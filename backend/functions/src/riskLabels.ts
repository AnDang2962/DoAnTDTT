/**
 * Module 6: Risk Labels (Crowdsourced Hazards) — v0.5 tap-first UX
 *
 * UX: Leader đang lái xe, không gõ chữ. 2 cách báo cáo:
 *   1. CHẠM UI (chính): chạm icon category → chạm subtype → save
 *   2. VOICE (phụ, khi tay bận): nói vài từ → AI map vào subtype có sẵn
 *
 * Cả 2 cách đều save chung schema vào riskLabels/.
 *
 * Cloud Functions trong module này:
 *   - reportRiskLabel(roomId, category, subtype, lat, lng, note?)
 *       UX chạm UI. Không gọi AI. Nhanh, deterministic.
 *
 *   - parseRiskFromVoice(roomId, voiceText, lat, lng)
 *       UX voice. AI chọn 1 subtype trong list có sẵn. Trả về preview
 *       để client confirm (hoặc auto-save nếu confidence cao).
 *
 *   - getRiskLabelsNearRoute(polyline OR roomId, bufferKm, minSeverity)
 *       Đọc — dùng polyline projection để chỉ trả risks DỌC route đã định tuyến.
 *
 * Time decay: linear theo subtype config (xem lib/riskTaxonomy.ts).
 * Permission: chỉ leader của room mới report được.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { Type, FunctionDeclaration } from '@google/genai';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { requireAuth } from './lib/auth';
import { makeLogger } from './lib/logger';
import { enforceRateLimit } from './lib/rateLimit';
import {
  requireString,
  requireRoomId,
  requirePolyline,
  requireNumber,
} from './lib/validate';
import { GEMINI_API_KEY, generateWithRetry } from './lib/gemini';
import {
  projectOntoPolyline,
  Polyline,
} from './lib/geo';
import {
  ALL_SUBTYPES,
  RISK_TAXONOMY,
  findSubtypeConfig,
  computeEffectiveSeverity,
  RiskCategory,
} from './lib/riskTaxonomy';

// ============================================================
// Helper: assert caller là leader của room
// ============================================================
async function assertLeader(
  uid: string,
  roomId: string,
  log: ReturnType<typeof makeLogger>
): Promise<void> {
  const db = getFirestore();
  const roomSnap = await db.doc(`rooms/${roomId}`).get();
  if (!roomSnap.exists) {
    throw new HttpsError('not-found', 'Room không tồn tại');
  }
  const room = roomSnap.data() as { leaderId?: string };
  if (room.leaderId !== uid) {
    log.warn('risk_not_leader', { roomId, uid });
    throw new HttpsError(
      'permission-denied',
      'Chỉ leader mới được report risk'
    );
  }
}

// ============================================================
// Helper: save 1 risk label vào Firestore
// ============================================================
async function saveRiskLabel(params: {
  category: RiskCategory;
  subtype: string;
  lat: number;
  lng: number;
  reportedBy: string;
  reportedRoomId: string;
  note?: string;
  severityOverride?: number;
  source: 'tap' | 'voice';
  voiceRawText?: string;
}): Promise<{ id: string; severity: number; expiresAt: Timestamp }> {
  const found = findSubtypeConfig(params.category, params.subtype);
  if (!found) {
    throw new HttpsError(
      'invalid-argument',
      `Cặp category="${params.category}" subtype="${params.subtype}" không hợp lệ`
    );
  }
  const cfg = found.config;
  const severity =
    typeof params.severityOverride === 'number'
      ? Math.max(0.1, Math.min(1.0, params.severityOverride))
      : cfg.defaultSeverity;

  const nowMs = Date.now();
  const expiresAt = Timestamp.fromMillis(
    nowMs + cfg.maxLifetimeH * 3600 * 1000
  );

  const db = getFirestore();
  const ref = db.collection('riskLabels').doc();
  await ref.set({
    category: params.category,
    subtype: params.subtype,
    baseSeverity: severity,
    lat: params.lat,
    lng: params.lng,
    note: params.note ?? '',
    reportedBy: params.reportedBy,
    reportedRoomId: params.reportedRoomId,
    source: params.source,
    voiceRawText: params.voiceRawText ?? '',
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
  });

  return { id: ref.id, severity, expiresAt };
}

// ============================================================
// 6a. reportRiskLabel — UX chạm UI (chính)
// ============================================================
interface ReportRiskLabelRequest {
  roomId: string;
  category: string;
  subtype: string;
  lat: number;
  lng: number;
  /** Note ngắn tùy chọn (chỉ gõ được khi đã dừng xe, hiếm dùng) */
  note?: string;
}

export const reportRiskLabel = onCall<
  ReportRiskLabelRequest,
  Promise<{
    id: string;
    category: string;
    subtype: string;
    severity: number;
  }>
