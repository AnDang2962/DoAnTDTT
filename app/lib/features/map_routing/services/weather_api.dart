import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/env_keys.dart';
import '../../../data/models/warning_marker.dart';

class WeatherApi {
  /// Lấy dữ liệu thời tiết tại một tọa độ và trả về Cảnh báo (nếu thời tiết xấu)
  static Future<WarningMarker?> checkWeatherRisk(double lat, double lng) async {
    final url = 'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lng&appid=${EnvKeys.openWeatherApiKey}&units=metric&lang=vi';

    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final int weatherId = data['weather'][0]['id'];
        final double temp = data['main']['temp'];
        final int humidity = data['main']['humidity']; // LẤY THÊM ĐỘ ẨM

        // Phân loại thời tiết thành các subtype gọn gàng
        String subtype = 'clear';
        if (weatherId >= 200 && weatherId < 300) subtype = 'storm';
        else if (weatherId >= 300 && weatherId < 600) subtype = 'rain';
        else if (weatherId >= 600 && weatherId < 700) subtype = 'snow';
        else if (weatherId >= 700 && weatherId < 800) subtype = 'fog';
        else if (weatherId == 800) subtype = 'sunny';
        else if (weatherId > 800) subtype = 'cloudy';

        // LỜI DẪN NGẮN GỌN (Ví dụ: "32.5°C • 💧 75%")
        String shortText = '${temp.toStringAsFixed(1)}°C • 💧 $humidity%';

        return WarningMarker(
          id: 'weather_${DateTime.now().millisecondsSinceEpoch}',
          category: 'WEATHER',
          subtype: subtype,
          vi: shortText,
          severity: 0.1, // Thời tiết bình thường thì severity thấp
          baseSeverity: 0.1,
          lat: lat,
          lng: lng,
          note: 'Trạm thời tiết 50km',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          distanceFromRouteKm: 0.0,
          progressKm: 0.0,
        );
      }
    } catch (e) {
      print('Lỗi gọi API Thời tiết: $e');
    }
    return null;
  }
}