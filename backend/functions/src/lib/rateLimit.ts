/**
 * Token-bucket-style rate limiter dùng Firestore.
 *
 * Tại sao Firestore thay vì in-memory? Cloud Functions là stateless và scale
 * horizontal — instance này bị reset, instance khác không biết. Phải lưu state
 * tập trung. Firestore là lựa chọn hợp lý cho rate limit thấp như 3/phút.
 *
 * Schema: rateLimits/{key} = { count, windowStart }
 * Sliding window 60s: nếu windowStart < now - 60s → reset count.
 *
 * Để cleanup tự động, có thể bật Firestore TTL trên field windowStart (sau
 * 1 ngày tự xóa). Cấu hình trong README.
 */
import { HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

export interface RateLimitConfig {
  /** Tên rate limit (ví dụ 'sos', 'weather'). Dùng để namespace. */
  name: string;
  /** UID của user bị rate limit. */
  uid: string;
  /** Tối đa bao nhiêu lần trong window. */
  maxCount: number;
  /** Độ dài window (giây). */
  windowSec: number;
}

/**
 * Throw HttpsError('resource-exhausted') nếu vượt quota.
 * Atomic qua Firestore transaction → an toàn với concurrent calls.
 */
export async function enforceRateLimit(cfg: RateLimitConfig): Promise<void> {
  const db = getFirestore();
  const ref = db.doc(`rateLimits/${cfg.name}_${cfg.uid}`);
  const now = Date.now();
  const windowMs = cfg.windowSec * 1000;

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() as
      | { count: number; windowStart: number }
      | undefined;

    // Window đã hết hạn (hoặc chưa từng có) → reset
    if (!data || now - data.windowStart >= windowMs) {
      tx.set(ref, {
        count: 1,
        windowStart: now,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    // Trong window → check count
    if (data.count >= cfg.maxCount) {
      const retryAfterSec = Math.ceil(
        (data.windowStart + windowMs - now) / 1000
      );
      throw new HttpsError(
        'resource-exhausted',
        `Quá nhiều yêu cầu. Thử lại sau ${retryAfterSec}s.`,
        { retryAfterSec, limit: cfg.maxCount, windowSec: cfg.windowSec }
      );
    }

    // Còn quota → increment
    tx.update(ref, {
      count: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}