>({ region: 'asia-southeast1', timeoutSeconds: 15 }, async (request) => {
  const log = makeLogger('reportRiskLabel');
  const startMs = Date.now();
  const auth = requireAuth(request);

  const roomId = requireRoomId(request.data?.roomId);
  const category = requireString(request.data?.category, 'category', {
    minLen: 1,
    maxLen: 30,
  });
  const subtype = requireString(request.data?.subtype, 'subtype', {
    minLen: 1,
    maxLen: 30,
  });
  const lat = requireNumber(request.data?.lat, 'lat', { min: -90, max: 90 });
  const lng = requireNumber(request.data?.lng, 'lng', { min: -180, max: 180 });
  const note =
    typeof request.data?.note === 'string'
      ? request.data.note.slice(0, 200)
      : '';

  // Validate taxonomy
  if (!findSubtypeConfig(category, subtype)) {
    throw new HttpsError(
      'invalid-argument',
      `Cặp ${category}/${subtype} không hợp lệ. Xem RISK_TAXONOMY.`
    );
  }

  await enforceRateLimit({
    name: 'risk_report',
    uid: auth.uid,
    maxCount: 20,
    windowSec: 60,
  });

  await assertLeader(auth.uid, roomId, log);

  const saved = await saveRiskLabel({
    category: category as RiskCategory,
    subtype,
    lat,
    lng,
    reportedBy: auth.uid,
    reportedRoomId: roomId,
    note,
    source: 'tap',
  });

  log.duration('risk_tap_reported', startMs, {
    roomId,
    uid: auth.uid,
    category,
    subtype,
  });

  return { id: saved.id, category, subtype, severity: saved.severity };
});

// ============================================================
// 6b. parseRiskFromVoice — UX voice (phụ)
// ============================================================
/**
 * Gemini Function Calling — chỉ chọn 1 subtype trong list có sẵn.
 * Đây KHÔNG phải hệ thống NLP free-form parse, mà là classifier.
 */
const VOICE_RISK_DECLARATION: FunctionDeclaration = {
  name: 'classify_risk',
  description:
    'Phân loại câu nói ngắn của leader thành đúng 1 risk subtype trong danh sách có sẵn. Nếu không khớp subtype nào, trả autoSave=false và lý do.',
  parameters: {
    type: Type.OBJECT,
    properties: {
      category: {
        type: Type.STRING,
        enum: Object.keys(RISK_TAXONOMY),
        description: 'Category chính',
      },
      subtype: {
        type: Type.STRING,
        description:
          'Subtype cụ thể, phải nằm trong list subtype của category đã chọn',
      },
      confidence: {
        type: Type.NUMBER,
        description: 'Độ tự tin 0-1. ≥ 0.8 = auto-save, < 0.8 = preview chờ confirm',
      },
      autoSave: {
        type: Type.BOOLEAN,
        description: 'true nếu confidence cao + không mơ hồ, false nếu cần confirm',
      },
      reason: {
        type: Type.STRING,
        description: 'Giải thích ngắn (max 80 ký tự) tại sao chọn subtype này',
      },
    },
    required: ['category', 'subtype', 'confidence', 'autoSave', 'reason'],
  },
};

/**
 * Build system prompt với danh sách subtype hợp lệ inline → Gemini buộc
 * phải chọn từ list này.
 */
function buildVoiceSystemPrompt(): string {
  const lines: string[] = [
    'Bạn là classifier phân loại báo cáo nguy hiểm giao thông từ leader đoàn phượt VN.',
    'Leader đang lái xe nói vài từ ngắn → bạn map vào DUY NHẤT 1 subtype trong danh sách:',
    '',
  ];
  for (const [cat, info] of Object.entries(RISK_TAXONOMY)) {
    lines.push(`${cat} (${info.vi}):`);
    for (const s of info.subtypes) {
      lines.push(`  - ${s.subtype} = ${s.vi}`);
    }
  }
  lines.push('');
  lines.push('Luôn gọi function classify_risk. Nếu không rõ ràng (ví dụ "ờ chỗ này lạ"), set autoSave=false để client hỏi lại leader.');
  return lines.join('\n');
}

interface ParseVoiceRequest {
  roomId: string;
  voiceText: string;
  lat: number;
  lng: number;
}

interface ParseVoiceResult {
  category: string;
  subtype: string;
  vi: string;
  confidence: number;
  autoSaved: boolean;
  reason: string;
  geminiMs: number;
  /** Chỉ có khi autoSaved=true */
  id?: string;
  severity?: number;
}

export const parseRiskFromVoice = onCall<
  ParseVoiceRequest,
  Promise<ParseVoiceResult>
