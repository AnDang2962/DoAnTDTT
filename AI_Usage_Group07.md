# Nhật ký sử dụng AI & Lịch sử Prompt - Nhóm 07 (RouteMate)

Tài liệu này tổng hợp toàn bộ lịch sử sử dụng Trí tuệ Nhân tạo và các câu lệnh yêu cầu (Prompts) của tất cả 6 thành viên trong nhóm phát triển dự án RouteMate. 

---

## ── THÀNH VIÊN 1: ĐẶNG QUỐC AN – LEADER & ARCHITECT ──

*Vai trò: Quản lý dự án, thiết kế kiến trúc hệ thống, biên soạn báo cáo LaTeX, cấu hình Gradle và môi trường chạy thử emulator.*

### 1.1 Khảo sát ý tưởng & Lộ trình thực hiện (Giai đoạn 1 & 2)
- Đánh giá ý tưởng và định hình kế hoạch thực hiện đồ án RouteMate.
- Phân tích rủi ro phình to phạm vi dự án (Scope Creep) và quyết định loại bỏ tính năng phụ trợ (AI tự động tổng hợp album kỷ niệm từ ảnh/video nhóm phượt).
- Phân chia công việc và thiết lập timeline thực hiện trong vòng 8 tuần cho 6 thành viên.

### 1.2 Phân tích vấn đề & Phân rã theo Tư duy tính toán (Giai đoạn 2)
- Xây dựng Problem Statement dưới góc độ tính toán từ mô tả sản phẩm ban đầu.
- Thiết lập bảng Stakeholder Mapping (phượt thủ, developers, API providers, người thân) cho báo cáo PA2.
- Nghiên cứu tài liệu giảng trình PA1 để nắm vững phương pháp luận phân tích vấn đề khoa học.
- Đề xuất tính năng Cân bằng nhóm (AI Group Balancing) để thay thế tính năng ghép nhóm tự động có độ rủi ro an toàn cao.
- Lựa chọn giải pháp API Gemini Flash để xây dựng tính năng AI Trip Copilot điều khiển bằng giọng nói.
- Xuất bản báo cáo tiến độ PA3 dưới định dạng PDF.

### 1.3 Thiết kế kiến trúc hệ thống C4 Model (Giai đoạn 3)
- Thiết kế sơ đồ Cấp độ 1 (System Context Diagram) bằng Mermaid.js thể hiện mối quan hệ giữa người dùng, hệ thống và các API dịch vụ ngoài.
- Phác thảo sơ đồ Cấp độ 2 (Container Diagram) bằng Mermaid.js chi tiết hóa các container (Flutter App, Firestore, Realtime Database, Cloud Functions).

### 1.4 Thiết lập codebase & Lập trình Module OLS Data Fitting (Giai đoạn 4)
- Định hình kiến trúc thư mục Flutter theo Clean Architecture (`lib/core`, `lib/data`, `lib/features`).
- Lập kế hoạch định hướng các bước triển khai code (implementation guide) chi tiết cho các thành viên đối với từng module.
- Triển khai và viết unit test cho thuật toán OLS Data Fitting, phân tích sai số (Residual Analysis) trực tiếp trên Jupyter Notebook.
- Khắc phục các lỗi NameError trong unit test liên quan đến biến môi trường `__file__`.

### 1.5 Quản lý Git & Tích hợp (Merge) mã nguồn (Giai đoạn 5 & 6)
- Cấu hình Git để đồng bộ hóa mã nguồn từ xa, clone repository công khai và xử lý xung đột ban đầu.
- Thực hiện merge nhánh tích hợp chung `M2+M3+BE` chứa code của module định tuyến, bản đồ nhóm và backend.
- Lập kế hoạch và thiết kế luồng Đăng nhập (Firebase Auth, Guest Mode) và màn hình Hồ sơ cá nhân (avatar, biệt danh, tích lũy quãng đường).

### 1.6 Biên soạn báo cáo LaTeX (Giai đoạn 5 & 6)
- Xây dựng tệp báo cáo `TDTT.tex` hoàn chỉnh, chuẩn hóa văn phong học thuật (loại bỏ in đậm tùy tiện, xóa bỏ các chú thích Anh-Việt dư thừa).
- Tích hợp các sơ đồ Mermaid.js trực quan (sequence diagram thời tiết, UML class model, phân cấp vai trò).
- Định cấu hình đánh số đề mục dạng chữ số La Mã tự động thay vì số thập phân.
- Cấu hình layout trang bìa, bảng phân công công việc căn giữa và xử lý lỗi ngắt trang/tách trang ảnh minh họa.

### 1.7 Cấu hình Backend Emulator & Deploy Production (Giai đoạn 7)
- Cấu hình Firebase Emulator cục bộ phục vụ chạy thử không dây qua IP nội bộ trên Windows.
- Thiết lập shared debug keystore để đồng bộ mã SHA-1 giữa các máy dev của các thành viên.
- Nâng cấp Firebase lên Blaze Plan, cấu hình Secret Manager bảo mật API Key OpenWeatherMap.
- Deploy thành công Cloud Functions lên Production, sửa lỗi giao tiếp `functions internal error` bằng việc cập nhật khóa SHA-1 thiết bị thật lên Firebase Console.

---

## ── THÀNH VIÊN 2: LÊ QUANG MINH (M2) – FRONTEND ROUTING ──

*Vai trò: Phát triển các tính năng định tuyến đa điểm, bản đồ Mapbox, tích hợp API Speech-to-Text để nhận dạng giọng nói, và giải quyết xung đột mã nguồn.*

