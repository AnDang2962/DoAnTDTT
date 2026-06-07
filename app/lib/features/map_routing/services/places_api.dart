import 'package:cloud_functions/cloud_functions.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../../core/services/firebase_functions_helper.dart';

class NearbyPlace {
  final String name;
  final double lat;
  final double lng;
  final String address;
  final double distanceKm;
  final String category;

  const NearbyPlace({
    required this.name,
    required this.lat,
    required this.lng,
    required this.address,
    required this.distanceKm,
    required this.category,
  });

  factory NearbyPlace.fromJson(Map<String, dynamic> json) => NearbyPlace(
        name: json['name']?.toString() ?? 'Không rõ tên',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        address: json['address']?.toString() ?? '',
        distanceKm: (json['distanceKm'] as num).toDouble(),
        category: json['category']?.toString() ?? '',
      );

  mapbox.Position get position => mapbox.Position(lng, lat);

  String get categoryLabel {
    const labels = {
      'gas_station': 'Trạm xăng',
      'restaurant': 'Quán ăn',
      'hotel': 'Khách sạn',
      'rest_stop': 'Trạm dừng nghỉ',
      'hospital': 'Bệnh viện',
      'atm': 'ATM',
      'mechanic': 'Tiệm sửa xe',
    };
    return labels[category] ?? category;
  }
}

class PlacesApi {
  static Future<List<NearbyPlace>> searchNearby({
    required double lat,
    required double lng,
    required String placeType,
    double radiusKm = 5.0,
  }) async {
    try {
      final result = await backendFunctions.httpsCallable('searchNearbyPlace').call({
        'lat': lat,
        'lng': lng,
        'placeType': placeType,
        'radiusKm': radiusKm,
      });
      final places = (result.data['places'] as List?) ?? [];
      return places
          .map((p) => NearbyPlace.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
