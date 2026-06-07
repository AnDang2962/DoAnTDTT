import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/services/firebase_functions_helper.dart';
import '../../../data/models/warning_marker.dart';

/// Weather API — gọi Cloud Function `getWeatherAlongRoute` của backend.
///
/// **Trước:** Gọi trực tiếp OpenWeatherMap → leak API key ở client.
/// **Sau:** Gọi backend làm proxy → OpenWeather key giấu ở server.
///
/// Display format: "32.5°C • 💧 75% • mưa nhẹ"
class WeatherApi {
  /// Lấy dữ liệu thời tiết tại tọa độ và trả về WarningMarker.
  ///
  /// Backend WeatherResult schema (cần backend thêm `humidity` field):
  ///   {
  ///     lat, lng,
  ///     tempC: number,           // Nhiệt độ Celsius
  ///     humidity: number,        // Độ ẩm %
  ///     weatherMain: string,     // 'Clear', 'Rain', 'Storm', ...
  ///     description: string,     // 'mưa nhẹ', 'trời quang' (đã tiếng Việt)
  ///     isDangerous: boolean,
  ///     rawCode: number,         // OpenWeatherMap weather ID (200-804)
  ///   }
  static Future<WarningMarker?> checkWeatherRisk(double lat, double lng, {double progressKm = 0.0}) async {
    try {
      final result = await backendFunctions
          .httpsCallable('getWeatherAlongRoute')
          .call<Map<String, dynamic>>({
        'lat': lat,
        'lng': lng,
      });

      final data = Map<String, dynamic>.from(result.data as Map);

      final tempC = (data['tempC'] as num?)?.toDouble() ?? 0.0;
      final humidity = (data['humidity'] as num?)?.toInt() ?? 0;
      final rawCode = (data['rawCode'] as num?)?.toInt() ?? 800;
      final description = data['description']?.toString() ?? '';

      // Phân loại subtype theo weather ID (logic gốc giữ nguyên)
      String subtype;
      if (rawCode >= 200 && rawCode < 300) {
        subtype = 'heavy_rain'; // Bão → mưa to
      } else if (rawCode >= 300 && rawCode < 600) {
        subtype = 'heavy_rain';
      } else if (rawCode >= 700 && rawCode < 800) {
        subtype = 'fog';
      } else {
        subtype = 'fog'; // mặc định fallback
      }

      final tempDisplay = '${tempC.toStringAsFixed(1)}°C • 💧 $humidity%';

      return WarningMarker(
        id: 'weather_${DateTime.now().millisecondsSinceEpoch}',
        category: 'WEATHER',
        subtype: subtype,
        vi: tempDisplay,
        severity: 0.1,
        baseSeverity: 0.1,
        lat: lat,
        lng: lng,
        note: description,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        distanceFromRouteKm: 0.0,
        progressKm: progressKm,
      );
    } catch (_) {
      return null;
    }
  }
}