### 2.1 Cấu hình Hệ thống & Kiến trúc nền tảng (Giai đoạn 1)
- Cấu hình `signingConfigs` sử dụng file `team_debug.jks` trong `build.gradle.kts` nhằm chuẩn hóa chứng chỉ SHA-1, tránh rủi ro bất đồng bộ mã SHA-1 giữa các máy dev của thành viên khi gọi Firebase/Google Maps.
- Tái cấu trúc phương thức khởi tạo thư viện `speech_to_text` trong `voice_service.dart`, chuyển từ object `SpeechListenOptions` sang các tham số trực tiếp (flat parameters) để tương thích phiên bản SDK và tránh xung đột cấu hình.
- Tích hợp Gemini API vào Flutter nhằm xây dựng tính năng "Real-time Incident Analyzer" phục vụ việc phân tích tự động các sự cố giao thông realtime trên lộ trình phượt.

### 2.2 Phát triển & Tối ưu hóa Tính năng cốt lõi (Giai đoạn 2)
- Tái cấu trúc luồng logic gửi tín hiệu khẩn cấp trong `sos_service.dart`: thu thập tọa độ GPS (`Geolocator`) và kiểm tra pin trước tiên, đảm bảo dữ liệu sẵn sàng cho cả hai phương án gọi Firebase Cloud Function (online) hoặc tự động kích hoạt SMS fallback (offline).
- Khắc phục lỗ hổng gửi tọa độ (0,0) trong `GroupRadar`: thêm logic kiểm tra biến vị trí cuối cùng `_myLastPos`, ngăn chặn việc app upload tọa độ rác lên DB khi chưa bắt được sóng GPS.
- Tối ưu hóa trải nghiệm chuyển tab ở màn hình chính `main_shell_screen.dart`: cấu hình lại `MultiProvider` để người dùng chuyển đổi tự do giữa tab Bản đồ và các tab khác (Profile, SOS...) mà không bị ngắt kết nối nền của tính năng Đa tuyến đường và Group Radar.

### 2.3 Quản lý nhánh Git & Giải quyết xung đột mã nguồn (Giai đoạn 3 & 4)
- Giải quyết xung đột (merge conflict) thủ công trong tệp `members_provider.dart` với nhánh `full_feature`, khôi phục biến `_leaderPhoneNumber` phục vụ gửi SMS khẩn cấp mà không phá vỡ mô hình quản lý trạng thái.
- Rà soát và khôi phục logic điều khiển giọng nói trong `voice_service.dart` sau khi pull mã nguồn mới bị ghi đè.
- Xử lý xung đột cấu hình mạng nội bộ trong `main.dart` khi merge code: lưu trữ tạm thời config local và áp dụng lại sau khi merge để kết nối ổn định với Firebase Emulator.
- Sửa lỗi môi trường cục bộ do file `settings.gradle.kts` bị ghi đè bởi path SDK Flutter của máy thành viên khác; cấu hình lại `.gitignore` để bỏ qua các file môi trường cá nhân.
- Khắc phục lỗi build APK thành công nhưng công cụ ADB báo thiết bị offline: chạy chuỗi lệnh reset ADB daemon và cập nhật RSA Key.
- Khôi phục mã nguồn sạch về trạng thái của nhánh `full_feature` bằng các lệnh `git reset --hard` và `git clean` để loại bỏ hoàn toàn các thay đổi rác cục bộ.

### 2.4 Trực quan hóa & Đánh giá chất lượng Code (Giai đoạn 5)
- Thiết kế sơ đồ Class Diagram và State Diagram bằng Mermaid.js thể hiện luồng giao tiếp dữ liệu giữa `MapStateProvider`, `MembersProvider` và Firestore/Firebase Functions.
- Đóng vai trò Code Reviewer để rà soát lỗi Null Safety, các tác vụ bất đồng bộ (`async`/`await`) tại màn hình `room_lobby_screen.dart` và `group_radar_overlay.dart` trước khi đóng gói ứng dụng.

---

## ── THÀNH VIÊN 3: NGUYỄN CÔNG NGUYÊN (M3) – FRONTEND GROUP RADAR ──

*Vai trò: Triển khai module chia sẻ vị trí realtime (Group Radar) qua Firebase Realtime Database, phát triển logic nhóm và phòng phượt.*

### 3.1 Cấu hình Hệ thống & Kiến trúc nền tảng (Giai đoạn 1)
- Xác định phạm vi, trách nhiệm của Module 3 và thiết lập lộ trình phát triển chi tiết qua từng tuần để hoàn thành demo.
- Phân tích cấu trúc cơ sở dữ liệu Firebase Realtime Database cho tính năng Group Radar: lập schema `gps/{roomId}/{memberId}: {lat, lng, updatedAt}`, chứng minh tính hợp lý khi tách vị trí realtime ra khỏi Firestore để giảm tải hệ thống, và cảnh báo rủi ro rò rỉ bộ nhớ (memory leak) khi subscribe dòng dữ liệu GPS.
- Xây dựng tài liệu Master Context từ các tệp mã nguồn để phục vụ quá trình lập trình tự động (vibe coding).
- Đánh giá kiến trúc codebase của Module 3, kiểm thử file Dart chuyển đổi từ Python về tính an toàn kiểu dữ liệu, cơ chế serialize/deserialize Firebase.
- Phân tích tác động lên kiến trúc Module 3 khi nhóm thay đổi tính năng AI (bỏ NLP kết bạn, chuyển sang voice assistant hỗ trợ khẩn cấp, thời tiết, tìm kiếm trạm dừng chân).
- Đánh giá rủi ro và các phương án công nghệ giữa việc sử dụng Flutter/Dart với Python cho đồ án môn học Tư duy tính toán.
- Thiết kế Master Prompt chung cho trợ lý AI giúp tạo code đồng bộ cấu trúc dữ liệu, các package (`Riverpod`, `Provider`) và không sinh thư viện ngoài.

