import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

/// Tiện ích điều chỉnh vị trí các điểm đánh dấu (Marker) trên bản đồ.
/// Vấn đề: Khi nhiều rủi ro (ổ gà, mưa, tai nạn) được báo cáo ở cùng 1 vị trí, 
/// các bong bóng cảnh báo sẽ đè lên nhau khiến người dùng không đọc được.
/// Giải pháp: Dời vị trí của marker mới lên trên một chút (offset) nếu nó quá gần marker cũ.
class MarkerOffsetHelper {
  /// Khoảng cách dời lên trên cho mỗi cấp độ (tính theo độ vĩ tuyến).
  /// Khoảng 0.00045 độ tương đương với việc dịch chuyển lên trên tầm 50 mét trên thực tế, 
  /// đủ để 2 bong bóng không đè nhau.
  static const double offsetStep = 0.00045;

  /// Khoảng cách tối thiểu giữa 2 điểm để coi là "Bị chồng lên nhau" (đơn vị: Mét).
  /// Nếu marker mới cách marker cũ dưới 60 mét, nó sẽ bị coi là chồng và phải dời đi.
  static const double overlapThreshold = 60.0;

  /// Số lần tối đa có thể dời lên trên.
  /// Tránh trường hợp có quá nhiều điểm gây ra lỗi đẩy vị trí ra xa hàng cây số.
  static const int maxLevels = 8;

  /// Hàm tính toán tọa độ điều chỉnh cho marker mới.
  /// 
  /// [existingPositions]: Danh sách tọa độ ĐÃ ĐIỀU CHỈNH của các marker đã vẽ trước đó
  /// (bao gồm cả marker rủi ro, thành viên, và điểm đến).
  /// [newLat], [newLng]: Tọa độ thực tế của marker mới cần vẽ.
  /// 
  /// Returns: Một tọa độ Mapbox mới đã được dời lên trên (nếu cần) để không bị đè.
  static mapbox.Position adjustForOverlap({
    required List<mapbox.Position> existingPositions,
    required double newLat,
    required double newLng,
  }) {
    double adjustedLat = newLat;
    int level = 0;

    bool isOverlapping = true;
    
    // Tiếp tục dời lên trên cho đến khi không còn đè lên cái nào, hoặc đạt mức tối đa
    while (isOverlapping && level < maxLevels) {
      isOverlapping = false;
      
      // Kiểm tra với TẤT CẢ các điểm đã tồn tại trên bản đồ
      for (final existing in existingPositions) {
        // Tính khoảng cách thực tế (theo mét) giữa điểm đang xét và điểm cũ
        final dist = geo.Geolocator.distanceBetween(
          adjustedLat,
          newLng,
          existing.lat.toDouble(),
          existing.lng.toDouble(),
        );
        
        // Nếu khoảng cách nhỏ hơn 60 mét -> Bị đè!
        if (dist < overlapThreshold) {
          // Tăng cấp độ dời lên 1
          level += 1;
          // Cộng thêm vào Vĩ độ (Lat) để đẩy điểm lên phía Bắc (hướng lên trên màn hình)
          adjustedLat = newLat + (offsetStep * level);
          isOverlapping = true; // Đánh dấu là vẫn còn đè, cần vòng lặp check lại tọa độ mới
          break; // Thoát vòng lặp con để check lại từ đầu với tọa độ mới
        }
      }
    }

    return mapbox.Position(newLng, adjustedLat);
  }
}
