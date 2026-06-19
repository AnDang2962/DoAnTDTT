/**
 * Module 4: Group Radar (v0.4)
 *
 * Algorithm 4 (Fatigue Score) — không thay đổi vs v0.3
 * Algorithm 2 (Group Gap Detection) — REWRITE để dùng polyline projection
 *
 * v0.3 cũ: heuristic "vĩ độ thấp nhất = Sweeper" — chỉ đúng cho route Bắc→Nam
 * v0.4 mới: chiếu mỗi GPS member lên polyline → progressKm → Sweeper = ai có
 *           progressKm THẤP NHẤT (đi xa nhất từ điểm xuất phát = ngược lại,
 *           tụt lại nhất = thấp nhất). Áp dụng đúng cho mọi hướng route.
 *
 * Fallback: nếu room chưa có route polyline → vẫn dùng heuristic vĩ độ cũ
 *           (graceful degradation, không fail toàn bộ feature).
 */
import { onCall } from 'firebase-functions/v2/https';
import { getDatabase } from 'firebase-admin/database';
import { getFirestore } from 'firebase-admin/firestore';
import { requireAuth } from './lib/auth';
import {
  haversineKm,
  projectOntoPolyline,
  Polyline,
} from './lib/geo';
import { makeLogger } from './lib/logger';
import { requireRoomId, requireNumber } from './lib/validate';

// ============================================================
// Algorithm 4: Fatigue Score (giữ nguyên v0.3)
// ============================================================
export const computeFatigueScore = onCall<
  { driveTimeMin: number; temperatureC?: number },
  Promise<{
    score: number;
    shouldRecommendRest: boolean;
    breakdown: { timeComponent: number; heatComponent: number };
  }>
>({ region: 'asia-southeast1', timeoutSeconds: 10 }, async (request) => {
  const log = makeLogger('computeFatigueScore');
  requireAuth(request);

  const driveTimeMin = requireNumber(
    request.data?.driveTimeMin,
    'driveTimeMin',
    { min: 0, max: 1440 }
  );
  const tempInput = request.data?.temperatureC;
  const temperatureC =
    typeof tempInput === 'number'
      ? requireNumber(tempInput, 'temperatureC', { min: -50, max: 60 })
      : 28.0;

  const timeComponent = driveTimeMin * 0.6;
  const heatExcess = Math.max(temperatureC - 28.0, 0);
  const heatComponent = heatExcess * 0.4;

  const rawScore = timeComponent + heatComponent;
  const score = Math.min(rawScore, 100);

  const result = {
    score: Math.round(score * 10) / 10,
    shouldRecommendRest: score > 70,
    breakdown: {
      timeComponent: Math.round(timeComponent * 10) / 10,
      heatComponent: Math.round(heatComponent * 10) / 10,
    },
  };

  log.info('fatigue_computed', {
    drive_min: driveTimeMin,
    temp_c: temperatureC,
    score: result.score,
    rest: result.shouldRecommendRest,
  });

  return result;
});

// ============================================================
// Algorithm 2: Group Gap Detection (v0.4 — polyline projection)
// ============================================================
interface GapResult {
  sweeper: { id: string; lat: number; lng: number; progressKm?: number } | null;
  gaps: Array<{ memberId: string; distanceKm: number }>;
  /** 'polyline' = dùng route.polyline | 'latitude' = fallback heuristic v0.3 */
  method: 'polyline' | 'latitude' | 'none';
  /** Off-route warnings: thành viên cách polyline > 1km (đi lệch route). */
  offRouteWarnings?: Array<{ memberId: string; offRouteKm: number }>;
}

interface GpsRecord {
  lat: number;
  lng: number;
  updatedAt: number;
}

export const checkGroupGap = onCall<
  { roomId: string; thresholdKm?: number },
  Promise<GapResult>