### 3.2 Phát triển & Mô phỏng Logic định vị nhóm (Giai đoạn 2)
- Soạn thảo prompt chuẩn yêu cầu AI lập trình `LocationService` bằng Flutter: sử dụng plugin `geolocator`, thiết lập bộ lọc khoảng cách `distanceFilter: 50m`, và xây dựng cơ chế tự động hủy stream (`dispose`) khi ngừng di chuyển.
- Xây dựng bản mẫu `LocationService` (Dart và Python) phục vụ so sánh hiệu năng, tính chất static typing, và null safety.
- Tái cấu trúc module lõi của ứng dụng (models, room_service, location_service, firebase_client) sang ngôn ngữ Python để phục vụ chương trình mô phỏng (Simulation).
- Thiết lập cơ chế chạy ngầm cho GPS giả lập bằng Python sử dụng kỹ thuật đa luồng (`threading.Thread` và `threading.Event`).
- Xây dựng kịch bản mô phỏng chạy bằng dòng lệnh (Console simulation) cho 2 xe di chuyển: sử dụng công thức toán học Haversine tính khoảng cách và in cảnh báo cự ly (Safe / Warning / Danger) ra màn hình terminal.
- Thiết kế cơ chế quản lý phòng phượt: quy trình tạo phòng, sinh mã phòng 6 ký tự ngẫu nhiên, phân quyền thành viên (Leader / Sweeper / Member) qua `RoomSessionManager`.

### 3.3 Tích hợp hệ thống & Báo cáo (Giai đoạn 3 & 4)
- Rà soát mã nguồn phiên bản Python simulation, tối ưu hóa các module và gộp logic chung tránh xung đột dữ liệu.
- Thiết kế Master Context cho luồng chạy mô phỏng bằng Python và giao diện hiển thị bằng `Streamlit`.
- Xây dựng biểu đồ kiến trúc dạng Class Diagram và State Diagram bằng Mermaid.js mô tả luồng đồng bộ vị trí giữa client và backend.
- Thực hiện Code Review độc lập cho module Group Radar trên Flutter (`room_lobby_screen.dart` và `group_radar_overlay.dart`), chỉ ra các lỗi Null Safety và xử lý bất đồng bộ.
- Thiết lập tệp tổng kết tiến trình dự án cho Module 3 làm báo cáo kỹ thuật.

---

## ── THÀNH VIÊN 4: TRẦN ĐOÀN NGỌC TÚC (M4) – FRONTEND SOS ──

*Vai trò: Thiết kế và phát triển tính năng SOS khẩn cấp (Online/Offline), hoạt ảnh bản đồ và cơ chế gửi SMS khẩn cấp tự động cứu nạn.*

### 4.1 Thiết kế giao diện (UI) & Luồng điều hướng nút SOS (Phiên 1 & 3)
- Xây dựng Widget nút SOS bằng Flutter (`GestureDetector`) hỗ trợ thao tác nhấn giữ trong 3 giây, đi kèm hiệu ứng vòng tròn đếm ngược (countdown animation) và hộp thoại xác nhận.
- Cải tiến nút SOS: chuyển từ hiển thị popup xác nhận sang cơ chế phát tín hiệu lập tức sau 3 giây nhấn giữ để tối ưu tốc độ cứu nạn.
- Tinh chỉnh style thanh điều hướng dưới: phân biệt trực quan màu sắc giữa các tab thông thường và tab đang hoạt động.
- Cải thiện luồng điều hướng: sau khi tạo phòng thành công, tự động chuyển từ tab "Tạo phòng" sang tab "Bản đồ" và ghim thông tin phòng.
- Điều chỉnh hiệu ứng vòng tròn đếm ngược: tạo hoạt ảnh bao quanh chu vi nút SOS và xoay đều trong 3 giây khi nhấn giữ.

### 4.2 Xử lý Logic SOS & Giải pháp ngoại tuyến (SMS Fallback) (Phiên 2, 4 & 6)
- Lập trình hàm kiểm tra trạng thái mạng để định tuyến tín hiệu khẩn cấp: gọi Cloud Function khi online, và tự động gọi ứng dụng SMS hệ thống kèm link tọa độ Google Maps khi offline.
- Đồng bộ hóa các biến thông tin nhóm trong codebase để cung cấp đầy đủ thông tin phòng cho tin nhắn SMS fallback.
- Xây dựng tính năng tự động trích xuất số điện thoại của Leader trong phòng phượt, tự động điền vào tin nhắn SMS khẩn cấp khi gặp sự cố mất mạng.
- Cập nhật logic xử lý nút SOS: hiển thị trạng thái "Đang gửi" và thông báo kết quả ("Thành công" / "Thất bại") rõ ràng cho người dùng.
- Debug và sửa lỗi thiết bị có internet nhưng vẫn bị định tuyến nhầm sang luồng SMS fallback.
- Khắc phục lỗi ứng dụng dừng ở màn hình "Chọn người nhận" (Select recipients) khi kích hoạt SMS fallback bằng cách cấu hình chuẩn tham số truyền vào SMS plugin.

### 4.3 Đồ họa Bản đồ & Khắc phục lỗi Hệ thống (Phiên 3, 5 & 7)
- Tạo hiệu ứng vòng tròn nhấp nháy động tại tọa độ nạn nhân trên bản đồ Mapbox (chu kỳ 1 giây, màu đỏ với độ mờ 50%), tích hợp nút điều hướng deeplink đến Google Maps.
- Lập trình tệp quản lý Marker SOS nhấp nháy màu đỏ trên layer Mapbox.
- Phát triển module lưu trữ và màn hình xem "Lịch sử SOS" nằm bên trong tab SOS.
- Khắc phục lỗi nút SOS nổi không hiển thị trên giao diện sau khi gộp module lịch sử và tạo nhóm.
- Debug lỗi đọc dung lượng pin hiển thị sai định dạng % trong payload gửi lên backend.
- Sửa lỗi hệ thống cảnh báo chưa bật GPS dù dịch vụ định vị của thiết bị đã được kích hoạt.
- Khắc phục lỗi ứng dụng bị treo không phản hồi (ANR - App Not Responding) sau khi render bản đồ trên thiết bị Android vật lý.

---

## ── THÀNH VIÊN 5: HOÀNG KHANG (M5) – BACKEND & CLOUD FUNCTIONS ──

*Vai trò: Thiết lập cơ sở dữ liệu Firebase Firestore và Realtime DB, lập trình các hàm Cloud Functions (Node.js), tích hợp API Gemini AI và OpenWeatherMap.*

