/**
 * Module 5: AI Trip Copilot
 *
 * 2 chức năng:
 *   - voiceCommand: PA3 §1.1.2 + Algorithm 1
 *     Input: text (đã qua STT phía client) → Gemini Function Calling
 *     Output: structured action {type, params} cho client thực thi
 *
 *   - describeSosLocation: bonus cho Module 1 SOS
 *     Input: GPS lat/lng → Gemini sinh mô tả tiếng Việt thân thiện
 *     Output: text như "Cách QL1A khoảng 200m, gần ngã ba ABC"
 *
 * Cả hai đều:
 *   - Yêu cầu auth (chống abuse quota Gemini free tier)
 *   - Rate limit per-user
 *   - Structured logging để debug
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { Type, FunctionDeclaration } from '@google/genai';
import { requireAuth } from './lib/auth';
import { makeLogger } from './lib/logger';
import { enforceRateLimit } from './lib/rateLimit';
import { requireString, requireLatLng } from './lib/validate';
import { GEMINI_API_KEY, generateWithRetry } from './lib/gemini';

// ============================================================
// 5a. Voice Command (Function Calling)
// ============================================================
/**
 * Catalog các action mà voice command có thể trigger.
 * Phía Flutter map mỗi action → UI flow tương ứng.
 *
 * Khi muốn thêm action mới: thêm 1 entry FunctionDeclaration ở đây.
 * Gemini sẽ tự động chọn action phù hợp + extract parameters.
 */
const VOICE_ACTION_DECLARATIONS: FunctionDeclaration[] = [
  {
    name: 'send_sos',
    description:
      'Kích hoạt báo động khẩn cấp tới các thành viên trong nhóm. Dùng khi user nói "SOS", "cứu", "khẩn cấp", "tai nạn".',
    parameters: {
      type: Type.OBJECT,
      properties: {
        reason: {
          type: Type.STRING,
          description: 'Lý do ngắn gọn (nếu user có nói)',
        },
      },
    },
  },
  {
    name: 'find_nearby_place',
    description:
      'Tìm địa điểm gần vị trí hiện tại. Dùng khi user nói "tìm trạm xăng", "quán ăn gần đây", "nhà nghỉ".',
    parameters: {
      type: Type.OBJECT,
      properties: {
        place_type: {
          type: Type.STRING,
          enum: [
            'gas_station',
            'restaurant',
            'hotel',
            'rest_stop',
            'hospital',
            'atm',
            'mechanic',
          ],
          description: 'Loại địa điểm cần tìm',
        },
        radius_km: {
          type: Type.NUMBER,
          description: 'Bán kính tìm kiếm (km), mặc định 5',
        },
      },
      required: ['place_type'],
    },
  },
  {
    name: 'check_weather',
    description:
      'Kiểm tra thời tiết hiện tại hoặc dọc tuyến đường. Dùng khi user hỏi "thời tiết thế nào", "có mưa không".',
    parameters: { type: Type.OBJECT, properties: {} },
  },
  {
    name: 'check_group_status',
    description:
      'Kiểm tra trạng thái cả nhóm — ai đang ở đâu, có ai bị tụt lại không. Dùng khi user nói "đoàn đâu rồi", "kiểm tra nhóm".',
    parameters: { type: Type.OBJECT, properties: {} },
  },
  {
    name: 'recommend_rest',
    description:
      'Đề xuất nghỉ ngơi dựa trên fatigue score. Dùng khi user nói "có nên nghỉ không", "tôi mệt".',
    parameters: { type: Type.OBJECT, properties: {} },
  },
  {
    name: 'unknown',
    description:
      'Khi không hiểu rõ ý user hoặc câu nói không liên quan đến các action trên.',
    parameters: {
      type: Type.OBJECT,
      properties: {
        original_text: {
          type: Type.STRING,
          description: 'Câu gốc của user',
        },
      },
    },
  },
];

