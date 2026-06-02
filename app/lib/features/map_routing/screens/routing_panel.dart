import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:route_mate_app/core/utils/route_utils.dart';
import 'package:route_mate_app/core/services/solo_room_service.dart';
import 'package:route_mate_app/features/main_map/providers/map_state_provider.dart';

import '../services/weather_api.dart';
import '../../../data/models/warning_marker.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../data/repositories/warning_repository.dart';

import '../widgets/routing_search_bar.dart';
import '../widgets/risk_report_sheet.dart';
import '../widgets/voice_record_btn.dart';
import '../services/gemini_ai_api.dart';
import '../../voice/services/voice_action_dispatcher.dart';

class RoutingPanel extends StatefulWidget {
  final String? roomId;

  const RoutingPanel({super.key, this.roomId});

  @override
  State<RoutingPanel> createState() => _RoutingPanelState();
}

class _RoutingPanelState extends State<RoutingPanel> {
  bool _isLoading = false;
  mapbox.Position? _previewDestPos;
  mapbox.Position? _myLastPos;

  double _routeDistance = 0.0;
  int _routeDurationMins = 0;

  final RoomRepository _roomRepo = RoomRepository();
  final WarningRepository _warningRepo = WarningRepository();
  StreamSubscription<List<WarningMarker>>? _riskSub;
  Timer? _riskRefreshTimer;
  StreamSubscription<Position>? _navGpsSub;

  // Hai nguồn risk riêng biệt — gộp trước khi vẽ để không ghi đè nhau
  List<WarningMarker> _realtimeRisks = [];
  List<WarningMarker> _crossGroupRisks = [];

  /// Gộp 2 nguồn risk (dedup theo id) và vẽ 1 lần duy nhất.
  void _redrawAllRisks() {
    if (!mounted) return;
    final merged = <String, WarningMarker>{};
    for (final r in _realtimeRisks) merged[r.id] = r;
    // Cross-group ghi đè nếu trùng id (có severity chính xác hơn)
    for (final r in _crossGroupRisks) merged[r.id] = r;
    context.read<MapStateProvider>().drawRiskMarkers(merged.values.toList(), {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSoloRiskListener());
  }

  void _startSoloRiskListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final soloRoomId = widget.roomId?.isNotEmpty == true
        ? widget.roomId!
        : uidToSoloRoomCode(uid);

    _riskSub = _warningRepo.listenToRoomWarnings(soloRoomId).listen((risks) {
      if (!mounted) return;
      _realtimeRisks = risks;
      _redrawAllRisks();
    });
  }

