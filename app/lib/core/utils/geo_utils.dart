import 'dart:math' as math;

/// Tiện ích tính toán các phép toán địa lý thuần túy.
/// 
/// Tính khoảng cách đường chim bay giữa hai điểm địa lý bằng công thức Haversine.
/// Ưu điểm của hàm này: Tính toán siêu tốc trên RAM mà không cần dùng đến 
/// package bên thứ ba hay kết nối mạng, rất phù hợp để check liên tục (cảnh báo đứt đội hình).
double calculateDistanceMeters({
  required double startLat,
  required double startLng,
  required double endLat,
  required double endLng,
}) {
  const earthRadiusMeters = 6371000.0; // Bán kính Trái Đất (Mét)
  
  // Đổi vĩ độ, kinh độ từ độ (Degrees) sang Radian
  final deltaLat = _degreesToRadians(endLat - startLat);
  final deltaLng = _degreesToRadians(endLng - startLng);
  final originLat = _degreesToRadians(startLat);
  final targetLat = _degreesToRadians(endLat);

  // Công thức Haversine
  final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(originLat) *
          math.cos(targetLat) *
          math.sin(deltaLng / 2) *
          math.sin(deltaLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return earthRadiusMeters * c;
}

/// Đổi độ sang Radian để truyền vào hàm Lượng giác (Sin, Cos)
double _degreesToRadians(double degrees) => degrees * (math.pi / 180.0);
