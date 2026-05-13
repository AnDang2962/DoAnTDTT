/**
 * Retry với exponential backoff cho external API calls.
 *
 * Default: 3 lần thử, delay 200ms → 400ms → 800ms (jittered ±25%).
 * Chỉ retry với lỗi mạng/5xx, không retry với 4xx (lỗi client).
 *
 * Dùng cho: Weather API (OpenWeatherMap), Gemini API.
 * KHÔNG dùng cho: FCM (đã có internal retry trong Firebase SDK).
 */
import { StructuredLogger } from './logger';

export interface RetryOptions {
  maxAttempts?: number;
  baseDelayMs?: number;
  /** Nếu trả true → retry. Mặc định: retry với network error & 5xx. */
  shouldRetry?: (err: unknown) => boolean;
}

const defaultShouldRetry = (err: unknown): boolean => {
  // axios error có .response?.status
  const e = err as { response?: { status?: number }; code?: string };
  // Network error (no response) → retry
  if (!e.response && e.code) return true;
  // 5xx → retry, 4xx → đừng (lỗi của ta)
  const status = e.response?.status;
  return typeof status === 'number' && status >= 500;
};

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

export async function retry<T>(
  fn: () => Promise<T>,
  opts: RetryOptions & { logger?: StructuredLogger; opName?: string } = {}
): Promise<T> {
  const maxAttempts = opts.maxAttempts ?? 3;
  const baseDelay = opts.baseDelayMs ?? 200;
  const shouldRetry = opts.shouldRetry ?? defaultShouldRetry;

  let lastErr: unknown;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      const isLast = attempt === maxAttempts;
      const willRetry = !isLast && shouldRetry(err);

      opts.logger?.warn('retry_attempt_failed', {
        op: opts.opName ?? 'unknown',
        attempt,
        will_retry: willRetry,
        error: err instanceof Error ? err.message : String(err),
      });

      if (!willRetry) break;

      // Jittered exponential backoff: base * 2^(attempt-1) * (0.75..1.25)
      const delay =
        baseDelay * Math.pow(2, attempt - 1) * (0.75 + Math.random() * 0.5);
      await sleep(delay);
    }
  }
  throw lastErr;
}
