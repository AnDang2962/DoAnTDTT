import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Khuôn mẫu để chứa dữ liệu thời tiết gọn gàng
class WeatherInfo {
  final double temperature; // Nhiệt độ (Độ C)
  final String description; // Mô tả (vd: "mưa rào", "trời quang")
  final String iconCode;    // Mã icon để sau này hiển thị hình ảnh

  WeatherInfo({
    required this.temperature, 
    required this.description, 
    required this.iconCode
  });

  factory WeatherInfo.fromJson(Map<String, dynamic> json) {
    return WeatherInfo(
      temperature: json['main']['temp'].toDouble(),
      description: json['weather'][0]['description'],
      iconCode: json['weather'][0]['icon'],
    );
  }
}

/// Dịch vụ kết nối API OpenWeatherMap để lấy thời tiết dọc đường
class WeatherService {
  static final String _apiKey = dotenv.env['OPENWEATHER_API_KEY'] ?? ''; 
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5/weather';

  /// Hàm lấy thời tiết tại 1 điểm tọa độ (Đã được bọc lỗi an toàn)
  static Future<WeatherInfo?> getWeatherAt(double latitude, double longitude) async {
    try {
      // Dựng URL: units=metric (chuyển sang độ C), lang=vi (trả về tiếng Việt)
      final String url = '$_baseUrl?lat=$latitude&lon=$longitude&appid=$_apiKey&units=metric&lang=vi';
      
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return WeatherInfo.fromJson(data);
      } else {
        debugPrint('Lỗi gọi API thời tiết (Mã lỗi: ${response.statusCode})');
        return null;
      }
    } catch (e) {
      debugPrint('Ngoại lệ khi gọi thời tiết: $e');
      return null;
    }
  }
}