### ── WEB CLAUDE.AI ──

*Tháng 4/2026 → Tháng 6/2026 — Giai đoạn phân tích, thiết kế hệ thống và xây dựng backend*

---

### 1. Báo cáo & Tài liệu học thuật

#### 1.1 Báo cáo PA2 — Problem Analysis & Decomposition
- Xây dựng báo cáo PA2 theo framework Tư duy Tính toán: chuyển bài toán từ ill-defined → well-defined; áp dụng Stakeholder Mapping, MoSCoW Requirements, Decomposition theo computational nature (routing / sync / broadcast / voice) — không decompose theo UI.
- Cấu trúc tài liệu: Cover page, Problem Statement, Stakeholder Mapping, Requirements (MoSCoW có cột Lý do ưu tiên + Module phụ trách), Decomposition (4 sub-problems theo format Input/Output/Operators/Evaluation/Constraints), Use Cases, In/Out-of-scope.
- Chuẩn hóa ngôn ngữ: thay tất cả threshold định tính ("nhanh", "an toàn") bằng giá trị định lượng (ms, km, %).
- Output: file `.docx` có header letterhead, table of contents.

#### 1.2 Slide thuyết trình PA2
- Thiết kế slide 5 phút: ít chữ, tập trung điểm sáng tạo so với các nhóm khác (định tuyến, lịch trình, ăn uống, mua sắm).
- Slide hook 30 giây đầu: câu chuyện thực tế phượt thủ bị tách đoàn, nền tối tạo cảm giác trầm tư.
- Slide so sánh dạng 2 cột: "App định tuyến/du lịch hiện tại" vs "RouteMate — điểm khác biệt".
- Slide Group Radar: trình bày định nghĩa Leader/Sweeper, thuật toán Haversine tính khoảng cách, ngưỡng >2km trigger cảnh báo, Distance Filter 50m tối ưu pin.
- Kịch bản thuyết trình kèm theo từng slide.

#### 1.3 Tài liệu điểm khác biệt (1 trang A4)
- Trình bày 6 điểm khác biệt của RouteMate — không nhắc tên nhóm khác, chỉ nêu điểm mới của bản thân.
- 6 điểm: (1) giải bài toán đi nhóm; (2) Group Radar giám sát sức khỏe đội hình realtime; (3) dự báo rủi ro theo ETA — thời tiết của tương lai; (4) SOS SMS fallback khi mất internet; (5) Risk Label cộng đồng 4 tiếng — nhóm đi sau thấy cảnh báo của nhóm đi trước; (6) định vị vấn đề: các nhóm khác = tiện ích du lịch, RouteMate = an toàn tập thể.

---

### 2. Thiết kế Agent Skill

- Thiết kế file `SKILL.md` foundation cho dự án: context chung, stack kỹ thuật, kiến trúc tổng thể — tối ưu token bằng cách không lặp lại context này ở các skill con.
- Phân tích lý do tối ưu token: description dài → AI hiểu đúng scope ngay lần đầu, giảm vòng hỏi-đáp xác nhận; Self-check checklist cuối skill → AI tự kiểm tra trước khi trả lời.
- Tạo 6 role-specific skill, mỗi skill chỉ chứa phần riêng của vai trò đó:

| Skill file | Trigger keywords | Phạm vi |
|---|---|---|
| `routemate-m1-lead` | M1, Lead, Architect, PA1/PA2/PA3 | Architecture, báo cáo |
| `routemate-m2-map` | M2, Map, routing, waypoint, polyline | Map feature |
| `routemate-m3-group` | M3, Group, Radar, GPS sync, Haversine | Group Radar |
| `routemate-m4-sos` | M4, SOS, FCM, SMS fallback | SOS Broadcast |
| `routemate-m5-backend` | M5, Backend, Cloud Functions, Firestore | Backend |
| `routemate-m6-qa` | M6, QA, test, integration | QA + Integration |

- Tạo thư mục `references/`: `code_patterns`, `pa2_guide`, `pa3_guide`, `ct_tables`, `prompt_library`, `tech_constraints` để làm nguồn dẫn chiếu cho các skill.

---

### 3. Backend Development

#### 3.1 Khởi tạo backend từ đầu
- Setup Firebase project `routemate-9e33b`: khởi tạo Cloud Functions (Node.js/TypeScript), cấu hình emulator (auth, functions, Firestore, RTDB), viết skeleton 4 module rỗng có thể chạy.
- Xác nhận Flutter tương thích với Firebase backend qua `cloud_functions` package; cấu hình region `asia-southeast1` cho tất cả Cloud Functions.
- Debug port conflict khi restart emulator; fix lỗi `firebase emulators:start` khi không tìm thấy `firebase.json`.

#### 3.2 Tích hợp Gemini AI
- Verify Gemini API key bằng curl trước khi tích hợp vào Cloud Function: `POST /v1beta/models/gemini-2.5-flash:generateContent`.
- Xử lý lỗi quota: chuyển từ `gemini-2.5-flash` sang `gemini-2.0-flash` (free tier 200 RPD) khi hết token; cân nhắc dùng tài khoản Google khác để tăng quota.
- Debug lỗi `AI service không phản hồi` ở voice command handler: kiểm tra payload gửi lên và timeout setting.

#### 3.3 Tích hợp OpenWeatherMap
- Proxy OpenWeatherMap qua Cloud Function thay vì gọi thẳng từ FE (ẩn API key); format response trả về FE bao gồm condition text (mưa nhẹ/mưa to/nắng) + nhiệt độ + xác suất mưa.
- Debug lỗi "Invalid API key": verify key bằng curl trực tiếp trước khi gắn vào Function.
- Weather label trên map: bỏ phần chữ condition text để giảm kích thước marker, chỉ giữ icon + số liệu.