interface VoiceCommandResult {
  action: string;
  params: Record<string, unknown>;
  /** Câu trả lời tự nhiên hiển thị cho user (TTS sẽ đọc câu này). */
  responseText: string;
  /** Latency Gemini call (ms) — để monitor. */
  latencyMs: number;
}

export const voiceCommand = onCall<
  { text: string },
  Promise<VoiceCommandResult>
>(
  {
    region: 'asia-southeast1',
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 30,
    memory: '256MiB',
  },
  async (request) => {
    const log = makeLogger('voiceCommand');
    const startMs = Date.now();
    const auth = requireAuth(request);

    const text = requireString(request.data?.text, 'text', {
      minLen: 1,
      maxLen: 500,
    });

    // Rate limit: 30 req/phút (chống burst — nhưng vẫn đủ cho conversation tự nhiên)
    await enforceRateLimit({
      name: 'voice',
      uid: auth.uid,
      maxCount: 30,
      windowSec: 60,
    });

    log.info('voice_received', { text_len: text.length });

    const systemPrompt = [
      'Bạn là trợ lý ảo trên ứng dụng RouteMate dành cho nhóm đi du lịch xe máy/ô tô tại Việt Nam.',
      'Khi user nói/gõ một câu, hãy phân tích ý định và GỌI ĐÚNG MỘT function trong danh sách.',
      'Sau khi chọn function, trả về câu xác nhận tự nhiên bằng tiếng Việt (1-2 câu, không vượt 50 từ).',
      'Câu xác nhận sẽ được đọc cho user nghe, nên dùng giọng văn thân thiện như đang nói chuyện.',
    ].join(' ');

    const geminiStart = Date.now();
    let response;
    try {
      response = await generateWithRetry(
        {
          model: 'gemini-2.5-flash',
          contents: text,
          config: {
            systemInstruction: systemPrompt,
            temperature: 0.2, // thấp để deterministic, ít hallucinate
            tools: [{ functionDeclarations: VOICE_ACTION_DECLARATIONS }],
            toolConfig: {
              functionCallingConfig: { mode: 'ANY' as never }, // BẮT BUỘC phải gọi function
            },
          },
        },
        log
      );
    } catch (err) {
      log.error('gemini_failed', {
        error: err instanceof Error ? err.message : String(err),
      });
      throw new HttpsError('internal', 'AI service không phản hồi');
    }
    const geminiMs = Date.now() - geminiStart;

    // Parse function call từ response
    const candidate = response.candidates?.[0];
    const parts = candidate?.content?.parts ?? [];
    const fnCall = parts.find((p) => p.functionCall)?.functionCall;
    const textPart = parts.find((p) => p.text)?.text ?? '';

    if (!fnCall || !fnCall.name) {
      log.warn('voice_no_function_call', { text });
      return {
        action: 'unknown',
        params: { original_text: text },
        responseText: 'Xin lỗi, tôi chưa hiểu ý bạn. Bạn có thể nói lại được không?',
        latencyMs: geminiMs,
      };
    }

    const result: VoiceCommandResult = {
      action: fnCall.name,
      params: (fnCall.args as Record<string, unknown>) ?? {},
      responseText:
        textPart.trim() ||
        defaultResponseFor(fnCall.name, fnCall.args as Record<string, unknown>),
      latencyMs: geminiMs,
    };

    log.duration('voice_completed', startMs, {
      action: result.action,
      gemini_ms: geminiMs,
    });
    return result;
  }
);

/**
 * Câu trả lời mặc định khi Gemini không kèm text part.
 * Đảm bảo user luôn nghe được phản hồi, kể cả khi AI chỉ trả function call.
 */
