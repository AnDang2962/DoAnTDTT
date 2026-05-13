/**
 * RouteMate Backend - Entry point
 *
 * Tất cả Cloud Functions được export từ file này.
 *
 * Region mặc định: asia-southeast1 (Singapore) - gần Việt Nam nhất, latency thấp.
 */
import { initializeApp } from 'firebase-admin/app';
import { onRequest } from 'firebase-functions/v2/https';

// Khi chạy emulator: chỉ định namespace RTDB rõ ràng để khớp với client.
// Khi production: FIREBASE_CONFIG tự cấu hình → để undefined.
const dbHost = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;

initializeApp({
  databaseURL: dbHost ? `http://${dbHost}?ns=${projectId}` : undefined,
});

// === Module 1: SOS Broadcast ===
export { sendSOS } from './sos';

// === Module 2: Weather Proxy ===
export { getWeatherAlongRoute } from './weather';

// === Module 3: Room/Member Service ===
export { createRoom, joinRoom, leaveRoom, setRoomRoute } from './rooms';

// === Module 4: Group Radar ===
export { computeFatigueScore, checkGroupGap } from './radar';

// === Module 5: AI Trip Copilot (NEW) ===
export { voiceCommand, describeSosLocation } from './ai';

// === Module 6: Risk Labels (Crowdsourced Hazards) ===
export {
  reportRiskLabel,
  parseRiskFromVoice,
  getRiskLabelsNearRoute,
  getRiskTaxonomy,
} from './riskLabels';

// === Health check ===
export const healthCheck = onRequest(
  { region: 'asia-southeast1', cors: true },
  (_req, res) => {
    res.status(200).json({
      status: 'ok',
      service: 'routemate-backend',
      timestamp: new Date().toISOString(),
      modules: ['sos', 'weather', 'rooms', 'radar', 'ai', 'risk'],
      version: '0.5.1-risk-tap',
    });
  }
);