#### 3.4 API contract và tích hợp FE
- Tạo tài liệu API contract cho các thành viên FE: endpoint, payload schema, response format, error codes của từng Cloud Function.
- Debug lỗi `setRoomRoute error: polyline phải là array` — FE gửi sai kiểu dữ liệu (string thay vì array of coordinates).
- Cung cấp kịch bản thuyết trình PA4: giải thích chức năng từng Cloud Function, luồng lưu trữ Firestore, cách FE và BE kết nối.

#### 3.5 Voice router architecture
- Backend `voiceCommand` nhận raw text → Gemini parse intent → trả về `{type: 'risk' | 'command', action: string, data: {...}}`.
- FE nhận JSON dispatch đúng hàm: `type=risk` → gọi `reportRisk`; `type=command` → gọi handler tương ứng.
- Cả solo và group dùng chung 1 nút mic, phân biệt context bằng tab active.

---

### 4. Thiết kế tính năng (Giai đoạn web)

#### 4.1 Wake Word — đánh giá phương án
- Đánh giá tradeoff giữa Picovoice (chính xác nhưng giới hạn 3 users free tier) và DIY STT continuous (không tốn quota, đủ cho scope đồ án).
- Quyết định: DIY wake word bằng `speech_to_text` continuous mode; patterns: "trợ lý", "routemate", "route mate", "hey routemate".
- Phân tích edge cases: wake patterns ngắn → false positive; race condition partial result; iOS auto-stop STT khi app background → cần recovery mechanism.

#### 4.2 Mode system (TRIP / STOP)
- Thiết kế mode system điều khiển nhiều behavior cùng lúc, không chỉ bật/tắt mic:
  - TRIP: wake word ON, GPS update 3s, auto-load weather/risk, wake lock, foreground notification.
  - STOP: wake word OFF, GPS update 30s, battery save mode.
- Implement theo hướng dễ mở rộng để thêm REST mode (GPS 60s + gợi ý nearby) sau này.

#### 4.3 Solo Room cho single-user
- Thiết kế: user đi 1 mình vẫn được cấp `roomId` (format `SOLO_<sha256(uid).slice(0,6)>`) và tự động là leader — không cần backend tạo phòng.
- FE tự tạo doc Firestore `rooms/SOLO_<hash>` → `assertLeader` pass tự nhiên → risk được lưu cho các nhóm đi sau load.

#### 4.4 Route trimming
- Phân tích: nếu trim polyline theo leader thì member đi sau không có đường dẫn; nếu trim theo từng user thì mỗi người thấy progress riêng.
- Quyết định: mỗi user tự trim polyline từ GPS hiện tại đến đích; leader recompute khi off-route rồi broadcast qua Firestore → members tự update.
- Off-route threshold: 80–150m → banner "Tính lại" (chỉ leader mới trigger recalculate).

#### 4.5 TTS integration points
- Xác định 6 điểm trong app phù hợp để gắn TTS: voice command response, risk alert <500m, off-route warning, destination reached, SOS từ member, member tụt lại >2km.
- Đánh giá turn-by-turn navigation: ước tính 8–15h cho bản cơ bản → không khả thi cho PA4, skip.

---

### 5. Multi-device & Testing

- Setup test 2 thiết bị đồng thời: `flutter run --release --dart-define=MAC_LAN_IP=$(ipconfig getifaddr en0)`.
- Debug kết nối backend khi chạy `--release`: các `dart-define` không được kế thừa từ debug config.
- Viết kịch bản test đầy đủ cho từng voice command: context precondition → input → expected output.
- Test cross-platform: ưu tiên iOS simulator → iOS thật → Android thật; xử lý conflict dependencies giữa `mapbox_maps_flutter` và các plugin khác khi build.
- Merge code giữa các thành viên M2 (map routing) + M3 (group radar): giải quyết xung đột dependency, đảm bảo cả 2 tính năng hoạt động trên cùng 1 app.

---

### ── CLAUDE CODE CLI ──

*Tháng 6/2026 — Giai đoạn hoàn thiện tính năng, fix bug và chuẩn bị demo*

---

### 6. Kiến trúc & Tái cấu trúc

- Phân tích cây thư mục dự án và xác định ranh giới trách nhiệm giữa các layer (`core`, `features`, `data`).
- Kiểm tra các hàm và file có logic trùng nhau giữa `map_routing` và `group_radar`; đánh giá nên gộp vào `core/service` hay giữ riêng ở từng feature.
- Xác định vị trí đúng của `FirebaseFunctionsHelper`: thuộc `core/service` hay nên tách theo feature?
- Refactor hàm `extractWaypointsEvery50Km` thành utility dùng chung; xoá các bản sao trong từng feature.
- Sau mỗi đợt refactor: kiểm tra và xoá toàn bộ dead code, import thừa, field không còn được đọc.

---

### 7. Voice Command

#### 7.1 Đồng bộ UI và luồng giữa 2 nút mic
- Phân tích sự khác biệt về UI và luồng xử lý giữa `VoiceRecordBtn` (solo) và `VoiceFab` (group); đồng nhất: border, label dưới icon, snackbar "Đang nghe...", callback trả kết quả.
- Đưa logic hiển thị partial result lên `VoiceService` để tránh lặp code ở từng widget.
- Điều chỉnh vị trí `VoiceFab` ở group cho nhất quán với solo.

#### 7.2 Implement 7 Voice Action Handlers
- Implement đủ 7 handler: `sendSos`, `checkWeather`, `checkGroupRadar`, `findNearbyPlace`, `reportRisk`, `startNavigation`, `stopNavigation`.
- Tích hợp `parseRiskFromVoice` (logic phân loại risk từ text) vào `reportRisk` handler — không thay thế, giữ nguyên classification logic.
- Thêm context guard: nếu user chưa định tuyến thì khóa lệnh navigation; chưa vào phòng thì khóa lệnh group; trả về thông báo lỗi rõ ràng thay vì silent fail.
- `sendSos`: thêm `_isSending` flag để tránh gửi trùng; lấy danh bạ khẩn cấp từ Firestore thay vì hardcode; dùng `LifecycleObserver` để gọi số sau khi resume từ SOS screen.
- `checkWeather`: TTS chỉ đọc các waypoint có thời tiết xấu theo format "X km nữa tại [địa danh]: mưa to, 28°C" — không đọc toàn bộ danh sách.
- `checkGroupRadar`: gọi Cloud Function `checkGroupRadar` thay vì tính toán lại ở FE; kết quả TTS báo tình trạng đội hình và ETA từng thành viên.
- `findNearbyPlace`: debug lỗi `internal - INTERNAL` từ `geocodePlace` Cloud Function; kiểm tra payload gửi lên và response handling.

