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
import { RISK_TAXONOMY, findSubtypeConfig } from './lib/riskTaxonomy';
import { saveRiskLabel, assertLeader } from './riskLabels';

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
    name: 'report_risk',
    description:
      'Báo cáo nguy hiểm/sự cố trên đường. Dùng khi user đề cập: ổ gà, ngập nước, trơn, sương mù, tai nạn, tắc đường, chốt CSGT, sạt lở, cây đổ, v.v.',
    parameters: {
      type: Type.OBJECT,
      properties: {
        category: {
          type: Type.STRING,
          enum: Object.keys(RISK_TAXONOMY),
          description:
            'WEATHER=thời tiết, ACCIDENT=tai nạn/tắc, ROAD_BAD=đường xấu, POLICE=chốt CSGT, HAZARD_OTHER=nguy hiểm khác',
        },
        subtype: {
          type: Type.STRING,
          description:
            'WEATHER: heavy_rain|fog|strong_wind|flooding | ACCIDENT: accident|traffic_jam|breakdown | ROAD_BAD: pothole|slippery|gravel|construction | POLICE: checkpoint|speed_camera|mobile_patrol | HAZARD_OTHER: landslide|fallen_tree|animal|dark_road',
        },
        confidence: {
          type: Type.NUMBER,
          description: 'Độ tự tin 0-1. ≥ 0.8 = auto-save, < 0.8 = preview chờ confirm',
        },
        autoSave: {
          type: Type.BOOLEAN,
          description: 'true nếu confidence cao + câu nói rõ ràng, false nếu mơ hồ cần confirm',
        },
        reason: {
          type: Type.STRING,
          description: 'Giải thích ngắn (max 80 ký tự) tại sao chọn subtype này',
        },
      },
      required: ['category', 'subtype', 'confidence', 'autoSave', 'reason'],
    },
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

interface CommandData {
  action: string;
  params: Record<string, unknown>;
  /** Câu trả lời tự nhiên hiển thị cho user (TTS sẽ đọc câu này). */
  responseText: string;
}

interface RiskData {
  category: string;
  subtype: string;
  vi: string;
  confidence: number;
  autoSaved: boolean;
  reason: string;
  responseText: string;
  id?: string;
  severity?: number;
}

interface VoiceCommandResult {
  type: 'command' | 'risk';
  data: CommandData | RiskData;
  /** Latency Gemini call (ms) — để monitor. */
  latencyMs: number;
}

export const voiceCommand = onCall<
  { text: string; roomId?: string; lat?: number; lng?: number },
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

    // Optional context cho risk reporting (solo hoặc group room)
    const roomId =
      typeof request.data?.roomId === 'string' &&
      /^[A-HJ-NP-Z2-9]{6}$/.test(request.data.roomId)
        ? request.data.roomId
        : null;
    const lat =
      typeof request.data?.lat === 'number' && isFinite(request.data.lat)
        ? request.data.lat
        : null;
    const lng =
      typeof request.data?.lng === 'number' && isFinite(request.data.lng)
        ? request.data.lng
        : null;

    // Rate limit: 30 req/phút (chống burst — nhưng vẫn đủ cho conversation tự nhiên)
    await enforceRateLimit({
      name: 'voice',
      uid: auth.uid,
      maxCount: 30,
      windowSec: 60,
    });

    log.info('voice_received', { text_len: text.length, has_room: roomId !== null });

    const systemPrompt = [
      'Bạn là trợ lý RouteMate cho nhóm phượt xe máy Việt Nam.',
      'Phân tích ý định user → GỌI ĐÚNG MỘT function. Sau khi gọi, viết xác nhận ngắn tiếng Việt (1-2 câu, ≤50 từ).',
      '',
      'Dùng report_risk khi user đề cập sự cố/nguy hiểm trên đường:',
      'WEATHER: mưa to→heavy_rain, sương mù→fog, gió mạnh→strong_wind, ngập→flooding',
      'ACCIDENT: tai nạn→accident, tắc đường→traffic_jam, xe hỏng→breakdown',
      'ROAD_BAD: ổ gà→pothole, trơn→slippery, sỏi đá→gravel, thi công→construction',
      'POLICE: chốt CSGT→checkpoint, camera tốc độ→speed_camera, tuần tra→mobile_patrol',
      'HAZARD_OTHER: sạt lở→landslide, cây đổ→fallen_tree, động vật→animal, đường tối→dark_road',
    ].join('\n');

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
        type: 'command',
        data: {
          action: 'unknown',
          params: { original_text: text },
          responseText: 'Xin lỗi, tôi chưa hiểu ý bạn. Bạn có thể nói lại được không?',
        },
        latencyMs: geminiMs,
      };
    }

    // --- Xử lý riêng report_risk ---
    if (fnCall.name === 'report_risk') {
      const riskArgs = (fnCall.args ?? {}) as {
        category?: string;
        subtype?: string;
        confidence?: number;
        autoSave?: boolean;
        reason?: string;
      };
      const found = findSubtypeConfig(riskArgs.category ?? '', riskArgs.subtype ?? '');

      if (!found) {
        return {
          type: 'command',
          data: {
            action: 'unknown',
            params: {},
            responseText: 'Không xác định được loại sự cố. Vui lòng dùng nút cảnh báo để chọn thủ công.',
          },
          latencyMs: geminiMs,
        };
      }

      const confidence = Math.max(0, Math.min(1, typeof riskArgs.confidence === 'number' ? riskArgs.confidence : 0.5));
      const shouldAutoSave = riskArgs.autoSave === true && confidence >= 0.8;
      const reason = (riskArgs.reason ?? '').slice(0, 100);

      let riskId: string | undefined;
      let severity: number | undefined;
      let autoSaved = false;

      if (shouldAutoSave && roomId !== null && lat !== null && lng !== null) {
        try {
          await assertLeader(auth.uid, roomId, log);
          const saved = await saveRiskLabel({
            category: found.category,
            subtype: found.config.subtype,
            lat,
            lng,
            reportedBy: auth.uid,
            reportedRoomId: roomId,
            source: 'voice',
            voiceRawText: text,
          });
          riskId = saved.id;
          severity = saved.severity;
          autoSaved = true;
        } catch {
          autoSaved = false;
        }
      }

      const riskResponse = autoSaved
        ? `Đã ghi nhận: ${found.config.vi} tại vị trí này.`
        : `Phát hiện: ${found.config.vi}. Chưa lưu — ${confidence < 0.8 ? 'độ tin cậy thấp' : 'thiếu vị trí hoặc quyền leader'}.`;

      log.duration('voice_risk_reported', startMs, {
        category: found.category,
        subtype: found.config.subtype,
        confidence,
        auto_saved: autoSaved,
        gemini_ms: geminiMs,
      });

      return {
        type: 'risk',
        data: {
          category: found.category,
          subtype: found.config.subtype,
          vi: found.config.vi,
          confidence,
          autoSaved,
          reason,
          responseText: riskResponse,
          id: riskId,
          severity,
        },
        latencyMs: geminiMs,
      };
    }

    // --- Xử lý command thông thường ---
    const result: VoiceCommandResult = {
      type: 'command',
      data: {
        action: fnCall.name,
        params: (fnCall.args as Record<string, unknown>) ?? {},
        responseText:
          textPart.trim() ||
          defaultResponseFor(fnCall.name, fnCall.args as Record<string, unknown>),
      },
      latencyMs: geminiMs,
    };

    log.duration('voice_completed', startMs, {
      action: fnCall.name,
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
    case 'report_risk':
      return 'Đã ghi nhận sự cố trên đường.';
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
