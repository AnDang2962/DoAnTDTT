# RouteMate Backend (v0.2 — Hardened)

Cloud Functions backend cho dự án **RouteMate** — Tư duy Tính toán, HCMUS.

> **Version 0.2 changelog:** rate limiting, idempotency keys, dead FCM token cleanup, retry với exponential backoff, structured logging, strict validation, expanded smoke test (11 cases) + 18 unit tests.

## Tính năng hardening (v0.2)

| Feature | Module áp dụng | Lợi ích |
|---|---|---|
| **Rate limit** (Firestore-based, sliding window) | SOS (3/phút), Weather (60/phút) | Chống spam/abuse, bảo vệ quota free tier |
| **Idempotency keys** | SOS | Chống double-send khi client retry network |
| **Dead token cleanup** | SOS | Tự xóa FCM token hết hạn — Firestore không phình ra |
| **Retry + exponential backoff** | Weather (sau này: Gemini) | Tăng resilience với network blip |
| **Structured logging** | Tất cả | Filter log theo `event` trong Cloud Logging, dễ alert |
| **Strict input validation** | Tất cả | Reject input xấu trước khi vào business logic |

## Cấu trúc thư mục

```
routemate-backend/
├── functions/
│   ├── src/
│   │   ├── index.ts          # Entry — export tất cả functions
│   │   ├── sos.ts            # Module 1 — SOS (rate limit + idempotency + cleanup)
│   │   ├── weather.ts        # Module 2 — Weather proxy (retry + rate limit)
│   │   ├── rooms.ts          # Module 3 — createRoom/joinRoom/leaveRoom
│   │   ├── radar.ts          # Module 4 — Fatigue Score + Group Gap
│   │   └── lib/
│   │       ├── auth.ts       # Verify Google Sign-In
│   │       ├── haversine.ts  # Công thức khoảng cách
│   │       ├── logger.ts     # Structured logger (NEW)
│   │       ├── rateLimit.ts  # Rate limiter Firestore (NEW)
│   │       ├── retry.ts      # Exponential backoff (NEW)
│   │       └── validate.ts   # Input validators (NEW)
│   ├── package.json
│   └── tsconfig.json
├── test/
│   ├── smoke.js              # End-to-end test (11 cases)
│   ├── unit-validate.js      # Unit test cho validation (18 cases, không cần emulator)
│   └── package.json
├── firestore.rules
├── database.rules.json
├── firebase.json
└── .firebaserc
```

## Migration từ v0.1 (nếu bạn đã chạy v0.1 trước đó)

**KHÔNG có breaking change cho schema chính.** Chỉ thêm 2 collection mới (`rateLimits`, `sosIdempotency`) và 2 field mới trong SOS (`idempotencyKey`, `cleanedTokens`).

Các bước:
1. **Stop emulator cũ** (Ctrl+C ở terminal đang chạy)
2. **Replace tất cả file** từ zip v0.2 (giữ lại `.firebaserc` đã sửa Project ID)
3. **Rebuild**: `cd functions && npm run build && cd ..`
4. **Restart emulator**: `firebase emulators:start`
5. **Run smoke test**: `cd test && npm run smoke`

Smoke test sẽ tự reset `rateLimits` và `sosIdempotency` collections trước mỗi lần chạy.

## Phần A — Setup từ đầu

### A.1. Cài đặt local tools (chỉ làm 1 lần)

Cần Node.js 20 LTS. Trên macOS:

```bash
node --version       # cần >= 20
npm install -g firebase-tools
firebase --version
```

### A.2. Tạo Firebase project (qua Console, free)

1. https://console.firebase.google.com → **Add project** → đặt tên (ví dụ `routemate-dev`).
2. Tắt Google Analytics.
3. **Build → Authentication → Sign-in method** → bật **Google** → Save.
4. **Build → Firestore Database → Create** → region `asia-southeast1` → Production mode.
5. **Build → Realtime Database → Create** → `asia-southeast1` → Locked mode.

### A.3. Cấu hình project

```bash
firebase login
```

Sửa `.firebaserc` — đổi `routemate-dev` thành Project ID thật của bạn.

Sửa `test/smoke.js` — đổi `PROJECT_ID` ở dòng đầu cho khớp.

### A.4. Cài dependencies

```bash
cd functions && npm install && cd ..
cd test && npm install && cd ..
```

## Phần B — Test (KHÔNG cần Blaze plan)

### B.1. Build code

```bash
cd functions && npm run build && cd ..
```

### B.2. Khởi động emulator (Terminal 1)

```bash
lsof -ti:8080,9000,9099,5001,4000,9150 | xargs kill -9 2>/dev/null
sleep 3
firebase emulators:start
```

Đợi đến dòng `All emulators ready!`. Mở http://localhost:4000.

### B.3. Chạy unit tests (Terminal 2)

```bash
cd test
node unit-validate.js
```

Kỳ vọng `=== 18 passed, 0 failed ===`.

### B.4. Chạy smoke test (Terminal 2)

```bash
npm run smoke
```

Kỳ vọng 11/11 ✓:

