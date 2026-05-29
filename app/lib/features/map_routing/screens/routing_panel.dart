import 'dart:math' show cos, sqrt, asin;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import 'package:route_mate_app/core/utils/route_utils.dart';
import 'package:route_mate_app/features/main_map/providers/map_state_provider.dart';

import '../services/routing_api.dart';
import '../services/weather_api.dart'; 
import '../../../data/models/warning_marker.dart';
import '../../../data/repositories/room_repository.dart'; // ĐÃ THÊM: Import RoomRepository

import '../widgets/routing_search_bar.dart'; 
import '../widgets/voice_record_btn.dart';
import '../services/gemini_ai_api.dart';

class RoutingPanel extends StatefulWidget {
  final String? roomId; // ĐÃ THÊM: Biến nhận ID phòng (nếu có)
  
  // ĐÃ SỬA: Cho phép truyền roomId vào
  const RoutingPanel({Key? key, this.roomId}) : super(key: key); 

  @override
  State<RoutingPanel> createState() => _RoutingPanelState();
}

// ĐÃ XÓA: Các biến trôi nổi ở ngoài class (đã chuyển vào Provider và State)

class _RoutingPanelState extends State<RoutingPanel> {
  bool _isLoading = false; // ĐÃ CHUYỂN VÀO ĐÂY: Biến loading nằm đúng vị trí
  mapbox.Position? _previewDestPos;

  // BIẾN MỚI CHO HIỂN THỊ THÔNG TIN CHUYẾN ĐI
  double _routeDistance = 0.0;
  int _routeDurationMins = 0;

  // ĐÃ THÊM: Khởi tạo RoomRepository để đẩy lộ trình lên Firebase
  final RoomRepository _roomRepo = RoomRepository(); 

