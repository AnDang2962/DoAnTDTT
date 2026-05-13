/**
 * RouteMate Backend - Smoke Test (v0.5.1 — Risk Labels tap UX)
 * ==========================================================
 * Test cases (25 total):
 *   1-11: Auth, rooms, fatigue, SOS, validation
 *  12-15: AI voice command + SOS description (auto-skip nếu thiếu Gemini key)
 *  16-17: Polyline-based Group Gap + Off-route detection
 *  18-21: Risk Labels via TAP UI (leader-only, taxonomy validation)
 *  22-23: Risk Labels via VOICE (auto-skip nếu thiếu Gemini key)
 *  24-25: Query risks dọc route + getRiskTaxonomy
 * ==========================================================
 */

const admin = require('firebase-admin');
const { initializeApp } = require('firebase/app');
const {
  getAuth,
  signInWithCustomToken,
  connectAuthEmulator,
} = require('firebase/auth');
const {
  getFunctions,
  httpsCallable,
  connectFunctionsEmulator,
} = require('firebase/functions');
const { getDatabase, ref, set, connectDatabaseEmulator } = require('firebase/database');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// ⚠ Đổi PROJECT_ID này khớp với .firebaserc
const PROJECT_ID = 'routemate-9e33b';
const REGION = 'asia-southeast1';

// 127.0.0.1 thay vì localhost (tránh lỗi IPv6 trên macOS mới)
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.FIREBASE_DATABASE_EMULATOR_HOST = '127.0.0.1:9000';

admin.initializeApp({
  projectId: PROJECT_ID,
  databaseURL: `http://127.0.0.1:9000?ns=${PROJECT_ID}`,
});

const app = initializeApp({
  apiKey: 'fake-api-key',
  projectId: PROJECT_ID,
  databaseURL: `http://127.0.0.1:9000?ns=${PROJECT_ID}`,
});
const auth = getAuth(app);
const functions = getFunctions(app, REGION);
const rtdb = getDatabase(app);

connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
connectFunctionsEmulator(functions, '127.0.0.1', 5001);
connectDatabaseEmulator(rtdb, '127.0.0.1', 9000);

const log = (msg) => console.log(`\n${msg}`);
const ok = (msg) => console.log(`   \x1b[32m✓\x1b[0m ${msg}`);
const skip = (msg) => console.log(`   \x1b[33m○\x1b[0m ${msg}`);
const fail = (msg) => {
  console.log(`   \x1b[31m✗\x1b[0m ${msg}`);
  failures++;
};
let failures = 0;

function hasGeminiKey() {
  const secretFile = path.join(__dirname, '..', 'functions', '.secret.local');
  if (!fs.existsSync(secretFile)) return false;
  const content = fs.readFileSync(secretFile, 'utf8');
  return /GEMINI_API_KEY=\S+/.test(content);
}

function hasOpenWeatherKey() {
  const secretFile = path.join(__dirname, '..', 'functions', '.secret.local');
  if (!fs.existsSync(secretFile)) return false;
  const content = fs.readFileSync(secretFile, 'utf8');
  return /OPENWEATHER_API_KEY=\S+/.test(content);
}

async function loginAs(uid, email, name) {
  const token = await admin.auth().createCustomToken(uid, { email, name });
  await signInWithCustomToken(auth, token);
}

const uuid = () => crypto.randomBytes(16).toString('hex');

