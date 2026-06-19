/**
 * Gemini API client wrapper.
 *
 * Tại sao có file này thay vì gọi @google/genai trực tiếp ở các function?
 *   - Giấu API key qua Firebase Secrets (Anthropic-grade security)
 *   - Lazy init: tạo client 1 lần per function instance, reuse cho các call sau
 *   - Retry logic shared (network blip, 5xx)
 *   - Centralize logging — debug 1 chỗ
 */
import { GoogleGenAI } from '@google/genai';
import { defineSecret } from 'firebase-functions/params';
import { retry } from './retry';
import { StructuredLogger } from './logger';

export const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

let cachedClient: GoogleGenAI | null = null;

/**
 * Get singleton Gemini client. Khởi tạo lazy ở lần gọi đầu.
 * Cloud Functions instance reuse giữa các invocations cùng ấm máy → tiết kiệm.
 */
export function getGeminiClient(): GoogleGenAI {
  if (cachedClient) return cachedClient;
  const apiKey = GEMINI_API_KEY.value();
  if (!apiKey) {
    throw new Error('GEMINI_API_KEY chưa cấu hình');
  }
  cachedClient = new GoogleGenAI({ apiKey });
  return cachedClient;
}

/**
 * Wrapper với retry tự động cho generateContent.
 * Dùng cho mọi call Gemini trong project.
 */
export async function generateWithRetry(
  params: Parameters<GoogleGenAI['models']['generateContent']>[0],
  log: StructuredLogger
): Promise<Awaited<ReturnType<GoogleGenAI['models']['generateContent']>>> {
  const client = getGeminiClient();
  return retry(() => client.models.generateContent(params), {
    maxAttempts: 3,
    baseDelayMs: 500,
    logger: log,
    opName: 'gemini_generate',
    shouldRetry: (err) => {
      // Gemini errors thường có .status hoặc message
      const e = err as { status?: number; message?: string };
      if (e.status && e.status >= 500) return true;
      if (e.message?.toLowerCase().includes('network')) return true;
      if (e.message?.toLowerCase().includes('timeout')) return true;
      return false;
    },
  });
}
