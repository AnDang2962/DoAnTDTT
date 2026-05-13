/**
 * Module 3: Room/Member Service (v0.4)
 *
 * NEW v0.4: Hỗ trợ Route polyline cho Group Gap Detection chính xác.
 *   - createRoom giờ nhận thêm option `route?: { polyline, startName, endName }`
 *   - setRoomRoute(roomId, route) — leader có thể set/update route sau khi tạo room
 *
 * Schema Firestore:
 *   rooms/{roomId} {
 *     leaderId: string,
 *     members: string[],
 *     memberInfo: { [uid]: { displayName, role } },
 *     fcmTokens: { [uid]: string },
 *     createdAt: Timestamp,
 *     isActive: boolean,
 *
 *     route?: {                                    // NEW v0.4
 *       polyline: [{lat, lng}, ...],
 *       startName: string,
 *       endName: string,
 *       totalDistanceKm: number,
 *       updatedAt: Timestamp
 *     }
 *   }
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getDatabase } from 'firebase-admin/database';
import { requireAuth } from './lib/auth';
import { makeLogger } from './lib/logger';
import {
  requireString,
  requireRoomId,
  requirePolyline,
} from './lib/validate';
import { polylineLengthKm, Polyline } from './lib/geo';

function generateRoomCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

interface RouteInput {
  polyline: unknown;
  startName: unknown;
  endName: unknown;
}

/**
 * Validate route input + tự tính totalDistanceKm.
 */
function validateRouteInput(route: RouteInput): {
  polyline: Polyline;
  startName: string;
  endName: string;
  totalDistanceKm: number;
} {
  const polyline = requirePolyline(route.polyline);
  const startName = requireString(route.startName, 'route.startName', {
    minLen: 1,
    maxLen: 100,
  });
  const endName = requireString(route.endName, 'route.endName', {
    minLen: 1,
    maxLen: 100,
  });
  const totalDistanceKm = Math.round(polylineLengthKm(polyline) * 100) / 100;
  return { polyline, startName, endName, totalDistanceKm };
}

// ============================================================
// createRoom
// ============================================================
export const createRoom = onCall<
  {
    displayName: string;
    fcmToken: string;
    route?: RouteInput;
  },
  Promise<{ roomId: string; role: 'leader'; routeDistanceKm?: number }>
>({ region: 'asia-southeast1', timeoutSeconds: 30 }, async (request) => {
  const log = makeLogger('createRoom');
  const startMs = Date.now();
  const auth = requireAuth(request);

  const displayName = requireString(request.data?.displayName, 'displayName', {
    minLen: 1,
    maxLen: 50,
  });
  const fcmToken = requireString(request.data?.fcmToken, 'fcmToken', {
    minLen: 10,
    maxLen: 500,
  });

  // Optional route
  const routeInput = request.data?.route;
  const route = routeInput ? validateRouteInput(routeInput) : null;

  const db = getFirestore();
  const rtdb = getDatabase();

  let roomId = '';
  for (let i = 0; i < 5; i++) {
    const candidate = generateRoomCode();
    const existing = await db.doc(`rooms/${candidate}`).get();
    if (!existing.exists) {
      roomId = candidate;
      break;
    }
  }
  if (!roomId) {
    log.error('create_room_collision_exhausted');
    throw new HttpsError('internal', 'Không tạo được room code, thử lại');
  }

  const roomDoc: Record<string, unknown> = {
    leaderId: auth.uid,
    members: [auth.uid],
    memberInfo: {
      [auth.uid]: { displayName, role: 'leader' },
    },
    fcmTokens: { [auth.uid]: fcmToken },
    createdAt: FieldValue.serverTimestamp(),
    isActive: true,
  };
  if (route) {
    roomDoc.route = {
      polyline: route.polyline,
      startName: route.startName,
      endName: route.endName,
      totalDistanceKm: route.totalDistanceKm,
      updatedAt: FieldValue.serverTimestamp(),
    };
  }

  await Promise.all([
    db.doc(`rooms/${roomId}`).set(roomDoc),
    rtdb.ref(`roomMembers/${roomId}/${auth.uid}`).set(true),
  ]);

  log.duration('room_created', startMs, {
    roomId,
    uid: auth.uid,
    has_route: route !== null,
    route_km: route?.totalDistanceKm ?? 0,
  });

  return {
    roomId,
    role: 'leader',
    ...(route ? { routeDistanceKm: route.totalDistanceKm } : {}),
  };
});

// ============================================================
// setRoomRoute (NEW v0.4)
// ============================================================
/**
 * Leader update route sau khi đã tạo room.
 * Use case: leader muốn đổi đích đến giữa chuyến.
 */
export const setRoomRoute = onCall<
  { roomId: string; route: RouteInput },
  Promise<{ totalDistanceKm: number }>
