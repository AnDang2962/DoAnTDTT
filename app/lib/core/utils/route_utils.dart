import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart'; // Thêm dòng này để đo khoảng cách

/// Tiện ích hỗ trợ tìm đường và xử lý lộ trình.
class RouteUtils {
  /// Hàm gọi API Mapbox Directions để tìm đường đi từ điểm A đến điểm B.
  /// Lộ trình trả về là một danh sách các tọa độ (đường gấp khúc - polyline) để vẽ lên bản đồ.
  /// Hàm MỚI: Gọi API Mapbox lấy NHIỀU tuyến đường để người dùng lựa chọn
  static Future<List<dynamic>> getMultipleMapboxRoutes(mapbox.Position start, mapbox.Position destination) async {
    final token = dotenv.env['MAPBOX_PUBLIC_KEY'] ?? '';
    
    // ĐÃ THÊM: alternatives=true (để lấy đường phụ) và overview=full (để nét vẽ mượt hơn)
    final url = 'https://api.mapbox.com/directions/v5/mapbox/driving/${start.lng},${start.lat};${destination.lng},${destination.lat}?geometries=geojson&alternatives=true&overview=full&access_token=$token';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Nếu API trả về danh sách lộ trình hợp lệ
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          // Trả về NGUYÊN BẢN toàn bộ mảng routes (chứa cả distance, duration và geometry)
          return data['routes'];
        }
      }
    } catch (e) {
      print("Lỗi API Mapbox lấy nhiều lộ trình: $e");
    }
    return [];
  }

  /// Trích xuất các điểm kiểm tra thời tiết dọc theo lộ trình.
  /// Thuật toán: Đi dọc theo lộ trình, cứ cộng dồn đủ 50km thì lấy ra 1 điểm để check thời tiết.
  static List<mapbox.Position> extractWaypointsEvery50Km(List<mapbox.Position> coords) {
    List<mapbox.Position> waypoints = [];
    if (coords.isEmpty) return waypoints;

    double accumulatedDistance = 0.0;
    
    // Duyệt qua từng đoạn thẳng nhỏ cấu tạo nên lộ trình
    for (int i = 0; i < coords.length - 1; i++) {
      // Tính khoảng cách của đoạn thẳng hiện tại
      double dist = Geolocator.distanceBetween(
        coords[i].lat.toDouble(), coords[i].lng.toDouble(),
        coords[i+1].lat.toDouble(), coords[i+1].lng.toDouble()
      );
      accumulatedDistance += dist;

      // Nếu tổng khoảng cách đã đi qua đạt 50,000 mét (50km)
      if (accumulatedDistance >= 50000) { 
        // Lấy điểm này làm điểm check thời tiết
        waypoints.add(coords[i+1]);
        // Reset lại khoảng cách để đo tiếp 50km tiếp theo
        accumulatedDistance = 0.0;
      }
    }
    return waypoints;
  }
}