async function resetState() {
  const db = admin.firestore();
  for (const col of ['rateLimits', 'sosIdempotency', 'riskLabels']) {
    const snap = await db.collection(col).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

// Polyline test data: SG → Phan Thiết, 4 waypoints
const SG_PHANTHIET_ROUTE = [
  { lat: 10.7769, lng: 106.7009 }, // SG
  { lat: 10.85, lng: 106.85 },
  { lat: 10.9, lng: 107.5 },
  { lat: 10.9333, lng: 108.1 }, // Phan Thiết
];

async function main() {
  console.log('\n🧪 === RouteMate Backend Smoke Test (v0.5.1 — Risk Tap+Voice) ===');

  await resetState();
  const geminiAvailable = hasGeminiKey();
  const openWeatherAvailable = hasOpenWeatherKey();

  // === 1. Health check ===
  log('1️⃣  Health check');
  try {
    const url = `http://127.0.0.1:5001/${PROJECT_ID}/${REGION}/healthCheck`;
    const res = await fetch(url);
    const body = await res.json();
    if (res.status !== 200 || body.status !== 'ok') {
      throw new Error(`Unexpected: ${res.status}`);
    }
    ok(`Status 200, version=${body.version}`);
  } catch (e) {
    fail(`Health check thất bại: ${e.message}`);
    process.exit(1);
  }

  // === 2. createRoom (NO route) ===
  log('2️⃣  User A tạo room (không có route)');
  await loginAs('user-a-uid', 'a@test.com', 'Alice');
  const createRoom = httpsCallable(functions, 'createRoom');
  const createRes = await createRoom({
    displayName: 'Alice',
    fcmToken: 'fake-fcm-token-a-1234567890',
  });
  const roomId = createRes.data.roomId;
  ok(`Room created: ${roomId}`);

  // === 3. Fatigue Score ===
  log('3️⃣  Fatigue Score - calibration values từ PA3');
  const computeFatigue = httpsCallable(functions, 'computeFatigueScore');
  const cases = [
    { driveTimeMin: 120, temperatureC: 28, expectedScore: 72, expectedRest: true },
    { driveTimeMin: 90, temperatureC: 35, expectedScore: 56.8, expectedRest: false },
    { driveTimeMin: 90, temperatureC: 40, expectedScore: 58.8, expectedRest: false },
  ];
  for (const tc of cases) {
    const r = await computeFatigue({ driveTimeMin: tc.driveTimeMin, temperatureC: tc.temperatureC });
    const passed = Math.abs(r.data.score - tc.expectedScore) < 0.1 && r.data.shouldRecommendRest === tc.expectedRest;
    if (passed) ok(`drive=${tc.driveTimeMin}min temp=${tc.temperatureC}°C → score=${r.data.score}`);
    else fail(`got ${r.data.score}/${r.data.shouldRecommendRest}`);
  }

  // === 4. joinRoom ===
  log('4️⃣  User B join room');
  await loginAs('user-b-uid', 'b@test.com', 'Bob');
  const joinRoom = httpsCallable(functions, 'joinRoom');
  await joinRoom({ roomId, displayName: 'Bob', fcmToken: 'fake-fcm-token-b-1234567890' });
  ok(`User B joined ${roomId}`);

  // === 5. Ghi GPS giả ===
  log('5️⃣  Ghi GPS giả (Alice ở Bắc, Bob ở Nam — route SG-PT)');
  await loginAs('user-a-uid', 'a@test.com', 'Alice');
  // Alice gần Phan Thiết (đi xa hơn, vĩ độ CAO hơn)
  await set(ref(rtdb, `gps/${roomId}/user-a-uid`), { lat: 10.92, lng: 107.8, updatedAt: Date.now() });
  await loginAs('user-b-uid', 'b@test.com', 'Bob');
  // Bob gần SG (Sweeper, vĩ độ THẤP hơn)
  await set(ref(rtdb, `gps/${roomId}/user-b-uid`), { lat: 10.78, lng: 106.71, updatedAt: Date.now() });
  ok('GPS đã ghi');

  // === 6. Group Gap Detection (FALLBACK heuristic — chưa có route) ===
  log('6️⃣  Group Gap (chưa có route → fallback latitude heuristic)');
  const checkGap = httpsCallable(functions, 'checkGroupGap');
  const gapRes = await checkGap({ roomId });
  if (gapRes.data.method === 'latitude' && gapRes.data.sweeper?.id === 'user-b-uid') {
    ok(`method=${gapRes.data.method}, Sweeper=${gapRes.data.sweeper.id}, gaps=${gapRes.data.gaps.length}`);
  } else {
    fail(`Unexpected: ${JSON.stringify(gapRes.data)}`);
  }

  // === 7. SOS bình thường ===
  log('7️⃣  User B gửi SOS');
  const sendSOS = httpsCallable(functions, 'sendSOS');
  const idem1 = uuid();
  const sosRes = await sendSOS({ roomId, lat: 10.78, lng: 106.71, idempotencyKey: idem1 });
  ok(`Status=${sosRes.data.status}, delivered=${sosRes.data.deliveredCount}`);

  // === 8. SOS idempotency ===
  log('8️⃣  SOS idempotency replay');
  const sosRes2 = await sendSOS({ roomId, lat: 10.78, lng: 106.71, idempotencyKey: idem1 });
  if (sosRes2.data.status === 'CACHED') ok('CACHED');
  else fail(`Expected CACHED, got ${sosRes2.data.status}`);

  // === 9. SOS rate limit ===
  log('9️⃣  SOS rate limit (4 SOS liên tiếp)');
  await admin.firestore().doc('rateLimits/sos_user-b-uid').delete();
  let rateLimited = false;
  for (let i = 1; i <= 4; i++) {
    try {
      await sendSOS({ roomId, lat: 10.78, lng: 106.71, idempotencyKey: uuid() });
    } catch (e) {
      if (e.code === 'functions/resource-exhausted' && i === 4) rateLimited = true;
    }
  }
  if (rateLimited) ok('Rate limit triggered ở lần 4');
  else fail('Rate limit không kích hoạt');

  // === 10. Input validation ===
  log('🔟  Input validation');
  try {
    await sendSOS({ roomId, lat: 999, lng: 106, idempotencyKey: uuid() });
    fail('Should reject lat=999');
  } catch (e) {
    if (e.code === 'functions/invalid-argument') ok(`Reject: ${e.message}`);
    else fail(`Wrong code: ${e.code}`);
  }

  // === 11. Permission ===
  log('1️⃣1️⃣ Non-member SOS');
  await loginAs('user-c-uid', 'c@test.com', 'Charlie');
  try {
    await sendSOS({ roomId, lat: 10.8, lng: 106.6, idempotencyKey: uuid() });
    fail('Should reject');
  } catch (e) {
    if (e.code === 'functions/permission-denied') ok('Reject permission-denied');
    else fail(`Wrong code: ${e.code}`);
  }

  // === 12-15: Module 5 AI ===
  if (geminiAvailable) {
    await loginAs('user-a-uid', 'a@test.com', 'Alice');
    const voiceCommand = httpsCallable(functions, 'voiceCommand');
    const describeSos = httpsCallable(functions, 'describeSosLocation');

    log('1️⃣2️⃣ Voice: "tìm trạm xăng gần đây"');
    try {
      const r = await voiceCommand({ text: 'tìm trạm xăng gần đây' });
      ok(`action=${r.data.action} | "${r.data.responseText}" (${r.data.latencyMs}ms)`);
    } catch (e) { fail(`${e.message}`); }

    log('1️⃣3️⃣ Voice: "cứu! tai nạn rồi"');
    try {
      const r = await voiceCommand({ text: 'cứu! tai nạn rồi' });
      ok(`action=${r.data.action} | "${r.data.responseText}"`);
    } catch (e) { fail(`${e.message}`); }

    log('1️⃣4️⃣ Voice: lạc đề');
    try {
      const r = await voiceCommand({ text: 'asdfgh xyz qwerty' });
      ok(`action=${r.data.action} | "${r.data.responseText}"`);
    } catch (e) { fail(`${e.message}`); }

    log('1️⃣5️⃣ describeSosLocation: GPS Phan Thiết');
    try {
      const r = await describeSos({ lat: 10.9333, lng: 108.1 });
      ok(`"${r.data.description}" (${r.data.latencyMs}ms)`);
    } catch (e) { fail(`${e.message}`); }
  } else {
    log('1️⃣2️⃣-1️⃣5️⃣ Module 5 AI');
    skip('Skip vì chưa có GEMINI_API_KEY');
  }

  // === 16. NEW: setRoomRoute + checkGroupGap với polyline ===
  log('1️⃣6️⃣ setRoomRoute + checkGroupGap polyline-based');
  await loginAs('user-a-uid', 'a@test.com', 'Alice'); // leader
  const setRoomRoute = httpsCallable(functions, 'setRoomRoute');
  try {
    const setRes = await setRoomRoute({
      roomId,
      route: {
        polyline: SG_PHANTHIET_ROUTE,
        startName: 'Sài Gòn',
        endName: 'Phan Thiết',
      },
    });
    if (setRes.data.totalDistanceKm > 100 && setRes.data.totalDistanceKm < 200) {
      ok(`Route set: SG→PT ${setRes.data.totalDistanceKm}km`);
    } else {
      fail(`Bất thường: ${setRes.data.totalDistanceKm}km`);
    }

    // Reset rate limit cho user-b để check gap
    await admin.firestore().doc('rateLimits/sos_user-b-uid').delete();

    // Reset GPS — Alice gần Phan Thiết (đi xa), Bob gần SG (Sweeper)
    await set(ref(rtdb, `gps/${roomId}/user-a-uid`), { lat: 10.92, lng: 107.8, updatedAt: Date.now() });
    await set(ref(rtdb, `gps/${roomId}/user-b-uid`), { lat: 10.78, lng: 106.71, updatedAt: Date.now() });

    const r = await checkGap({ roomId });
    if (r.data.method === 'polyline' && r.data.sweeper?.id === 'user-b-uid' && r.data.sweeper.progressKm < 5) {
      ok(`method=polyline, Sweeper=${r.data.sweeper.id}, progress=${r.data.sweeper.progressKm}km, gaps=${r.data.gaps.length}`);
    } else {
      fail(`Unexpected: ${JSON.stringify(r.data)}`);
    }
  } catch (e) { fail(`${e.message}`); }

  // === 17. NEW: Off-route detection ===
  log('1️⃣7️⃣ Off-route detection (member ở Nha Trang, lệch route SG-PT)');
  try {
    // Alice gần Phan Thiết, Bob ở Nha Trang (xa polyline > 100km)
    await set(ref(rtdb, `gps/${roomId}/user-a-uid`), { lat: 10.92, lng: 107.8, updatedAt: Date.now() });
    await set(ref(rtdb, `gps/${roomId}/user-b-uid`), { lat: 12.24, lng: 109.19, updatedAt: Date.now() }); // Nha Trang

    const r = await checkGap({ roomId });
    if (r.data.offRouteWarnings && r.data.offRouteWarnings.length > 0) {
      const w = r.data.offRouteWarnings[0];
      ok(`Off-route detected: ${w.memberId} cách polyline ${w.offRouteKm}km`);
    } else {
      fail(`Expected off-route warning: ${JSON.stringify(r.data)}`);
    }
  } catch (e) { fail(`${e.message}`); }

  // === 18-21: Module 6 v0.5.1 - Risk Labels (tap UX + voice fallback) ===
  await loginAs('user-a-uid', 'a@test.com', 'Alice'); // leader

  log('1️⃣8️⃣ Leader chạm UI report risk: Đường xấu → Ổ gà');
  const reportRiskLabel = httpsCallable(functions, 'reportRiskLabel');
  try {
    const r = await reportRiskLabel({
      roomId,
      category: 'ROAD_BAD',
      subtype: 'pothole',
      lat: 10.85,
      lng: 106.85,
    });
    if (r.data.category === 'ROAD_BAD' && r.data.subtype === 'pothole' && r.data.severity > 0) {
      ok(`Saved ${r.data.id} | ${r.data.category}/${r.data.subtype} severity=${r.data.severity}`);
    } else {
      fail(`Unexpected: ${JSON.stringify(r.data)}`);
    }
  } catch (e) { fail(`${e.message}`); }

  log('1️⃣9️⃣ Leader chạm UI report risk: CSGT → Chốt');
  try {
    const r = await reportRiskLabel({
      roomId,
      category: 'POLICE',
      subtype: 'checkpoint',
      lat: 10.9,
      lng: 107.5,
    });
    if (r.data.subtype === 'checkpoint') {
      ok(`Saved chốt CSGT severity=${r.data.severity} (decay 6h)`);
    } else fail(`Unexpected: ${JSON.stringify(r.data)}`);
  } catch (e) { fail(`${e.message}`); }

  log('2️⃣0️⃣ Reject taxonomy không hợp lệ');
  try {
    await reportRiskLabel({
      roomId,
      category: 'FAKE_CATEGORY',
      subtype: 'pothole',
      lat: 10.85,
      lng: 106.85,
    });
    fail('Should reject invalid category');
  } catch (e) {
    if (e.code === 'functions/invalid-argument') ok(`Reject: ${e.message}`);
    else fail(`Wrong code: ${e.code}`);
  }

  log('2️⃣1️⃣ Member (non-leader) thử report → reject');
  await loginAs('user-b-uid', 'b@test.com', 'Bob');
  try {
    await reportRiskLabel({
      roomId,
      category: 'ROAD_BAD',
      subtype: 'slippery',
      lat: 10.85,
      lng: 106.85,
    });
    fail('Non-leader nên bị reject');
  } catch (e) {
    if (e.code === 'functions/permission-denied') ok('Reject permission-denied');
    else fail(`Wrong code: ${e.code}`);
  }

  // === 22-24: Voice path + query nearby ===
  if (geminiAvailable) {
    await loginAs('user-a-uid', 'a@test.com', 'Alice');

    log('2️⃣2️⃣ Voice "ổ gà to lắm" → AI classify thành ROAD_BAD/pothole');
    const parseRiskFromVoice = httpsCallable(functions, 'parseRiskFromVoice');
    try {
      const r = await parseRiskFromVoice({
        roomId,
        voiceText: 'ổ gà to lắm',
        lat: 10.86,
        lng: 106.9,
      });
      if (r.data.category === 'ROAD_BAD' && r.data.subtype === 'pothole') {
        ok(`AI → ${r.data.category}/${r.data.subtype} conf=${r.data.confidence} autoSaved=${r.data.autoSaved} | "${r.data.reason}"`);
      } else {
        fail(`Expected ROAD_BAD/pothole, got ${r.data.category}/${r.data.subtype}`);
      }
    } catch (e) { fail(`${e.message}`); }

    log('2️⃣3️⃣ Voice "có chốt phía trước" → AI classify thành POLICE/checkpoint');
    try {
      const r = await parseRiskFromVoice({
        roomId,
        voiceText: 'có chốt phía trước',
        lat: 10.91,
        lng: 107.6,
      });
      if (r.data.category === 'POLICE') {
        ok(`AI → ${r.data.category}/${r.data.subtype} conf=${r.data.confidence}`);
      } else {
        fail(`Expected POLICE, got ${r.data.category}`);
      }
    } catch (e) { fail(`${e.message}`); }
  } else {
    log('2️⃣2️⃣-2️⃣3️⃣ Voice classifier');
    skip('Skip vì cần Gemini key');
  }

  log('2️⃣4️⃣ Query risks dọc route SG → Phan Thiết');
  await loginAs('user-a-uid', 'a@test.com', 'Alice');
  const getRisks = httpsCallable(functions, 'getRiskLabelsNearRoute');
  try {
    const r = await getRisks({ roomId, bufferKm: 5 });
    if (r.data.count >= 2) {
      ok(`Tìm thấy ${r.data.count} risk(s) dọc route, sorted theo progressKm:`);
      for (const risk of r.data.risks.slice(0, 5)) {
        console.log(
          `      - ${risk.category}/${risk.subtype} (${risk.vi}) at progress=${risk.progressKm}km, severity=${risk.severity}`
        );
      }
    } else {
      fail(`Expected ≥2 risks, got ${r.data.count}`);
    }
  } catch (e) { fail(`${e.message}`); }

  log('2️⃣5️⃣ getRiskTaxonomy — FE pull constants');
  const getTax = httpsCallable(functions, 'getRiskTaxonomy');
  try {
    const r = await getTax({});
    const data = r.data;
    if (data.WEATHER && data.ACCIDENT && data.ROAD_BAD && data.POLICE && data.HAZARD_OTHER && data.allSubtypes?.length > 0) {
      ok(`Taxonomy có 5 category, ${data.allSubtypes.length} subtypes`);
    } else {
      fail(`Taxonomy thiếu category hoặc subtypes`);
    }
  } catch (e) { fail(`${e.message}`); }

  // === 26-27: Module 2 - Weather Proxy (auto-skip nếu thiếu OpenWeather key) ===
  if (openWeatherAvailable) {
    log('2️⃣6️⃣ Weather Sài Gòn (Module 2 thật từ OpenWeatherMap)');
    const getWeather = httpsCallable(functions, 'getWeatherAlongRoute');
    try {
      const r = await getWeather({ lat: 10.7769, lng: 106.7009 });
      if (typeof r.data.tempC === 'number' && r.data.weatherMain) {
        ok(`tempC=${r.data.tempC}°C | ${r.data.weatherMain} | "${r.data.description}" | dangerous=${r.data.isDangerous}`);
      } else {
        fail(`Response bất thường: ${JSON.stringify(r.data)}`);
      }
    } catch (e) { fail(`${e.message}`); }

    log('2️⃣7️⃣ Weather Phan Thiết (đầu kia route)');
    try {
      const r = await getWeather({ lat: 10.9333, lng: 108.1 });
      if (typeof r.data.tempC === 'number') {
        ok(`tempC=${r.data.tempC}°C | ${r.data.description}`);
      } else {
        fail(`Response bất thường: ${JSON.stringify(r.data)}`);
      }
    } catch (e) { fail(`${e.message}`); }
  } else {
    log('2️⃣6️⃣-2️⃣7️⃣ Module 2 Weather Proxy');
    skip('Skip vì chưa có OPENWEATHER_API_KEY');
  }

  // === Summary ===
  console.log('\n' + '='.repeat(60));
  if (failures === 0) {
    console.log('\x1b[32m✅ Tất cả tests PASS!\x1b[0m');
    if (!geminiAvailable) {
      console.log('\x1b[33m⚠ Module 5 chưa được test (thiếu GEMINI_API_KEY)\x1b[0m');
    }
    console.log('\n👉 Mở Emulator UI: http://127.0.0.1:4000\n');
    process.exit(0);
  } else {
    console.log(`\x1b[31m❌ ${failures} test(s) FAILED\x1b[0m\n`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('\n\x1b[31m❌ Test crashed:\x1b[0m', err);
  process.exit(1);
});