  /// Refresh cross-group risks định kỳ 5 phút khi đang điều hướng.
  void _startCrossGroupRiskTimer(List<Map<String, double>> polylineData) {
    _riskRefreshTimer?.cancel();
    _riskRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (!mounted) { _riskRefreshTimer?.cancel(); return; }
      final mapProvider = context.read<MapStateProvider>();
      if (!mapProvider.isNavigating) { _riskRefreshTimer?.cancel(); return; }

      final risks = await _warningRepo.getRiskLabelsNearRoute(polyline: polylineData);
      if (mounted) {
        _crossGroupRisks = risks;
        _redrawAllRisks();
      }
    });
  }

  void _startNavGpsStream() {
    _navGpsSub?.cancel();
    _navGpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      if (!mounted) return;
      _myLastPos = mapbox.Position(pos.longitude, pos.latitude);
      final mapProvider = context.read<MapStateProvider>();
      mapProvider.trimRouteToProgress(_myLastPos!);
      if (mapProvider.isFollowing) {
        mapProvider.easeTo(_myLastPos!, bearing: pos.heading >= 0 ? pos.heading : null);
      }
    });
  }

  void _stopNavGpsStream() {
    _navGpsSub?.cancel();
    _navGpsSub = null;
  }

  @override
  void dispose() {
    _riskSub?.cancel();
    _riskRefreshTimer?.cancel();
    _navGpsSub?.cancel();
    super.dispose();
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

      final routes = await RouteUtils.getMultipleMapboxRoutes(startPos, destPos);

      if (routes.isEmpty) {
        _showToast('Không tìm thấy đường đi tới điểm này!');
        return;
      }

      if (mounted) {
        context.read<MapStateProvider>().setRoutesData(routes, placeName);
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

      final routeCoords = geometry
          .map((c) => mapbox.Position(c[0].toDouble(), c[1].toDouble()))
          .toList();
          
      final List<Map<String, double>> polylineData = RouteUtils.downsamplePolyline(
        geometry
            .map<Map<String, double>>((c) => {
                  'lng': (c[0] as num).toDouble(),
                  'lat': (c[1] as num).toDouble()
                })
            .toList(),
      );

      await mapProvider.drawRoutePolyline(routeCoords);
      mapProvider.setFullRoute(routeCoords);

      if (widget.roomId != null && widget.roomId!.isNotEmpty) {
        await _roomRepo.setRoomRoute(
          roomId: widget.roomId!, 
          polyline: polylineData,
          startName: 'Vị trí hiện tại',
          endName: mapProvider.previewDestName ?? 'Điểm đến', 
        );
      }

      _crossGroupRisks = await _warningRepo.getRiskLabelsNearRoute(polyline: polylineData);
      if (_crossGroupRisks.isNotEmpty && mounted) {
        _redrawAllRisks();
        _showToast('Phát hiện ${_crossGroupRisks.length} cảnh báo nguy hiểm trên lộ trình!');
      }
      _startCrossGroupRiskTimer(polylineData);

      final matchPoints = RouteUtils.extractWaypointsEvery50Km(routeCoords);

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
      _startNavGpsStream();

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
        if (!mapProvider.isNavigating)
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
                  Builder(builder: (_) {
                    final routes = mapProvider.availableRoutes;
                    final fastestSecs = routes
                        .map((r) => (r['duration'] as num).toDouble())
                        .reduce((a, b) => a < b ? a : b);
                    final selected = routes[mapProvider.selectedRouteIndex];
                    final selKm = (selected['distance'] / 1000).toStringAsFixed(1);
                    final selMins = (selected['duration'] / 60).round();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.straighten, size: 16, color: Colors.blueAccent),
                            const SizedBox(width: 4),
                            Text('$selKm km', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                            const SizedBox(width: 16),
                            const Icon(Icons.schedule, size: 16, color: Colors.blueAccent),
                            const SizedBox(width: 4),
                            Text(
                              selMins > 60
                                  ? '${selMins ~/ 60} giờ ${selMins % 60} phút'
                                  : '$selMins phút',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(routes.length, (index) {
                              final isSelected = mapProvider.selectedRouteIndex == index;
                              final durationMins = (routes[index]['duration'] / 60).round();
                              final isFastest = (routes[index]['duration'] as num).toDouble() == fastestSecs;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                child: ChoiceChip(
                                  label: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Tuyến ${index + 1}',
                                        style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                                      ),
                                      Text(
                                        isFastest ? '$durationMins ph ✓' : '$durationMins ph',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isFastest ? Colors.green[700] : Colors.grey[600],
                                          fontWeight: isFastest ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                  selected: isSelected,
                                  selectedColor: Colors.blue[100],
                                  onSelected: (sel) async {
                                    if (sel) {
                                      mapProvider.selectRoute(index);
                                      await mapProvider.drawMultipleRoutesPreview();
                                    }
                                  },
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    );
                  }),
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

        if (mapProvider.isNavigating && mapProvider.isOffRoute)
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 90, left: 16, right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange[700],
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Bạn đã lệch tuyến đường!',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: _previewDestPos == null
                        ? null
                        : () async {
                            final dest = _previewDestPos!;
                            final destName = mapProvider.previewDestName ?? 'Điểm đến';
                            _stopNavGpsStream();
                            _riskRefreshTimer?.cancel();
                            await context.read<MapStateProvider>().clearAll();
                            mapProvider.clearRoutes();
                            await _handleDestinationSelected(dest, destName);
                          },
                    child: const Text(
                      'Tính lại',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
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
                children: [
                  Expanded(
                    child: Column(
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
                  ),
                  Row(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'risk_fab_solo',
                        backgroundColor: Colors.orange[700],
                        onPressed: () async {
                          final pos = _myLastPos;
                          if (pos == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Chưa lấy được vị trí GPS')),
                            );
                            return;
                          }
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          final effectiveRoomId =
                              (widget.roomId != null && widget.roomId!.isNotEmpty)
                                  ? widget.roomId!
                                  : (uid != null ? uidToSoloRoomCode(uid) : '');
                          if (effectiveRoomId.isEmpty) return;
                          final reported = await RiskReportSheet.show(
                            context,
                            roomId: effectiveRoomId,
                            lat: pos.lat.toDouble(),
                            lng: pos.lng.toDouble(),
                          );
                          if (reported && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã báo cáo sự cố thành công!')),
                            );
                          }
                        },
                        child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'stop_nav_fab',
                        onPressed: () {
                          _riskRefreshTimer?.cancel();
                          _stopNavGpsStream();
                          context.read<MapStateProvider>().clearAll();
                          mapProvider.clearRoutes();
                        },
                        backgroundColor: Colors.redAccent,
                        child: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),

        if (!mapProvider.isNavigating || !mapProvider.isFollowing)
          Positioned(
            bottom: 200,
            right: 16,
            child: GestureDetector(
              onTap: () => context.read<MapStateProvider>().flyToCurrentLocation(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: Icon(
                  mapProvider.isNavigating ? Icons.navigation : Icons.my_location,
                  color: Colors.blue,
                  size: 22,
                ),
              ),
            ),
          ),

        if (mapProvider.isNavigating)
          Positioned(
            bottom: 128,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.redAccent.withValues(alpha: 0.4), blurRadius: 15, spreadRadius: 2),
                ],
              ),
              child: VoiceRecordButton(
                  onResult: (spokenText) async {
                    if (spokenText.isEmpty) return;

                    Position? currentPos;
                    try {
                      currentPos = await Geolocator.getCurrentPosition(
                        desiredAccuracy: LocationAccuracy.high,
                        timeLimit: const Duration(seconds: 3),
                      );
                    } catch (_) {
                      currentPos = await Geolocator.getLastKnownPosition();
                    }

                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    final effectiveRoomId =
                        (widget.roomId != null && widget.roomId!.isNotEmpty)
                            ? widget.roomId!
                            : (uid != null ? uidToSoloRoomCode(uid) : '');

                    final result = await GeminiAiApi.analyzeCommand(
                      spokenText,
                      roomId: effectiveRoomId,
                      currentLat: currentPos?.latitude,
                      currentLng: currentPos?.longitude,
                    );

                    if (result == null) {
                      _showToast('Không kết nối được AI');
                      return;
                    }

                    if (!mounted) return;
                    await VoiceActionDispatcher(
                      context: context,
                      isInGroup: widget.roomId?.isNotEmpty == true,
                      roomId: effectiveRoomId,
                      currentLat: currentPos?.latitude,
                      currentLng: currentPos?.longitude,
                      currentUserId: uid ?? '',
                      onNavigateTo: _handleDestinationSelected,
                    ).dispatch(result);
                  },
                ),
              ),
            ),
      ],
    );
  }
}