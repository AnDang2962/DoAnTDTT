import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvKeys {
  // Lấy Key Mapbox
  static String get mapboxPublicKey => dotenv.env['MAPBOX_PUBLIC_KEY'] ?? 'THIẾU_MAPBOX_KEY';
  
  // Lấy Key Thời tiết
  static String get openWeatherApiKey => dotenv.env['OPENWEATHER_API_KEY'] ?? 'THIẾU_OPENWEATHER_KEY';

  // Lấy Key Gemini AI
  static String get geminiApiKey => dotenv.env['GEMINI_API_KEY'] ?? 'THIẾU_GEMINI_KEY';
}