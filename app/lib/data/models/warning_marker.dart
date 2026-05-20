import 'package:flutter/material.dart';

/// Model đại diện cho 1 Điểm Cảnh Báo (Rủi ro/Nguy hiểm) trên đường.
/// Được đồng bộ từ Backend (Cloud Functions).
/// 
/// Có 5 danh mục chính (Categories):
/// WEATHER (Thời tiết), ACCIDENT (Tai nạn), ROAD_BAD (Đường xấu), POLICE (CSGT), HAZARD_OTHER (Khác)
class WarningMarker {
  final String id;
  final String category;
  final String subtype;
  final String vi; // Tên tiếng Việt hiển thị (VD: "Ổ gà", "Chốt CSGT")
  final double severity; // Mức độ nghiêm trọng hiện tại (sau khi trừ hao theo thời gian)
  final double baseSeverity; // Mức độ nghiêm trọng gốc
  final double lat;
  final double lng;
  final String note;
  final int createdAtMs;
  final double distanceFromRouteKm; // Khoảng cách từ điểm này tới lộ trình (để lọc)
  final double progressKm; // Nằm ở kilomet thứ mấy trên lộ trình (để sắp xếp thứ tự)

  WarningMarker({
    required this.id,
    required this.category,
    required this.subtype,
    required this.vi,
    required this.severity,
    required this.baseSeverity,
    required this.lat,
    required this.lng,
    required this.note,
    required this.createdAtMs,
    required this.distanceFromRouteKm,
    required this.progressKm,
  });

  /// Parse từ JSON response của Backend (Cloud Functions)
  factory WarningMarker.fromJson(Map<String, dynamic> json) {
    return WarningMarker(
      id: json['id']?.toString() ?? '',
      category: json['category']?.toString() ?? 'HAZARD_OTHER',
      subtype: json['subtype']?.toString() ?? 'dark_road',
      vi: json['vi']?.toString() ?? 'Không rõ',
      severity: (json['severity'] as num?)?.toDouble() ?? 0.5,
      baseSeverity: (json['baseSeverity'] as num?)?.toDouble() ?? 0.5,
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      note: json['note']?.toString() ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      distanceFromRouteKm: (json['distanceFromRouteKm'] as num?)?.toDouble() ?? 0.0,
      progressKm: (json['progressKm'] as num?)?.toDouble() ?? 0.0,
    );
  }
/// Trả về màu sắc cho Bong bóng đánh dấu trên bản đồ tùy theo loại rủi ro
  Color get color {
    switch (category) {
      case 'WEATHER':
        // Xét thêm subtype để đổi màu theo từng loại thời tiết
        switch (subtype) {
          case 'sunny': return Colors.orange;     // Nắng -> Cam
          case 'cloudy': return Colors.blueGrey;  // Nhiều mây -> Xám
          case 'rain': return Colors.blue;        // Mưa -> Xanh biển
          case 'storm': return Colors.deepPurple; // Bão -> Tím
          case 'fog': return Colors.grey;         // Sương mù -> Xám nhạt
          default: return Colors.lightBlue;
        }
      case 'ACCIDENT':
        return Colors.red;
      case 'ROAD_BAD':
        return Colors.orange;
      case 'POLICE':
        return Colors.purple;
      case 'HAZARD_OTHER':
      default:
        return Colors.grey;
    }
  }

  /// Trả về Emoji hiển thị trên Bong bóng bản đồ
  String get emoji {
    switch (category) {
      case 'WEATHER':
        // Cập nhật emoji tinh gọn
        switch (subtype) {
          case 'sunny': return '☀️';
          case 'cloudy': return '☁️';
          case 'rain': return '🌧️';
          case 'storm': return '⛈️';
          case 'fog': return '🌫️';
          default: return '🌤️';
        }
      case 'ACCIDENT':
        return '⚠️';
      case 'ROAD_BAD':
        return '🕳️';
      case 'POLICE':
        return '🚓';
      case 'HAZARD_OTHER':
      default:
        return '🚧';
    }
  }

  /// Trả về Icon hiển thị trong danh sách UI (Card List)
  IconData get icon {
    switch (category) {
      case 'WEATHER':
        // Cập nhật Icon của Flutter theo thời tiết
        switch (subtype) {
          case 'sunny': return Icons.wb_sunny;
          case 'cloudy': return Icons.cloud;
          case 'rain': return Icons.water_drop;
          case 'storm': return Icons.thunderstorm;
          case 'fog': return Icons.foggy;
          default: return Icons.wb_cloudy;
        }
      case 'ACCIDENT':
        return Icons.warning;
      case 'ROAD_BAD':
        return Icons.construction;
      case 'POLICE':
        return Icons.local_police;
      case 'HAZARD_OTHER':
      default:
        return Icons.dangerous;
    }
  }

  /// Tính xem cảnh báo này đã được báo cáo cách đây bao nhiêu giờ
  double get ageHours => (DateTime.now().millisecondsSinceEpoch - createdAtMs) / 3600000.0;
}
