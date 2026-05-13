/**
 * Module 1: SOS Broadcast (HARDENED v0.2)
 *
 * Implement Algorithm 3 (PA3) - Network-aware Fallback + production safeguards:
 *   ✓ Rate limit 3 SOS/phút/user (chống spam/abuse)
 *   ✓ Idempotency keys (chống double-send khi client retry network)
 *   ✓ Dead FCM token cleanup (tự xóa token hết hạn)
 *   ✓ Structured logging (event-based, có request_id correlation)
 *   ✓ Strict input validation
 *   ✓ Audit log đầy đủ trong Firestore
 *
 * Phía client (Flutter):
 *   IF online → call này
 *   ELSE → fallback SMS URI (không qua server)
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import {
  getFirestore,
  FieldValue,
  Firestore,
} from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { requireAuth } from './lib/auth';
import { makeLogger } from './lib/logger';
import { enforceRateLimit } from './lib/rateLimit';
import {
  requireRoomId,
  requireLatLng,
  requireString,
} from './lib/validate';

interface SosRequest {
  roomId: string;
  lat: number;
  lng: number;
  /** UUID v4 do client sinh. Cùng key → cùng kết quả, không gửi lại FCM. */
  idempotencyKey: string;
}

interface SosResult {
  status: 'DELIVERED' | 'PARTIAL' | 'FAILED' | 'CACHED';
  deliveredCount: number;
  failedCount: number;
  method: 'FCM' | 'NONE';
  cleanedTokens?: number;
}

// FCM error codes báo hiệu token chết → cần xóa
const DEAD_TOKEN_ERRORS = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

export const sendSOS = onCall<SosRequest, Promise<SosResult>>(
  { region: 'asia-southeast1', timeoutSeconds: 30, memory: '256MiB' },
  async (request) => {
    const log = makeLogger('sendSOS');
    const startMs = Date.now();
    const auth = requireAuth(request);

    // === 1. Validate input (fail-fast) ===
    const roomId = requireRoomId(request.data?.roomId);
    const { lat, lng } = requireLatLng(request.data ?? {});
    const idempotencyKey = requireString(
      request.data?.idempotencyKey,
      'idempotencyKey',
      { minLen: 8, maxLen: 64 }
    );

    log.info('sos_received', { roomId, uid: auth.uid });

    // === 2. Rate limit (3 SOS/phút/user) ===
    await enforceRateLimit({
      name: 'sos',
      uid: auth.uid,
      maxCount: 3,
      windowSec: 60,
    });

    // === 3. Idempotency check ===
    const db = getFirestore();
    const idemRef = db.doc(`sosIdempotency/${auth.uid}_${idempotencyKey}`);
    const idemSnap = await idemRef.get();
    if (idemSnap.exists) {
      const cached = idemSnap.data() as SosResult;
      log.info('sos_idempotent_replay', { roomId, uid: auth.uid });
      return { ...cached, status: 'CACHED' };
    }

    // === 4. Verify membership ===
    const roomRef = db.doc(`rooms/${roomId}`);
    const roomSnap = await roomRef.get();
    if (!roomSnap.exists) {
      log.warn('sos_room_not_found', { roomId, uid: auth.uid });
      throw new HttpsError('not-found', 'Room không tồn tại');
    }
    const room = roomSnap.data() as {
      members?: string[];
      fcmTokens?: Record<string, string>;
    };
    if (!room.members?.includes(auth.uid)) {
      log.warn('sos_not_member', { roomId, uid: auth.uid });
      throw new HttpsError(
        'permission-denied',
        'Bạn không phải thành viên của room này'
      );
    }

    // === 5. Multicast FCM ===
    const tokenMap = room.fcmTokens ?? {};
    const tokens = Object.values(tokenMap).filter((t): t is string => !!t);
    if (tokens.length === 0) {
      log.warn('sos_no_tokens', { roomId, uid: auth.uid });
      const result: SosResult = {
        status: 'FAILED',
        deliveredCount: 0,
        failedCount: 0,
        method: 'NONE',
      };
      await idemRef.set({
        ...result,
        createdAt: FieldValue.serverTimestamp(),
      });
      return result;
    }

    let fcmResult;
    try {
      fcmResult = await getMessaging().sendEachForMulticast({
        tokens,
        notification: {
          title: '🆘 SOS!',
          body: 'Một thành viên trong nhóm cần giúp đỡ!',
        },
        data: {
          type: 'SOS',
          senderId: auth.uid,
          senderName: auth.name ?? '',
          lat: String(lat),
          lng: String(lng),
          timestamp: String(Date.now()),
        },
        android: { priority: 'high' },
        apns: {
          payload: { aps: { sound: 'default', contentAvailable: true } },
        },
      });
    } catch (err) {
      log.error('sos_fcm_exception', {
        error: err instanceof Error ? err.message : String(err),
      });
      throw new HttpsError('internal', 'Lỗi gửi SOS qua FCM');
    }

    // === 6. Cleanup dead tokens ===
    const cleanedTokens = await cleanupDeadTokens(
      db,
      roomRef,
      tokenMap,
      tokens,
      fcmResult.responses
    );

    // === 7. Audit log + idempotency cache ===
    const result: SosResult = {
      status: fcmResult.failureCount === 0 ? 'DELIVERED' : 'PARTIAL',
      deliveredCount: fcmResult.successCount,
      failedCount: fcmResult.failureCount,
      method: 'FCM',
      cleanedTokens,
    };

    await Promise.all([
      db.collection(`rooms/${roomId}/sosLogs`).add({
        senderId: auth.uid,
        idempotencyKey,
        lat,
        lng,
        deliveredCount: fcmResult.successCount,
        failedCount: fcmResult.failureCount,
        cleanedTokens,
        createdAt: FieldValue.serverTimestamp(),
      }),
      idemRef.set({
        ...result,
        createdAt: FieldValue.serverTimestamp(),
      }),
    ]);

    log.duration('sos_completed', startMs, {
      roomId,
      delivered: result.deliveredCount,
      failed: result.failedCount,
      cleaned: cleanedTokens,
    });

    return result;
  }
);

/**
 * Quét responses từ FCM, xóa các token bị "chết" khỏi Firestore.
 * Trả về số token đã xóa.
 */
async function cleanupDeadTokens(
  db: Firestore,
  roomRef: FirebaseFirestore.DocumentReference,
  tokenMap: Record<string, string>,
  orderedTokens: string[],
  responses: { success: boolean; error?: { code: string } }[]
): Promise<number> {
  // Map ngược: token → uid (để biết xóa field nào)
  const tokenToUid = new Map<string, string>();
  for (const [uid, token] of Object.entries(tokenMap)) {
    if (token) tokenToUid.set(token, uid);
  }

  const updates: Record<string, FirebaseFirestore.FieldValue> = {};
  let cleaned = 0;
  for (let i = 0; i < responses.length; i++) {
    const r = responses[i];
    if (r.success) continue;
    const code = r.error?.code;
    if (code && DEAD_TOKEN_ERRORS.has(code)) {
      const deadToken = orderedTokens[i];
      const uid = tokenToUid.get(deadToken);
      if (uid) {
        updates[`fcmTokens.${uid}`] = FieldValue.delete();
        cleaned++;
      }
    }
  }
  if (cleaned > 0) {
    await roomRef.update(updates);
  }
  return cleaned;
}