>({ region: 'asia-southeast1', timeoutSeconds: 10 }, async (request) => {
  const log = makeLogger('checkGroupGap');
  requireAuth(request);

  const roomId = requireRoomId(request.data?.roomId);
  const thresholdInput = request.data?.thresholdKm;
  const threshold =
    typeof thresholdInput === 'number'
      ? requireNumber(thresholdInput, 'thresholdKm', { min: 0.1, max: 100 })
      : 2.0;

  // === 1. Lấy active GPS từ RTDB ===
  const snap = await getDatabase().ref(`gps/${roomId}`).once('value');
  const gpsData = snap.val() as Record<string, GpsRecord> | null;

  if (!gpsData || Object.keys(gpsData).length < 2) {
    log.info('gap_skip_insufficient_members', { roomId });
    return { sweeper: null, gaps: [], method: 'none' };
  }

  const now = Date.now();
  const fiveMinAgo = now - 5 * 60 * 1000;
  const active = Object.entries(gpsData).filter(
    ([, pos]) => pos.updatedAt >= fiveMinAgo
  );

  if (active.length < 2) {
    log.info('gap_skip_few_active', {
      roomId,
      total: Object.keys(gpsData).length,
      active: active.length,
    });
    return { sweeper: null, gaps: [], method: 'none' };
  }

  // === 2. Đọc route polyline từ Firestore (nếu có) ===
  const roomSnap = await getFirestore().doc(`rooms/${roomId}`).get();
  const room = roomSnap.exists
    ? (roomSnap.data() as { route?: { polyline?: Polyline } })
    : {};
  const polyline = room.route?.polyline;

  if (polyline && polyline.length >= 2) {
    return computeGapWithPolyline(active, polyline, threshold, log, roomId);
  } else {
    log.info('gap_no_polyline_fallback', { roomId });
    return computeGapWithLatitude(active, threshold, log, roomId);
  }
});

/**
 * v0.4: Polyline-based detection — đúng cho mọi hướng route.
 *
 * Sweeper = thành viên có progressKm THẤP NHẤT (đi ít nhất từ start).
 * Gap = thành viên khác có (progressKm - sweeperProgress) > threshold,
 *       NHƯNG báo theo "cách Sweeper xa bao nhiêu" để khớp UX với v0.3.
 *
 * Cảnh báo off-route: nếu có thành viên cách polyline > 1km, log warning.
 */
function computeGapWithPolyline(
  active: [string, GpsRecord][],
  polyline: Polyline,
  threshold: number,
  log: ReturnType<typeof makeLogger>,
  roomId: string
): GapResult {
  // Project mỗi thành viên lên polyline
  const projected = active.map(([id, pos]) => {
    const proj = projectOntoPolyline({ lat: pos.lat, lng: pos.lng }, polyline);
    return {
      id,
      pos,
      progressKm: proj.progressKm,
      offRouteKm: proj.offRouteKm,
    };
  });

  // Sweeper = progressKm thấp nhất (đi ít nhất → tụt lại)
  const sweeper = projected.reduce((min, cur) =>
    cur.progressKm < min.progressKm ? cur : min
  );

  // Gaps = các thành viên đi xa hơn Sweeper > threshold
  const gaps = projected
    .filter((p) => p.id !== sweeper.id)
    .map((p) => ({
      memberId: p.id,
      distanceKm: Math.round((p.progressKm - sweeper.progressKm) * 100) / 100,
    }))
    .filter((g) => g.distanceKm > threshold);

  // Off-route warnings (cách polyline > 1km)
  const offRouteWarnings = projected
    .filter((p) => p.offRouteKm > 1.0)
    .map((p) => ({
      memberId: p.id,
      offRouteKm: Math.round(p.offRouteKm * 100) / 100,
    }));

  log.info('gap_computed', {
    roomId,
    method: 'polyline',
    active_count: active.length,
    gap_count: gaps.length,
    off_route_count: offRouteWarnings.length,
    threshold_km: threshold,
  });

  return {
    sweeper: {
      id: sweeper.id,
      lat: sweeper.pos.lat,
      lng: sweeper.pos.lng,
      progressKm: Math.round(sweeper.progressKm * 100) / 100,
    },
    gaps,
    method: 'polyline',
    ...(offRouteWarnings.length > 0 ? { offRouteWarnings } : {}),
  };
}

/**
 * v0.3 fallback: Heuristic vĩ độ thấp nhất.
 * Chỉ đúng cho route Bắc → Nam. Giữ lại để backward compatible khi room
 * chưa có route polyline (room mới tạo, leader chưa set route).
 */
function computeGapWithLatitude(
  active: [string, GpsRecord][],
  threshold: number,
  log: ReturnType<typeof makeLogger>,
  roomId: string
): GapResult {
  const [sweeperId, sweeperPos] = active.reduce((min, cur) =>
    cur[1].lat < min[1].lat ? cur : min
  );

  const gaps = active
    .filter(([id]) => id !== sweeperId)
    .map(([id, pos]) => ({
      memberId: id,
      distanceKm:
        Math.round(
          haversineKm(sweeperPos.lat, sweeperPos.lng, pos.lat, pos.lng) * 100
        ) / 100,
    }))
    .filter((g) => g.distanceKm > threshold);

  log.info('gap_computed', {
    roomId,
    method: 'latitude',
    active_count: active.length,
    gap_count: gaps.length,
    threshold_km: threshold,
  });

  return {
    sweeper: { id: sweeperId, lat: sweeperPos.lat, lng: sweeperPos.lng },
    gaps,
    method: 'latitude',
  };
}
