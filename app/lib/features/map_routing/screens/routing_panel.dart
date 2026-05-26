import 'dart:math' show cos, sqrt, asin; // Thư viện toán học cho Haversine
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import 'package:route_mate_app/features/main_map/providers/map_state_provider.dart';

import '../services/routing_api.dart';
import '../services/weather_api.dart'; // Đảm bảo import API thời tiết của bạn
import '../../../data/models/warning_marker.dart';

import '../widgets/routing_search_bar.dart'; 
import '../widgets/voice_record_btn.dart';
import '../services/gemini_ai_api.dart';

class RoutingPanel extends StatefulWidget {
  const RoutingPanel({Key? key}) : super(key: key);

  @override
  State<RoutingPanel> createState() => _RoutingPanelState();
}

class _RoutingPanelState extends State<RoutingPanel> {
  
  bool _isLoading = false;
  mapbox.Position? _previewDestPos;

  // BIẾN MỚI CHO HIỂN THỊ THÔNG TIN CHUYẾN ĐI
  bool _isNavigating = false;
  double _routeDistance = 0.0;
  int _routeDurationMins = 0;

  /// THUẬT TOÁN HAVERSINE (Tính khoảng cách đường chim bay)
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var a = 0.5 - cos((lat2 - lat1) * p)/2 + 
            cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p))/2;
    return 12742 * asin(sqrt(a)); // Trả về số Kilomet
  }

  Future<void> _handleDestinationSelected(mapbox.Position position, String placeName) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _previewDestPos = position;
      _isNavigating = false; // Tắt chế độ dẫn đường nếu đang có
    });
    await context.read<MapStateProvider>().drawDestinationMarker(position, placeName);
  }

  /// HÀM XỬ LÝ LỆNH AI (Đã được nâng cấp để nhận trực tiếp câu nói)  /// HÀM BẮT ĐẦU ĐI (ĐÃ CẬP NHẬT CHIA ĐIỂM 50KM VÀ THỜI TIẾT)
  Future<void> _startRouting() async {
    if (_previewDestPos == null) return;
    setState(() => _isLoading = true);
    final mapProvider = context.read<MapStateProvider>();

    try {
      Position? currentPos;
      try {
        currentPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        currentPos = await Geolocator.getLastKnownPosition();
      }

      double startLng = currentPos?.longitude ?? 109.1967;
      double startLat = currentPos?.latitude ?? 12.2388;
      final startPos = mapbox.Position(startLng, startLat);

      final routeCoords = await RoutingApi.getRoute(startPos, _previewDestPos!);
      
      if (routeCoords.isNotEmpty) {
        await mapProvider.drawRoutePolyline(routeCoords);

        // ==========================================
        // THUẬT TOÁN CHIA MATCH POINTS (50KM/LẦN)
        // ==========================================
        double totalDist = 0.0;
        double distSinceLast = 0.0;
        List<mapbox.Position> matchPoints = [];

        for (int i = 0; i < routeCoords.length - 1; i++) {
          double d = _haversineDistance(
            routeCoords[i].lat.toDouble(), routeCoords[i].lng.toDouble(),
            routeCoords[i+1].lat.toDouble(), routeCoords[i+1].lng.toDouble()
          );
          totalDist += d;
          distSinceLast += d;

          // Cứ đi được thêm 50km thì đánh dấu 1 điểm
          if (distSinceLast >= 50.0) {
            matchPoints.add(routeCoords[i+1]);
            distSinceLast = 0.0; // Reset lại bộ đếm
          }
        }

        // ==========================================
        // GỌI API THỜI TIẾT TẠI CÁC MATCH POINTS
        // ==========================================
        if (matchPoints.isNotEmpty) {
          _showToast("Đang phân tích thời tiết trên lộ trình...");
          List<WarningMarker> weatherWarnings = [];
          
          for (var pt in matchPoints) {
            final warning = await WeatherApi.checkWeatherRisk(pt.lat.toDouble(), pt.lng.toDouble());
            if (warning != null) weatherWarnings.add(warning);
          }

          if (weatherWarnings.isNotEmpty) {
            await mapProvider.drawWeatherMarkers(weatherWarnings);
            _showToast("Phát hiện ${weatherWarnings.length} khu vực thời tiết xấu!");
          }
        }

        // CHUYỂN SANG GIAO DIỆN DẪN ĐƯỜNG (Hiện thời gian, quãng đường)
        setState(() {
          _previewDestPos = null; 
          _isNavigating = true;
          _routeDistance = totalDist;
          // Phượt xe máy mặc định tốc độ 40km/h
          _routeDurationMins = (totalDist / 40.0 * 60).round(); 
        });

      } else {
        _showToast("Không tìm thấy lộ trình!");
      }
    } catch (e) {
      _showToast("Lỗi vẽ đường!");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ===================================
        // KHỐI UI 1: THANH TÌM KIẾM (Đỉnh màn hình)
        // ===================================
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RoutingSearchBar(
                  onDestinationSelected: _handleDestinationSelected,
                  onClear: () {
                    context.read<MapStateProvider>().clearAll();
                    setState(() {
                      _previewDestPos = null;
                      _isNavigating = false;
                    });
                  },
                ),
              ], // <--- PHẢI CÓ DẤU NÀY ĐỂ ĐÓNG COLUMN
            ), // <--- PHẢI CÓ DẤU NÀY ĐỂ ĐÓNG CONTAINER
          ), 
        ),

        // ===================================
        // KHỐI UI 2: NÚT BẮT ĐẦU (Xem trước)
        // ===================================
        if (_previewDestPos != null && !_isLoading && !_isNavigating)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: ElevatedButton.icon(
                onPressed: _startRouting,
                icon: const Icon(Icons.two_wheeler, color: Colors.white), // Đổi icon xe máy
                label: const Text('Bắt đầu đi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 8,
                ),
              ),
            ),
          ),

        // ===================================
        // KHỐI UI 3: BẢNG THÔNG TIN CHUYẾN ĐI (Giống Google Maps)
        // ===================================
        if (_isNavigating)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, -2))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Đổi phút ra Giờ/Phút cho đẹp
                        _routeDurationMins > 60 
                          ? '${_routeDurationMins ~/ 60} giờ ${_routeDurationMins % 60} phút'
                          : '$_routeDurationMins phút',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_routeDistance.toStringAsFixed(1)} km • Đi bằng xe máy',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                  FloatingActionButton(
                    onPressed: () {
                      context.read<MapStateProvider>().clearAll();
                      setState(() => _isNavigating = false);
                    },
                    backgroundColor: Colors.redAccent,
                    child: const Icon(Icons.close, color: Colors.white),
                  )
                ],
              ),
            ),
          ),
          // ===================================
        // KHỐI UI 4: NÚT BÁO CÁO SỰ CỐ DÀNH CHO LEADER
        // (Chỉ hiện ra khi đang trong chế độ Dẫn đường)
        // ===================================
        if (_isNavigating)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.redAccent.withOpacity(0.4), blurRadius: 15, spreadRadius: 2)
                  ]
                ),
                // Sử dụng lại component VoiceRecordButton xịn sò của bạn
                child: VoiceRecordButton(
                  onResult: (spokenText) async {
                    if (spokenText.isEmpty) return;
                    
                    final result = await GeminiAiApi.analyzeCommand(spokenText);
                    if (result == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Không kết nối được AI')),
                      );
                      return;
                    }
                    
                    final action = result['action']?.toString() ?? 'unknown';
                    final response = result['responseText']?.toString() ?? '';
                    
                    if (response.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(response),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                    
                    debugPrint('[VoiceCommand] Action: $action');
                    // TODO: Xử lý từng action (find_nearby_place, check_weather, ...)
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}