```
🧪 === RouteMate Backend Smoke Test (Hardened v0.2) ===
1️⃣  Health check ✓
2️⃣  createRoom ✓
3️⃣  Fatigue Score (3 calibration cases) ✓
4️⃣  joinRoom ✓
5️⃣  Ghi GPS ✓
6️⃣  Group Gap Detection ✓
7️⃣  SOS bình thường ✓
8️⃣  SOS idempotency replay → CACHED ✓ (NEW)
9️⃣  SOS rate limit triggered ở lần 4 ✓ (NEW)
🔟  Input validation lat=999 reject ✓ (NEW)
1️⃣1️⃣ Non-member SOS reject ✓ (NEW)
✅ Tất cả tests PASS!
```

## Phần C — Verify trong Emulator UI

Mở http://localhost:4000:

| Tab | Đường dẫn | Phải thấy |
|---|---|---|
| Authentication | — | 3 user (`user-a-uid`, `user-b-uid`, `user-c-uid`) |
| Firestore | `rooms/{roomId}` | members, fcmTokens, memberInfo |
| Firestore | `rooms/{roomId}/sosLogs` | Documents có `idempotencyKey`, `cleanedTokens` |
| Firestore | `rateLimits/sos_user-b-uid` | `{count, windowStart}` |
| Firestore | `sosIdempotency/{uid_key}` | Cached SOS results |
| Database | `roomMembers/{roomId}/{uid}` | true |
| Database | `gps/{roomId}/{uid}` | `{lat, lng, updatedAt}` |
| Logs | filter `event:sos_idempotent_replay` | Lần SOS thứ 2 với cùng key |

## Phần D — Deploy lên production

Chỉ làm khi smoke test pass.

### D.1. Upgrade lên Blaze plan (cần thiết cho Cloud Functions)
Firebase Console → Settings → Usage and billing → Modify plan → Blaze.

### D.2. Cấu hình secrets
```bash
firebase functions:secrets:set OPENWEATHER_API_KEY
# (sau này) firebase functions:secrets:set GEMINI_API_KEY
```

### D.3. (Khuyến nghị) Bật Firestore TTL để auto-cleanup
- Firebase Console → Firestore → TTL → Add policy
- Collection: `rateLimits`, field: `updatedAt`, expires after `1 day`
- Collection: `sosIdempotency`, field: `createdAt`, expires after `7 days`

### D.4. Deploy
```bash
firebase deploy
```

## Phần E — Monitoring (Production-grade, post-deploy)

### E.1. Cloud Logging — Structured log queries

Trong Firebase Console → Functions → Logs, hoặc Google Cloud Console → Logging:

```
# Tất cả lỗi
severity>=ERROR

# SOS rate limited
jsonPayload.event="sos_rate_limit_exceeded"

# Tất cả SOS hoàn tất với latency > 5s
jsonPayload.event="sos_completed" AND jsonPayload.duration_ms>5000

# Tất cả idempotent replay (debug double-send)
jsonPayload.event="sos_idempotent_replay"
```

### E.2. Log-based alerts (free tier có sẵn)

Google Cloud Console → Logging → Logs Explorer → "Create alert":

**Alert 1: SOS thất bại**
- Filter: `jsonPayload.event="sos_fcm_exception"`
- Notification: email tới M5 nếu > 5 lần/10 phút

**Alert 2: Function timeout**
- Filter: `severity=ERROR AND jsonPayload.duration_ms>25000`
- Notification: email

### E.3. Custom metrics

Logs → Logs-based Metrics → Create:
- Name: `sos_delivery_rate`
- Filter: `jsonPayload.event="sos_completed"`
- Field: `jsonPayload.delivered`
- Type: Distribution

Sau đó pin lên Firebase dashboard.

## Module overview

| Module | Function | Algorithm | Status |
|---|---|---|---|
| 1. SOS | `sendSOS` | Algorithm 3 (PA3) | ✅ Hardened: rate limit + idempotency + cleanup |
| 2. Weather | `getWeatherAlongRoute` | — | ✅ Hardened: retry + rate limit. **Cần API key** |
| 3. Rooms | `createRoom`, `joinRoom`, `leaveRoom` | — | ✅ Hardened: validation + logging |
| 4. Radar | `computeFatigueScore`, `checkGroupGap` | Algorithm 2 + 4 (PA3) | ✅ Hardened: validation + logging |
| Misc | `healthCheck` | — | ✅ |

## Còn lại cần hoàn thiện

1. **Sweeper detection** trong `radar.ts`: hiện dùng heuristic vĩ độ thấp nhất (chỉ đúng cho route Bắc→Nam). Production cần distance-along-polyline khi có Module Routing.
2. **Module 2 Weather**: code đã sẵn, cần OpenWeatherMap API key để chạy thật.
3. **Module 5 AI Trip Copilot** (Gemini proxy) — chưa implement.

## Troubleshooting

| Lỗi | Nguyên nhân | Fix |
|---|---|---|
| Smoke test stuck ở rate limit | Firestore còn data từ run trước | Smoke test tự reset; nếu vẫn stuck, manual delete `rateLimits/*` trong Emulator UI |
| SOS trả `CACHED` không mong muốn | Reuse idempotencyKey | Sinh UUID mới mỗi lần `sendSOS` (smoke test đã làm đúng) |
| `permission-denied` ở smoke test | Project ID mismatch | Check `.firebaserc` và `test/smoke.js` PROJECT_ID khớp nhau |