#### 7.3 Tái cấu trúc nút mic theo thiết kế mới
- Đưa nút voice command lên center của `BottomAppBar` (dạng FAB notch); xoá nút mic cũ ở từng tab.
- Logic dispatch theo tab active: tab 0 → solo context, tab 1 → group context, tab 2/3 → hiển thị thông báo không khả dụng.
- Đảm bảo nút persist khi chuyển tab, không rebuild lại widget.

#### 7.4 Speech-to-Text
- Xác nhận `speech_to_text ^7.3.0` yêu cầu tất cả config (`localeId`, `listenFor`, `pauseFor`) nằm trong `SpeechListenOptions`; các direct params đã deprecated.
- So sánh với bản code của thành viên trong `/Downloads/tmp/` để quyết định bản nào giữ.

---

### 8. Cảnh báo nguy hiểm (Risk)

#### 8.1 Bug: Risk không hiển thị sau khi gán
- Phân tích tại sao risk được ghi nhận (log confirm) nhưng không render trên map cho đến khi định tuyến lại.
- Root cause: flag `isInitialLoad` được set `true` khi `_knownRiskIds` rỗng + risk đầu tiên vào → toàn bộ map refresh bị skip. Fix: tách điều kiện hiện snackbar (phụ thuộc `isInitialLoad`) khỏi điều kiện trigger map refresh (luôn chạy khi có risk mới).
- Root cause thứ hai (member): code nhận route từ Firestore gán vào biến local `polylineData` thay vì field `_polylineData` → member không có polyline để gọi `getRiskLabelsNearRoute`.

#### 8.2 Cross-group risk detection
- Thiết kế: `listenToRoomWarnings` subscribe Firestore theo `reportedRoomId` (risk của phòng hiện tại); `getRiskLabelsNearRoute` query theo geography (cross-group, bất kỳ nhóm nào báo).
- Timer 5 phút refresh `getRiskLabelsNearRoute` để bắt risk của nhóm đi trước trong lúc đang di chuyển.
- Khi nhận route mới (từ Firestore hoặc recalculate), trigger lại `getRiskLabelsNearRoute` ngay thay vì chờ timer.

#### 8.3 Giới hạn polyline backend
- Cloud Function từ chối payload `> 5000 điểm`: downsample polyline trước khi gửi lên để tính risk proximity; layer render vẫn dùng full resolution.

#### 8.4 Risk report bằng tap trên map
- Thêm `onLongPress`/`onTap` trên `MapboxMap` để mở `RiskReportSheet` với tọa độ đã chọn.
- Dùng chung `soloRoomId` (persistent per user) cho cả solo và group; không sinh ID mới mỗi lần báo.

#### 8.5 Thiết kế lại Risk marker
- Dùng pill nhỏ bo tròn, bỏ đuôi nhọn, `iconAnchor: CENTER` để marker ghim đúng tọa độ khi zoom.
- Giữ emoji + label ngắn để phân biệt loại risk tại mật độ cao.

---

### 9. Định tuyến (Routing)

#### 9.1 Đồng bộ luồng solo và group
- Chuẩn hóa luồng: tìm kiếm điểm đến → hiện preview marker + flyTo → card "Đường đi / Bắt đầu đi" → chọn tuyến → vẽ route + load weather + load risk → bắt đầu navigation.
- Khi chuyển tuyến: invalidate cache weather và risk, load lại theo tuyến mới.
- Khi chuyển tab hoặc leave room: clear route state để tránh route cũ hiển thị ở context khác.

#### 9.2 Cập nhật polyline trong lúc di chuyển
- Đoạn đã đi qua: đổi stroke sang xám nhạt thay vì xoá khỏi layer (giữ nguyên context đường đi cho cả đội).
- Mỗi thành viên tự trim đoạn theo GPS của họ — leader không broadcast cắt đoạn cho member.
- Off-route detection: khi lệch > threshold, hiển thị cảnh báo hoặc trigger recalculate.

#### 9.3 Chọn điểm đến bằng tap map
- Bắt sự kiện tap trên `MapboxMap`, reverse geocode tọa độ, đưa vào luồng định tuyến như tìm kiếm thông thường.

---

### 10. Group Radar

#### 10.1 Member marker
- Lấy `photoURL` từ Firestore profile để render avatar; fallback về initials nếu chưa có ảnh.
- Viền marker màu theo role: xanh dương = leader, xám = member.
- Khi bắt đầu navigation: marker của bản thân chuyển thành mũi tên (bearing theo GPS), ẩn marker avatar của chính mình; marker thành viên khác giữ nguyên.
- Fix: `clearAll()` không được gọi trước khi vẽ arrow marker để tránh xoá marker thành viên.
- Hiển thị emoji rank trên đầu marker để phân biệt danh hiệu (không xung đột với viền role).

#### 10.2 Panel tác vụ nhóm
- Thay thế panel cũ bằng `DraggableScrollableSheet` từ cạnh trái; handle là thanh xám nhỏ, không hiện thanh trắng.
- Nội dung: thông tin phòng, danh sách thành viên với avatar, nút thoát phòng ở dưới cùng.
- Bố cục nút phải: compass → risk FAB → recenter, kích thước đồng nhất, khoảng cách đều nhau.

#### 10.3 Vào phòng bằng QR code
- Generate QR từ mã phòng; deep link `routemate://join?code=XXXX` để mở app và join trực tiếp khi quét bằng camera iOS.