>(
  {
    region: 'asia-southeast1',
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 30,
    memory: '256MiB',
  },
  async (request) => {
    const log = makeLogger('parseRiskFromVoice');
    const startMs = Date.now();
    const auth = requireAuth(request);

    const roomId = requireRoomId(request.data?.roomId);
    const voiceText = requireString(request.data?.voiceText, 'voiceText', {
      minLen: 2,
      maxLen: 200,
    });
    const lat = requireNumber(request.data?.lat, 'lat', { min: -90, max: 90 });
    const lng = requireNumber(request.data?.lng, 'lng', { min: -180, max: 180 });

    await enforceRateLimit({
      name: 'risk_voice',
      uid: auth.uid,
      maxCount: 15,
      windowSec: 60,
    });

    await assertLeader(auth.uid, roomId, log);

    // Gọi Gemini classifier
    const geminiStart = Date.now();
    let response;
    try {
      response = await generateWithRetry(
        {
          model: 'gemini-2.5-flash',
          contents: voiceText,
          config: {
            systemInstruction: buildVoiceSystemPrompt(),
            temperature: 0.1,
            tools: [{ functionDeclarations: [VOICE_RISK_DECLARATION] }],
            toolConfig: {
              functionCallingConfig: { mode: 'ANY' as never },
            },
          },
        },
        log
      );
    } catch (err) {
      log.error('risk_voice_gemini_failed', {
        error: err instanceof Error ? err.message : String(err),
      });
      throw new HttpsError('internal', 'AI service không phản hồi');
    }
    const geminiMs = Date.now() - geminiStart;

    const parts = response.candidates?.[0]?.content?.parts ?? [];
    const fnCall = parts.find((p) => p.functionCall)?.functionCall;
    const args = (fnCall?.args ?? {}) as {
      category?: string;
      subtype?: string;
      confidence?: number;
      autoSave?: boolean;
      reason?: string;
    };

    const category = args.category ?? '';
    const subtype = args.subtype ?? '';
    const found = findSubtypeConfig(category, subtype);

    if (!found) {
      log.warn('risk_voice_invalid_classification', {
        voiceText,
        ai_category: category,
        ai_subtype: subtype,
      });
      return {
        category: 'HAZARD_OTHER',
        subtype: 'dark_road',
        vi: 'Không rõ',
        confidence: 0,
        autoSaved: false,
        reason: 'AI không phân loại được — vui lòng chạm UI để chọn thủ công',
        geminiMs,
      };
    }

    const confidence = Math.max(
      0,
      Math.min(1, typeof args.confidence === 'number' ? args.confidence : 0.5)
    );
    // Auto-save chỉ khi AI tự confirm + confidence cao
    const shouldAutoSave = args.autoSave === true && confidence >= 0.8;

    const result: ParseVoiceResult = {
      category: found.category,
      subtype: found.config.subtype,
      vi: found.config.vi,
      confidence,
      autoSaved: false,
      reason: (args.reason ?? '').slice(0, 100),
      geminiMs,
    };

    if (shouldAutoSave) {
      const saved = await saveRiskLabel({
        category: found.category,
        subtype: found.config.subtype,
        lat,
        lng,
        reportedBy: auth.uid,
        reportedRoomId: roomId,
        source: 'voice',
        voiceRawText: voiceText,
      });
      result.autoSaved = true;
      result.id = saved.id;
      result.severity = saved.severity;
    }

    log.duration('risk_voice_classified', startMs, {
      roomId,
      voice_len: voiceText.length,
      ai_category: found.category,
      ai_subtype: found.config.subtype,
      confidence,
      auto_saved: result.autoSaved,
      gemini_ms: geminiMs,
    });

    return result;
  }
);

// ============================================================
// 6c. getRiskLabelsNearRoute — query risks DỌC polyline
// ============================================================
interface RiskNearbyResult {
  id: string;
  category: RiskCategory;
  subtype: string;
  vi: string;
  severity: number; // effective sau decay
  baseSeverity: number;
  lat: number;
  lng: number;
  note: string;
  createdAtMs: number;
  /** Khoảng cách (km) tới điểm gần nhất trên polyline */
  distanceFromRouteKm: number;
  /** Vị trí dọc route (km từ điểm xuất phát) — để FE biết "khi chạy đến km X sẽ gặp risk" */
  progressKm: number;
}

export const getRiskLabelsNearRoute = onCall<
  {
    polyline?: unknown;
    roomId?: string;
    bufferKm?: number;
    minSeverity?: number;
  },
  Promise<{ count: number; risks: RiskNearbyResult[] }>