  /// THUẬT TOÁN HAVERSINE (Tính khoảng cách đường chim bay)
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var a = 0.5 - cos((lat2 - lat1) * p)/2 + 
            cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p))/2;
    return 12742 * asin(sqrt(a)); 
  }

  Future<void> _handleDestinationSelected(mapbox.Position destPos, String placeName) async {
    FocusScope.of(context).unfocus(); 
    setState(() => _isLoading = true); 

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

      // Gọi API Mapbox lấy danh sách ĐA TUYẾN ĐƯỜNG
      final routes = await RouteUtils.getMultipleMapboxRoutes(startPos, destPos);

      if (routes.isEmpty) {
        _showToast('Không tìm thấy đường đi tới điểm này!');
        return;
      }

      // Bắn toàn bộ 2-3 tuyến đường vào Trạm trung chuyển Provider
      if (mounted) {
        context.read<MapStateProvider>().setRoutesData(routes, placeName);
        // Bắn lệnh vẽ 2-3 đường preview lên bản đồ
        await context.read<MapStateProvider>().drawMultipleRoutesPreview();
        await context.read<MapStateProvider>().drawDestinationMarker(destPos, placeName);
      }

      setState(() {
        _previewDestPos = destPos;
      });

    } catch (e) {
      _showToast('Có lỗi xảy ra khi tìm đường: $e');
    } finally {
      setState(() => _isLoading = false); 
    }
  }

  Future<void> _startRouting() async {
    final mapProvider = context.read<MapStateProvider>();
    
    if (mapProvider.availableRoutes.isEmpty) return; 
    
    setState(() => _isLoading = true);

    try {
      final chosenRoute = mapProvider.availableRoutes[mapProvider.selectedRouteIndex];
      final geometry = chosenRoute['geometry']['coordinates'] as List;

      // 1. Xử lý tọa độ cho bản đồ 
      final routeCoords = geometry
          .map((c) => mapbox.Position(c[0].toDouble(), c[1].toDouble()))
          .toList();
          
      // 2. SỬA LỖI ÉP KIỂU TẠI ĐÂY: Bắt buộc khai báo rõ List<Map<String, double>>
      final List<Map<String, double>> polylineData = geometry
          .map<Map<String, double>>((c) => {
                'lng': (c[0] as num).toDouble(),
                'lat': (c[1] as num).toDouble()
              })
          .toList();

      // 3. Vẽ đường đơn tuyến chính thức lên bản đồ
      await mapProvider.drawRoutePolyline(routeCoords);

      // 4. KIỂM TRA VÀ ĐẨY LÊN FIREBASE (Đoạn của bạn được giữ nguyên 100%)
      if (widget.roomId != null && widget.roomId!.isNotEmpty) {
        await _roomRepo.setRoomRoute(
          roomId: widget.roomId!, 
          polyline: polylineData,
          startName: 'Vị trí hiện tại',
          endName: mapProvider.previewDestName ?? 'Điểm đến', 
        );
      }

      // THUẬT TOÁN CHIA MATCH POINTS (50KM/LẦN)
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

        if (distSinceLast >= 50.0) {
          matchPoints.add(routeCoords[i+1]);
          distSinceLast = 0.0;
        }
      }

      // GỌI API THỜI TIẾT TẠI CÁC MATCH POINTS
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

      mapProvider.startNavigating();

      setState(() {
        _routeDistance = chosenRoute['distance'] / 1000.0; 
        _routeDurationMins = (chosenRoute['duration'] / 60.0).round(); 
      });

    } catch (e) {
      _showToast("Lỗi vẽ đường: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showToast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapStateProvider>();

    return Stack(
      children: [
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
                    mapProvider.clearRoutes(); 
                    setState(() {
                      _previewDestPos = null;
                    });
                  },
                ),
              ],
            ),
          ), 
        ),

        if (mapProvider.availableRoutes.isNotEmpty && !_isLoading && !mapProvider.isNavigating)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 24.0, left: 16, right: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Khoảng cách: ${(mapProvider.availableRoutes[mapProvider.selectedRouteIndex]['distance'] / 1000).toStringAsFixed(1)} km '
                    '• Thời gian: ${(mapProvider.availableRoutes[mapProvider.selectedRouteIndex]['duration'] / 60).toStringAsFixed(0)} phút',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                  ),
                  const SizedBox(height: 12),
                  
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(mapProvider.availableRoutes.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: ChoiceChip(
                            label: Text('Tuyến ${index + 1}', style: TextStyle(fontWeight: index == mapProvider.selectedRouteIndex ? FontWeight.bold : FontWeight.normal)),
                            selected: mapProvider.selectedRouteIndex == index,
                            selectedColor: Colors.blue[100],
                            onSelected: (selected) async {
                              if (selected) {
                                mapProvider.selectRoute(index); // Đổi index trong Provider
                                // Kêu Provider vẽ lại màu (Đổi đường Xám thành Xanh)
                                await mapProvider.drawMultipleRoutesPreview();
                              }
                            },
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),

                  ElevatedButton.icon(
                    onPressed: _startRouting,
                    icon: const Icon(Icons.two_wheeler, color: Colors.white),
                    label: const Text('Bắt đầu đi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 4,
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (mapProvider.isNavigating)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
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
                      mapProvider.clearRoutes(); 
                    },
                    backgroundColor: Colors.redAccent,
                    child: const Icon(Icons.close, color: Colors.white),
                  )
                ],
              ),
            ),
          ),

        if (mapProvider.isNavigating)
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
                child: VoiceRecordButton(
                  onResult: (spokenText) async {
                    if (spokenText.isEmpty) return;
                    
                    final result = await GeminiAiApi.analyzeCommand(spokenText);
                    if (result == null) {
                      _showToast('Không kết nối được AI');
                      return;
                    }
                    
                    final action = result['action']?.toString() ?? 'unknown';
                    final response = result['responseText']?.toString() ?? '';
                    
                    if (response.isNotEmpty) {
                      _showToast(response);
                    }
                    
                    debugPrint('[VoiceCommand] Action: $action');
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}