#### 10.4 Đồng bộ tính năng leader / member / solo
- Member được dùng voice command, báo risk, xem weather và risk đầy đủ.
- Route từ leader được sync xuống member qua Firestore; member load risk ngay khi nhận route.
- Navigation info bar (km, ETA) hiển thị cho cả leader và member.

#### 10.5 Persist session sau khi restart app
- Lưu `roomId` vào SharedPreferences; khi app khởi động lại, kiểm tra document còn tồn tại và rejoin nếu user vẫn là thành viên.

---

### 11. SOS

- Luồng "TỚI CỨU NGAY": member → switch tab 0 + set `sosRoutingTarget`; leader → switch tab 1 + set `sosRoutingTarget`.
- Fix black screen: `SOSMapOverlay._handleNavigate` đã pop chính nó; callback `onNavigateToVictim` không được gọi thêm `Navigator.pop()` nữa.
- Callback chain: `GroupRadarOverlay(onSosNavigate)` → `RoomLobbyScreen(onSosNavigate)` → `MainShellScreen._navigateToSosVictim`.
- FCM token: thay fake token bằng `FirebaseMessaging.instance.getToken()` có guard `getAPNSToken()` trên iOS trước khi request.

---

### 12. Bản đồ & Camera

#### 12.1 Recenter và la bàn
- Implement nút recenter: `flyTo` vị trí GPS hiện tại, zoom 15, pitch 45° nếu đang navigate.
- Khi đang navigate: camera follow + bearing theo hướng di chuyển (giống Google Maps navigation mode).
- Fix jank khi xoay màn hình: `_compassSub` trigger `easeTo` trùng với `flyTo` animation → pause sub trước khi flyTo, resume sau 650ms.
- Đồng bộ vị trí và style nút recenter + compass cho cả solo và group.

#### 12.2 Vị trí khởi tạo map
- Map khởi động tại tọa độ cố định (Nha Trang) thay vì GPS thực — fix bằng cách gọi `Geolocator.getCurrentPosition` trước khi khởi tạo `MapboxMap`.

---

### 13. Giao diện

#### 13.1 Tổng thể
- Phân tích điểm yếu UX hiện tại: nền map nhìn xuyên qua tab, chuyển tab không clean, các element chồng lên nhau.
- Áp dụng pattern overlay: tab content có nền đặc (trắng), chỉ tab bản đồ để map hiện phía dưới.

#### 13.2 Implement thiết kế mới từ Stitch
- Implement từng màn hình theo bản mẫu: welcome, login, register, main shell, profile.
- Đối chiếu `ui_ux_evolution_report.md` để cập nhật các điểm còn thiếu.

#### 13.3 Màn hình Welcome & Login
- Welcome: logo đúng kích thước, tagline "Hành trình an toàn hơn khi có RouteMate đồng hành".
- Login: loading indicator hiện tại nút đang xử lý (không hiện ở Google button); dùng icon Google SVG chính thức.
- Logo: tách nền JPEG → PNG trong suốt; áp dụng đúng kích thước theo context (welcome vs login).

#### 13.4 Màn hình vào phòng
- Implement collapse animation: header cam thu nhỏ khi scroll lên, giữ trạng thái sau khi thả.
- Điều chỉnh `maxExtent` riêng cho tab "Làm trưởng nhóm" và "Nhập mã tham gia" để không thừa khoảng trắng.
- Fix text overflow: "Nhập mã tham gia" bị wrap chữ cuối; text "Bắt đầu đi" bị xuống dòng trong card định tuyến.

#### 13.5 Destination marker
- Thay marker text bằng pin bo tròn (style Google Maps); đảm bảo anchor đúng tâm để không lệch khi zoom.

---

### 14. Tab Hồ sơ

- Lịch sử hành trình: lưu khi kết thúc chuyến (solo và group, cả leader lẫn member); hiện ✓ nếu hoàn thành, ✗ nếu huỷ giữa chừng; persist sau đăng xuất.
- Achievement card: cập nhật realtime số chuyến và tổng km sau mỗi chuyến kết thúc.
- Hệ thống rank theo km: xác định ngưỡng từng bậc, đổi màu ring avatar và hiện 👑 theo bậc.
- Hiển thị `nickname` thay vì `displayName` trong phòng nhóm.
- Avatar: cho phép upload ảnh tùy chỉnh cho cả tài khoản Google và email; bỏ badge camera, tap trực tiếp vào avatar để đổi.
- Số điện thoại: thêm trường vào profile, lưu vào Firestore.
- Đổi tên realtime: cập nhật `members` document trong phòng ngay khi user save profile.

---

### 15. Backend & Firebase (giai đoạn CLI)

- Audit toàn bộ Cloud Functions: liệt kê hàm nào đã có client gọi, hàm nào chưa kết nối.
- Kết nối `checkGroupRadar` (FE đang self-calculate, bypass BE), `getRiskTaxonomy`, `geocodePlace`.
- Phân tích sự khác biệt logic giữa FE bypass và BE implementation của `checkGroupRadar`; quyết định dùng bản nào.
- Debug `getWeatherAlongRoute`: response trả về nhưng TTS chỉ nói "đang kiểm tra" — kiểm tra parse logic phía FE.
- Cập nhật Firestore Security Rules để hỗ trợ tính năng lịch sử hành trình; đánh giá impact lên các collection khác.
- Quản lý Gemini API quota: cân nhắc giữa Pay-as-you-go và Prepay trên Google AI Studio; xác nhận key không thay đổi sau khi nâng gói.

---

### 16. Build & Deploy

- Build APK release: `flutter build apk --release --dart-define=...`; cài chồng lên thiết bị (cùng keystore không cần gỡ).
- Fix kết nối backend khi chạy `--release` (các `dart-define` khác với debug mode).
- iOS: provisioning profile từ free Apple ID hết hạn sau 7 ngày — re-sign bằng `flutter run --release`.
- Fix `CocoaPods specs out-of-date`: `pod repo update` trước khi build.
- Kiểm tra `git status` đầy đủ trước mỗi lần push để không bỏ sót file đã sửa.