>({ region: 'asia-southeast1', timeoutSeconds: 30 }, async (request) => {
  const log = makeLogger('setRoomRoute');
  const startMs = Date.now();
  const auth = requireAuth(request);

  const roomId = requireRoomId(request.data?.roomId);
  if (!request.data?.route) {
    throw new HttpsError('invalid-argument', 'Thiếu route');
  }
  const route = validateRouteInput(request.data.route);

  const db = getFirestore();
  const roomRef = db.doc(`rooms/${roomId}`);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) {
    throw new HttpsError('not-found', 'Room không tồn tại');
  }
  const room = roomSnap.data() as { leaderId?: string };
  if (room.leaderId !== auth.uid) {
    throw new HttpsError(
      'permission-denied',
      'Chỉ leader mới được set route'
    );
  }

  await roomRef.update({
    route: {
      polyline: route.polyline,
      startName: route.startName,
      endName: route.endName,
      totalDistanceKm: route.totalDistanceKm,
      updatedAt: FieldValue.serverTimestamp(),
    },
  });

  log.duration('route_set', startMs, {
    roomId,
    uid: auth.uid,
    points: route.polyline.length,
    km: route.totalDistanceKm,
  });

  return { totalDistanceKm: route.totalDistanceKm };
});

// ============================================================
// joinRoom
// ============================================================
export const joinRoom = onCall<
  { roomId: string; displayName: string; fcmToken: string },
  Promise<{ roomId: string; role: 'member' }>
>({ region: 'asia-southeast1', timeoutSeconds: 30 }, async (request) => {
  const log = makeLogger('joinRoom');
  const startMs = Date.now();
  const auth = requireAuth(request);

  const roomId = requireRoomId(request.data?.roomId);
  const displayName = requireString(request.data?.displayName, 'displayName', {
    minLen: 1,
    maxLen: 50,
  });
  const fcmToken = requireString(request.data?.fcmToken, 'fcmToken', {
    minLen: 10,
    maxLen: 500,
  });

  const db = getFirestore();
  const rtdb = getDatabase();
  const roomRef = db.doc(`rooms/${roomId}`);
  const roomSnap = await roomRef.get();

  if (!roomSnap.exists) {
    log.warn('join_room_not_found', { roomId, uid: auth.uid });
    throw new HttpsError('not-found', 'Room code không tồn tại');
  }
  const room = roomSnap.data() as { isActive?: boolean; members?: string[] };
  if (!room.isActive) {
    log.warn('join_room_inactive', { roomId, uid: auth.uid });
    throw new HttpsError('failed-precondition', 'Room đã đóng');
  }

  if (room.members?.includes(auth.uid)) {
    log.info('join_room_already_member', { roomId, uid: auth.uid });
    return { roomId, role: 'member' };
  }

  await Promise.all([
    roomRef.update({
      members: FieldValue.arrayUnion(auth.uid),
      [`memberInfo.${auth.uid}`]: { displayName, role: 'member' },
      [`fcmTokens.${auth.uid}`]: fcmToken,
    }),
    rtdb.ref(`roomMembers/${roomId}/${auth.uid}`).set(true),
  ]);

  log.duration('member_joined', startMs, { roomId, uid: auth.uid });
  return { roomId, role: 'member' };
});

// ============================================================
// leaveRoom
// ============================================================
export const leaveRoom = onCall<
  { roomId: string },
  Promise<{ success: true }>
>({ region: 'asia-southeast1', timeoutSeconds: 30 }, async (request) => {
  const log = makeLogger('leaveRoom');
  const startMs = Date.now();
  const auth = requireAuth(request);
  const roomId = requireRoomId(request.data?.roomId);

  const db = getFirestore();
  const rtdb = getDatabase();
  const roomRef = db.doc(`rooms/${roomId}`);
  const roomSnap = await roomRef.get();

  if (!roomSnap.exists) {
    throw new HttpsError('not-found', 'Room không tồn tại');
  }
  const room = roomSnap.data() as { leaderId?: string };
  if (room.leaderId === auth.uid) {
    log.warn('leave_room_leader_blocked', { roomId, uid: auth.uid });
    throw new HttpsError(
      'failed-precondition',
      'Leader không thể rời room. Hãy đóng room hoặc chuyển leader.'
    );
  }

  await Promise.all([
    roomRef.update({
      members: FieldValue.arrayRemove(auth.uid),
      [`memberInfo.${auth.uid}`]: FieldValue.delete(),
      [`fcmTokens.${auth.uid}`]: FieldValue.delete(),
    }),
    rtdb.ref(`roomMembers/${roomId}/${auth.uid}`).remove(),
    rtdb.ref(`gps/${roomId}/${auth.uid}`).remove(),
  ]);

  log.duration('member_left', startMs, { roomId, uid: auth.uid });
  return { success: true };
});
