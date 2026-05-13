/**
 * Structured logging wrapper.
 *
 * Tại sao? `firebase-functions/v2` đã có `logger` built-in, nhưng chúng ta
 * muốn ENFORCE consistent format ở mọi nơi:
 *   - Mỗi log có `event` (snake_case) để filter trong Cloud Logging
 *   - Tự động kèm `function_name`, `request_id` (correlation tracking)
 *   - Phân biệt rõ info/warn/error
 *
 * Khi deploy production, log đi vào Google Cloud Logging. Có thể tạo
 * log-based metrics + alerts từ field `event` (xem README).
 */
import { logger as fnLogger } from 'firebase-functions/v2';

export type LogContext = Record<string, string | number | boolean | null | undefined>;

/**
 * Sinh request ID ngắn cho correlation tracking (8 ký tự hex).
 * Dùng cho mỗi function call để nhóm các log line liên quan.
 */
export function newRequestId(): string {
  return Math.random().toString(16).slice(2, 10);
}

export class StructuredLogger {
  constructor(
    private readonly fnName: string,
    private readonly requestId: string
  ) {}

  private base(): LogContext {
    return { fn: this.fnName, rid: this.requestId };
  }

  info(event: string, ctx: LogContext = {}): void {
    fnLogger.info(event, { ...this.base(), event, ...ctx });
  }

  warn(event: string, ctx: LogContext = {}): void {
    fnLogger.warn(event, { ...this.base(), event, ...ctx });
  }

  error(event: string, ctx: LogContext = {}): void {
    fnLogger.error(event, { ...this.base(), event, ...ctx });
  }

  /** Log thời gian thực thi (ms). Dùng để monitor latency. */
  duration(event: string, startMs: number, ctx: LogContext = {}): void {
    this.info(event, { ...ctx, duration_ms: Date.now() - startMs });
  }
}

export function makeLogger(fnName: string): StructuredLogger {
  return new StructuredLogger(fnName, newRequestId());
}