function defaultResponseFor(
  action: string,
  params: Record<string, unknown>
): string {
  switch (action) {
    case 'send_sos':
      return 'Đã gửi tín hiệu SOS đến các thành viên trong nhóm.';
    case 'find_nearby_place': {
      const type = params.place_type as string | undefined;
      const map: Record<string, string> = {
        gas_station: 'trạm xăng',
        restaurant: 'quán ăn',
        hotel: 'khách sạn',
        rest_stop: 'điểm dừng nghỉ',
        hospital: 'bệnh viện',
        atm: 'cây ATM',
        mechanic: 'tiệm sửa xe',
      };
      const label = type && map[type] ? map[type] : 'địa điểm';
      return `Đang tìm ${label} gần đây cho bạn.`;
    }
    case 'check_weather':
      return 'Đang kiểm tra thời tiết khu vực này.';
    case 'check_group_status':
      return 'Đang kiểm tra vị trí cả nhóm.';
    case 'recommend_rest':
      return 'Đang phân tích mức độ mệt mỏi của bạn.';
    default:
      return 'Đã nhận yêu cầu của bạn.';
  }
}

// ============================================================
// 5b. Smart SOS Location Description (text generation)
// ============================================================
/**
 * Khi SOS được kích hoạt, sinh mô tả vị trí thân thiện bằng tiếng Việt
 * dựa trên GPS coordinates. Đính kèm vào notification để người nhận biết
 * NGAY người gặp nạn ở đâu, không cần mở map.
 *
 * Lý do tách thành function riêng (không gọi trong sendSOS):
 *   - sendSOS phải FAST (< 2s, theo NFR PA3). Gọi Gemini thêm 1-3s.
 *   - Cho phép Flutter app gọi async sau khi sendSOS xong, update notification sau.
 */
export const describeSosLocation = onCall<
  { lat: number; lng: number; nearbyContext?: string },
  Promise<{ description: string; latencyMs: number }>
>(
  {
    region: 'asia-southeast1',
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 15,
    memory: '256MiB',
  },
  async (request) => {
    const log = makeLogger('describeSosLocation');
    const startMs = Date.now();
    const auth = requireAuth(request);

    const { lat, lng } = requireLatLng(request.data ?? {});
    const nearbyContext =
      typeof request.data?.nearbyContext === 'string'
        ? request.data.nearbyContext.slice(0, 200)
        : '';

    await enforceRateLimit({
      name: 'sos_describe',
      uid: auth.uid,
      maxCount: 10,
      windowSec: 60,
    });

    const prompt = [
      `Tọa độ GPS: ${lat.toFixed(5)}, ${lng.toFixed(5)} (Việt Nam).`,
      nearbyContext ? `Bối cảnh thêm: ${nearbyContext}` : '',
      '',
      'Hãy mô tả vị trí này bằng tiếng Việt trong 1-2 câu ngắn (tối đa 30 từ),',
      'theo phong cách dễ hiểu cho người Việt — ưu tiên các điểm mốc giao thông',
      '(quốc lộ, ngã ba, thành phố/tỉnh gần nhất). Không lặp lại tọa độ.',
      'Ví dụ: "Khu vực Phan Thiết, Bình Thuận, gần QL1A, cách trung tâm TP khoảng 5km".',
    ].join('\n');

    const geminiStart = Date.now();
    let response;
    try {
      response = await generateWithRetry(
        {
          model: 'gemini-2.5-flash',
          contents: prompt,
          config: { temperature: 0.4, maxOutputTokens: 100 },
        },
        log
      );
    } catch (err) {
      log.error('gemini_failed', {
        error: err instanceof Error ? err.message : String(err),
      });
      // Fallback: trả mô tả tối giản, không fail toàn bộ SOS flow
      return {
        description: `Vị trí GPS ${lat.toFixed(4)}, ${lng.toFixed(4)}`,
        latencyMs: Date.now() - geminiStart,
      };
    }
    const geminiMs = Date.now() - geminiStart;

    const text = response.text?.trim() ?? '';
    const description =
      text || `Vị trí GPS ${lat.toFixed(4)}, ${lng.toFixed(4)}`;

    log.duration('sos_description_completed', startMs, {
      gemini_ms: geminiMs,
      desc_len: description.length,
    });

    return { description, latencyMs: geminiMs };
  }
);