---

### 17. Tổng hợp lỗi kỹ thuật

| Vấn đề | Root cause | Hướng xử lý |
|--------|-----------|-------------|
| Màn hình đen sau "TỚI CỨU NGAY" | Double `Navigator.pop()` trong callback chain | Xoá pop thừa tại `onNavigateToVictim` |
| Risk không render dù đã gán | `isInitialLoad = true` khi `_knownRiskIds` rỗng → skip map refresh | Tách điều kiện snackbar và map refresh |
| Member không thấy risk sau khi nhận route | Gán vào biến local thay vì `_polylineData` state field | Gán đúng `_polylineData =` |
| Recenter animation khựng khi xoay màn hình | `_compassSub` gọi `easeTo` trong lúc `flyTo` đang chạy | Pause sub trước flyTo, resume sau 650ms |
| `Null check operator` trong RoomLobbyScreen | Widget rebuild sau khi dispose | Thêm `mounted` guard sau các `await` |
| FCM notification không đến | Fake token hardcode thay vì token thật | Dùng `_getFcmToken()` với APNS guard |
| STT không nhận `localeId`/`listenFor` | Dùng deprecated direct params | Chuyển sang `SpeechListenOptions` |
| Risk marker lệch khi zoom | `iconAnchor` mặc định không phải CENTER | Set `iconAnchor: [0.5, 0.5]` |

---

### 18. Quyết định kiến trúc không triển khai

| Tính năng | Lý do không triển khai |
|---|---|
| Picovoice Wake Word | Free tier giới hạn 3 users, yêu cầu đăng ký device |
| Turn-by-turn navigation (TBT) | ~8-15h để làm bản cơ bản — không tương xứng scope PA4 |
| AI Matchmaking (PA2 cũ) | Off-scope cho PA4; focus an toàn thay vì social matching |
| Camera tốc độ (speed camera alert) | Không có data coverage tại Việt Nam |
| Sweeper role riêng biệt | Phức tạp hóa luồng join room; dùng chung member role có flag `isSweeper` |
| REST mode (GPS 60s + gợi ý cafe) | Chưa đủ thời gian; GPS interval đã tối ưu riêng cho TRIP/STOP |

---

## ── THÀNH VIÊN 6: BÙI QUANG TIẾN (M6) – UI/UX & QA TESTING ──

*Vai trò: Thiết kế Wireframe, cấu hình ThemeData đồng bộ, xây dựng bộ 20 Test Cases hệ thống, thiết lập tiêu chí đánh giá và đóng gói APK release.*

### 6.1 Xây dựng Tiêu chí đánh giá hệ thống (Mục 2.3.4)
- Thiết lập bảng tiêu chí đo lường hiệu năng hệ thống RouteMate, định lượng các thông số kỹ thuật (độ trễ SOS, tần suất cập nhật GPS, độ chính xác nhận diện ý định bằng giọng nói của AI, tỷ lệ cảnh báo đứt đoàn sai).
- Xác định ngưỡng đạt (threshold) kỹ thuật và phương án đo đạc thực nghiệm trên thiết bị thật (bắt đầu đo từ thời điểm trigger, sử dụng công cụ giám sát mạng/logs).

### 6.2 Thiết kế và Phát triển Bộ Test Cases Hệ thống (Mục 8.1)
- Xây dựng bộ 20 Test Cases kiểm thử tích hợp (TC-01 đến TC-20) cho các module lõi: Group Radar, GPS Distance Filter, AI Copilot, SOS, Routing Map.
- Bổ sung các ca kiểm thử biên (edge cases) cho tính năng SOS: gửi tín hiệu khẩn cấp liên tục trong thời gian cực ngắn (anti-spam/idempotency), gửi tín hiệu khi thiết bị đột ngột mất mạng, và trường hợp FCM token bị lỗi.
- Thiết kế test case chuyên biệt cho thuật toán Group Radar để xác nhận vai trò Sweeper khi đoàn di chuyển ngược hướng (Bắc-Nam), đảm bảo tính đúng đắn khi tính toán quãng đường tích lũy (`progressKm`) thay vì so sánh tọa độ vĩ độ thuần túy.
- Định dạng và biên soạn bảng Test Cases dưới dạng Markdown, chia làm 2 phần phục vụ chèn vào tài liệu báo cáo chính thức.

### 6.3 Thiết kế Wireframe & Bố cục Giao diện (UI/UX)
- Phác thảo layout khung xương (Wireframe) cho các màn hình ứng dụng: Splash Screen, Đăng nhập, Tạo/Tham gia phòng qua QR, Bản đồ chính, Group Radar, SOS, Hồ sơ cá nhân. Tối ưu hóa kích thước và khoảng cách nút bấm đảm bảo an toàn thao tác khi di chuyển bằng xe máy.
- Bố trí thanh điều hướng dưới (Bottom Navigation) với 4 tab (Bản đồ, Nhóm, SOS, Hồ sơ) và làm nổi bật nút SOS màu đỏ ở giữa.

### 6.4 Xây dựng Theme hệ thống & Đóng gói ứng dụng (Flutter)
- Viết mã nguồn cấu hình `ThemeData` Material 3 cho Flutter: sử dụng màu xanh dương chủ đạo (an toàn, tin cậy) phối hợp màu đỏ khẩn cấp cho nút SOS, định nghĩa màu sắc (`ColorScheme.fromSeed`), kiểu chữ (`textTheme`) và theme cho các nút bấm (`elevatedButtonTheme`).
- Cấu hình file `key.properties`, `build.gradle` và tạo Java Keystore (`.jks`) ký ứng dụng để đóng gói file APK Release trên Windows.
- Sửa lỗi tương thích Gradle build liên quan đến thuộc tính `minSdkVersion` của package quét mã QR `mobile_scanner` trong tệp `android/app/build.gradle`.
