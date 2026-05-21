# 🚀 Hướng Dẫn Setup & Chạy Frontend Kết Nối Local Backend

> **Mục đích:** Hướng dẫn các thành viên nhóm Frontend cách chạy ứng dụng kết nối với Firebase Emulator cục bộ để test các tính năng (như Tạo phòng, Lộ trình, Radar...) mà không dính lỗi kết nối.
> **Dự án:** RouteMate
> **Lưu ý:** Vui lòng đọc kỹ từng bước, đặc biệt là phần cấu hình IP và cấp quyền Android.

---

## Bước 1: Khởi động Backend (Điều kiện tiên quyết)
Để app có thể gọi API, bạn **bắt buộc** phải bật máy chủ ảo của nhóm trước.
1. Mở Terminal, trỏ vào thư mục `backend`.
2. Chạy lệnh:
   ```bash
   firebase emulators:start
   ```
3. Chờ đến khi Terminal hiện chữ `✔ All emulators ready!` và giữ nguyên Terminal này chạy ngầm. (Xem thêm chi tiết tại file BACKEND_API.md của Khang).

---

## Bước 2: Cấu hình IP cục bộ trong main.dart
Vì chúng ta đang chạy server ở môi trường Local, mỗi máy tính sẽ có một dải mạng khác nhau. Bạn phải sửa IP trong file `main.dart` cho khớp với thiết bị bạn dùng để test.

Mở `lib/main.dart`, tìm đến đoạn cấu hình Emulator và sửa lại biến `emulatorIp`:

```dart
  if (kDebugMode) {
    // ⚠️ QUAN TRỌNG: Sửa IP dưới đây cho phù hợp với máy của bạn:
    // 1. Dùng Máy ảo Android (Android Emulator trên máy tính): '10.0.2.2'
    // 2. Dùng Web/iOS Simulator: '127.0.0.1' hoặc 'localhost'
    // 3. Điện thoại thật cắm cáp (đã chạy lệnh adb reverse): '127.0.0.1'
    // 4. Điện thoại thật bắt Wi-Fi Hotspot từ máy tính: Mở Terminal gõ 'ipconfig' (Windows) lấy IPv4 của Hotspot (VD: '192.168.137.1')
    
    String emulatorIp = '192.168.137.1'; // <-- ĐỔI Ở ĐÂY

    FirebaseAuth.instance.useAuthEmulator(emulatorIp, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorIp, 8080);
    FirebaseDatabase.instance.useDatabaseEmulator(emulatorIp, 9000);

    // Bắt buộc dùng region asia-southeast1 theo chuẩn Backend
    FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .useFunctionsEmulator(emulatorIp, 5001);
  }
```

---

## Bước 3: Cấp quyền HTTP cho Android (Bắt buộc cho Local)
Để Android không tự động chặn kết nối đến máy chủ ảo (do thiếu HTTPS), chúng ta cần cấp quyền `usesCleartextTraffic`.

Mở file: `android/app/src/main/AndroidManifest.xml`

Kiểm tra xem trong thẻ `<application>` đã có dòng này chưa. Nếu chưa thì thêm vào:

```xml
    <application
        android:label="route_mate_app"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">
```

---

## Bước 4: Xóa App cũ và Khởi chạy lại
> ⚠️ **HÀNH ĐỘNG BẮT BUỘC:** Vì file `AndroidManifest.xml` đã thay đổi, hệ điều hành sẽ không nhận diện nếu bạn chỉ chạy đè lên. 
> Bạn **phải gỡ cài đặt (Uninstall) ứng dụng cũ** trên điện thoại/máy ảo trước khi chạy lệnh mới.

Mở Terminal của Frontend và chạy chuỗi lệnh sau để dọn dẹp và khởi chạy:

```bash
# 1. Dọn dẹp cache cũ
flutter clean

# 2. Cài đặt lại thư viện
flutter pub get

# 3. Chạy ứng dụng
flutter run
```

---

## 🛑 Các Lỗi Thường Gặp (Troubleshooting)

### 1. Lỗi NOT_FOUND khi gọi hàm
**Nguyên nhân:** App đang cố gọi hàm ở máy chủ Mỹ (`us-central1`) thay vì Singapore (`asia-southeast1`) của nhóm.

**Cách sửa:** Chắc chắn bạn đang gọi hàm thông qua helper `backendFunctions` được định nghĩa trong `lib/services/firebase_functions_helper.dart`. (Tuyệt đối không dùng `FirebaseFunctions.instance.httpsCallable()`).

---

### 2. Lỗi UNAVAILABLE hoặc DEADLINE_EXCEEDED
**Nguyên nhân:** Điện thoại bị mất kết nối với máy tính.

**Cách sửa:** 
- Nếu dùng điện thoại thật bắt Hotspot của máy tính: Tắt ngay dữ liệu di động (4G/5G) trên điện thoại.
- Kiểm tra xem Tường lửa Windows (Windows Defender Firewall) đã được tắt chưa.
- Kiểm tra lại IP ở Bước 2 xem có bị sai không.

---

### 3. Màn hình đen khi mới mở App
**Nguyên nhân:** App bị treo do hàm `signInAnonymously()` không tìm thấy máy chủ xác thực (Auth Emulator).

**Cách sửa:** Áp dụng timeout để tránh treo app. Code `main.dart` chuẩn:

```dart
if (FirebaseAuth.instance.currentUser == null) {
    try {
      await FirebaseAuth.instance.signInAnonymously().timeout(const Duration(seconds: 5));
    } catch (e) {
      print("Đăng nhập ẩn danh thất bại/Timeout: $e");
    }
}
```

(Đồng thời kiểm tra lại mạng kết nối giữa điện thoại và máy tính).
