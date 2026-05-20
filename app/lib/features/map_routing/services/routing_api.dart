import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
// Nạp két sắt chứa Key của M1
import '../../../core/constants/env_keys.dart'; 

class RoutingApi {
  /// 1. Biến tên địa điểm thành Tọa độ (Geocoding)
  static Future<mapbox.Position?> getCoordinates(String placeName) async {
    if (placeName.isEmpty) return null;
    
    // Gắn giới hạn tìm kiếm ở Việt Nam (country=vn) cho chuẩn
    final url = 'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(placeName)}.json?access_token=${EnvKeys.mapboxPublicKey}&country=vn&limit=1';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final coords = data['features'][0]['center'];
          // Mapbox trả về [Longitude, Latitude]
          return mapbox.Position(coords[0], coords[1]); 
        }
      }
    } catch (e) {
      print('Lỗi Geocoding: $e');
    }
    return null;
  }

  /// 2. Lấy danh sách tọa độ để vẽ Polyline đường đi (Directions)
  static Future<List<mapbox.Position>> getRoute(mapbox.Position start, mapbox.Position end) async {
    // Dùng profile 'driving' cho xe máy/ô tô
    final url = 'https://api.mapbox.com/directions/v5/mapbox/driving/${start.lng},${start.lat};${end.lng},${end.lat}?geometries=geojson&access_token=${EnvKeys.mapboxPublicKey}';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final List coordinates = data['routes'][0]['geometry']['coordinates'];
          return coordinates.map((c) => mapbox.Position(c[0] as double, c[1] as double)).toList();
        }
      }
    } catch (e) {
      print('Lỗi Directions: $e');
    }
    return [];
  }
}