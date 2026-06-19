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
  Color get color {
    switch (category) {
      case 'WEATHER': return Colors.blue;
      case 'ACCIDENT': return Colors.red;
      case 'ROAD_BAD': return Colors.orange;
      case 'POLICE': return Colors.indigo;
      case 'HAZARD_OTHER': return Colors.deepOrange;
      default: return Colors.grey;
    }
  }

  String get emoji {
    switch (category) {
      case 'WEATHER':
        switch (subtype) {
          // user-reported
          case 'heavy_rain': return '🌧️';
          case 'flooding': return '🌊';
          case 'strong_wind': return '💨';
          // weather API display
          case 'rain': return '🌧️';
          case 'storm': return '⛈️';
          case 'snow': return '🌨️';
          case 'sunny': return '☀️';
          case 'cloudy': return '☁️';
          case 'fog': return '🌫️';
          default: return '🌩️';
        }
      case 'ACCIDENT':
        switch (subtype) {
          case 'accident': return '💥';
          case 'traffic_jam': return '🚦';
          case 'breakdown': return '🔧';
          default: return '💥';
        }
      case 'ROAD_BAD':
        switch (subtype) {
          case 'pothole': return '🕳️';
          case 'slippery': return '💧';
          case 'construction': return '🚧';
          case 'gravel': return '🪨';
          default: return '🕳️';
        }
      case 'POLICE':
        switch (subtype) {
          case 'checkpoint': return '🛑';
          case 'mobile_patrol': return '🚔';
          case 'speed_camera': return '📷';
          default: return '👮';
        }
      case 'HAZARD_OTHER':
      default:
        switch (subtype) {
          case 'landslide': return '⛰️';
          case 'fallen_tree': return '🌳';
          case 'animal': return '🦌';
          case 'dark_road': return '🌑';
          default: return '🆘';
        }
    }
  }

  IconData get icon {
    switch (category) {
      case 'WEATHER':
        switch (subtype) {
          // user-reported
          case 'heavy_rain': return Icons.water;
          case 'flooding': return Icons.waves;
          case 'strong_wind': return Icons.air;
          // weather API display
          case 'rain': return Icons.water;
          case 'storm': return Icons.thunderstorm;
          case 'snow': return Icons.ac_unit;
          case 'sunny': return Icons.wb_sunny;
          case 'cloudy': return Icons.cloud;
          case 'fog': return Icons.foggy;
          default: return Icons.thunderstorm;
        }
      case 'ACCIDENT':
        switch (subtype) {
          case 'accident': return Icons.car_crash;
          case 'traffic_jam': return Icons.traffic;
          case 'breakdown': return Icons.build;
          default: return Icons.warning;
        }
      case 'ROAD_BAD':
        switch (subtype) {
          case 'pothole': return Icons.report_problem;
          case 'slippery': return Icons.dangerous;
          case 'construction': return Icons.engineering;
          case 'gravel': return Icons.terrain;
          default: return Icons.construction;
        }
      case 'POLICE':
        switch (subtype) {
          case 'checkpoint': return Icons.local_police;
          case 'mobile_patrol': return Icons.directions_car;
          case 'speed_camera': return Icons.speed;
          default: return Icons.local_police;
        }
      case 'HAZARD_OTHER':
      default:
        switch (subtype) {
          case 'landslide': return Icons.landscape;
          case 'fallen_tree': return Icons.park;
          case 'animal': return Icons.pets;
          case 'dark_road': return Icons.dark_mode;
          default: return Icons.dangerous;
        }
    }
  }

  /// Tính xem cảnh báo này đã được báo cáo cách đây bao nhiêu giờ
  double get ageHours => (DateTime.now().millisecondsSinceEpoch - createdAtMs) / 3600000.0;
}
