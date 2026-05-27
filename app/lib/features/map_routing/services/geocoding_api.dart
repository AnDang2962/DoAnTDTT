import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../../../core/firebase_functions_helper.dart';

/// Geocoding API — gọi Cloud Function `geocodePlace` của backend.
///
/// **Trước:** Gọi trực tiếp api.mapbox.com/geocoding → leak Mapbox token.
/// **Sau:** Backend proxy → token giấu server-side.
///
/// 2 modes:
///   - `searchAutocomplete(query)` — gợi ý type-ahead (limit=5, autocomplete=true)
///   - `findExact(query)` — voice exact (limit=1, autocomplete=false)
class GeocodingApi {
  /// Type-ahead search cho TextField gõ chữ.
  /// Returns: List of suggestions (max 5).
  static Future<List<GeocodedPlace>> searchAutocomplete(String query) async {
    return _callBackend(query: query, limit: 5, autocomplete: true);
  }

  /// Voice search — user nói tên địa điểm chính xác.
  /// Returns: 1st kết quả hoặc null.
  static Future<GeocodedPlace?> findExact(String query) async {
    final places =
        await _callBackend(query: query, limit: 1, autocomplete: false);
    return places.isNotEmpty ? places.first : null;
  }

  static Future<List<GeocodedPlace>> _callBackend({
    required String query,
    required int limit,
    required bool autocomplete,
  }) async {
    if (query.trim().isEmpty) return [];

    try {
      final result = await backendFunctions
          .httpsCallable('geocodePlace')
          .call<Map<String, dynamic>>({
        'query': query.trim(),
        'limit': limit,
        'autocomplete': autocomplete,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final rawPlaces = (data['places'] as List?) ?? [];

      final places = <GeocodedPlace>[];
      for (final p in rawPlaces) {
        if (p is Map) {
          places.add(GeocodedPlace.fromJson(Map<String, dynamic>.from(p)));
        }
      }

      debugPrint(
          '[GeocodingApi] Tìm "$query" (auto=$autocomplete) → ${places.length} kết quả');
      return places;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[GeocodingApi] ✗ Backend error: ${e.code} - ${e.message}');
      return [];
    } catch (e) {
      debugPrint('[GeocodingApi] ✗ Lỗi: $e');
      return [];
    }
  }
}

class GeocodedPlace {
  final String name; // "Đà Lạt"
  final String fullName; // "Đà Lạt, Lâm Đồng, Việt Nam"
  final double lat;
  final double lng;
  final String type;

  GeocodedPlace({
    required this.name,
    required this.fullName,
    required this.lat,
    required this.lng,
    required this.type,
  });

  factory GeocodedPlace.fromJson(Map<String, dynamic> json) {
    return GeocodedPlace(
      name: json['name']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      type: json['type']?.toString() ?? 'unknown',
    );
  }
}