>({ region: 'asia-southeast1', timeoutSeconds: 30 }, async (request) => {
  const log = makeLogger('getRiskLabelsNearRoute');
  const startMs = Date.now();
  requireAuth(request);

  // Lấy polyline: ưu tiên truyền trực tiếp, fallback lấy từ roomId
  let polyline: Polyline;
  if (request.data?.polyline) {
    polyline = requirePolyline(request.data.polyline);
  } else if (request.data?.roomId) {
    const roomId = requireRoomId(request.data.roomId);
    const roomSnap = await getFirestore().doc(`rooms/${roomId}`).get();
    if (!roomSnap.exists) {
      throw new HttpsError('not-found', 'Room không tồn tại');
    }
    const room = roomSnap.data() as { route?: { polyline?: Polyline } };
    if (!room.route?.polyline || room.route.polyline.length < 2) {
      throw new HttpsError(
        'failed-precondition',
        'Room chưa có route polyline. Leader cần setRoomRoute trước.'
      );
    }
    polyline = room.route.polyline;
  } else {
    throw new HttpsError(
      'invalid-argument',
      'Phải truyền hoặc polyline hoặc roomId'
    );
  }

  const bufferKm =
    typeof request.data?.bufferKm === 'number'
      ? requireNumber(request.data.bufferKm, 'bufferKm', { min: 0.1, max: 50 })
      : 3.0; // 3km mỗi bên (đủ để cover lệch route nhẹ)
  const minSeverity =
    typeof request.data?.minSeverity === 'number'
      ? requireNumber(request.data.minSeverity, 'minSeverity', {
          min: 0,
          max: 1,
        })
      : 0.1;

  // Bounding box query
  const lats = polyline.map((p) => p.lat);
  const lngs = polyline.map((p) => p.lng);
  const latBuffer = bufferKm / 111;
  const lngBuffer = bufferKm / 109;
  const minLat = Math.min(...lats) - latBuffer;
  const maxLat = Math.max(...lats) + latBuffer;
  const minLng = Math.min(...lngs) - lngBuffer;
  const maxLng = Math.max(...lngs) + lngBuffer;

  const nowMs = Date.now();
  const snap = await getFirestore()
    .collection('riskLabels')
    .where('lat', '>=', minLat)
    .where('lat', '<=', maxLat)
    .where('expiresAt', '>', Timestamp.fromMillis(nowMs))
    .limit(500)
    .get();

  const risks: RiskNearbyResult[] = [];
  for (const doc of snap.docs) {
    const d = doc.data() as {
      category: string;
      subtype: string;
      baseSeverity: number;
      lat: number;
      lng: number;
      note: string;
      createdAt: Timestamp;
    };

    if (d.lng < minLng || d.lng > maxLng) continue;

    const found = findSubtypeConfig(d.category, d.subtype);
    if (!found) continue; // skip records với schema cũ/lỗi

    const createdAtMs = d.createdAt?.toMillis() ?? 0;
    const effective = computeEffectiveSeverity(
      d.baseSeverity,
      found.config,
      createdAtMs,
      nowMs
    );
    if (effective < minSeverity) continue;

    // Project điểm risk lên polyline để có progressKm + filter bufferKm chính xác
    const proj = projectOntoPolyline({ lat: d.lat, lng: d.lng }, polyline);
    if (proj.offRouteKm > bufferKm) continue;

    risks.push({
      id: doc.id,
      category: found.category,
      subtype: found.config.subtype,
      vi: found.config.vi,
      severity: Math.round(effective * 100) / 100,
      baseSeverity: d.baseSeverity,
      lat: d.lat,
      lng: d.lng,
      note: d.note ?? '',
      createdAtMs,
      distanceFromRouteKm: Math.round(proj.offRouteKm * 100) / 100,
      progressKm: Math.round(proj.progressKm * 100) / 100,
    });
  }

  // Sort theo progressKm tăng dần (risks sắp xuất hiện theo thứ tự lái xe)
  risks.sort((a, b) => a.progressKm - b.progressKm);

  log.duration('risks_queried', startMs, {
    polyline_points: polyline.length,
    buffer_km: bufferKm,
    found: risks.length,
    scanned: snap.size,
  });

  return { count: risks.length, risks };
});

// ============================================================
// 6d. getRiskTaxonomy — public endpoint cho FE lấy danh sách icons
// ============================================================
/**
 * FE có thể hardcode taxonomy hoặc gọi endpoint này khi khởi động app.
 * Trả về cấu trúc đầy đủ để render UI buttons.
 */
export const getRiskTaxonomy = onCall<
  Record<string, never>,
  Promise<typeof RISK_TAXONOMY & { allSubtypes: typeof ALL_SUBTYPES }>
>({ region: 'asia-southeast1', timeoutSeconds: 5 }, async (request) => {
  requireAuth(request);
  return {
    ...RISK_TAXONOMY,
    allSubtypes: ALL_SUBTYPES,
  };
});
