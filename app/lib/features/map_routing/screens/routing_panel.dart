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
  final bool isActive;

  const RoutingPanel({super.key, this.roomId, this.isActive = true});

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

  List<WarningMarker> _realtimeRisks = [];
  List<WarningMarker> _crossGroupRisks = [];
  List<Map<String, double>> _polylineData = [];

  void _redrawAllRisks() {
    if (!mounted) return;
    final mapProvider = context.read<MapStateProvider>();
    if (mapProvider.isGroupModeActive) return;
    final merged = <String, WarningMarker>{};
    for (final r in _realtimeRisks) merged[r.id] = r;
    for (final r in _crossGroupRisks) merged[r.id] = r;
    mapProvider.drawRiskMarkers(merged.values.toList(), {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSoloRiskListener());
  }

  @override
  void didUpdateWidget(RoutingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _stopNavGpsStream();
      _riskRefreshTimer?.cancel();
      if (mounted) {
        final mapProvider = context.read<MapStateProvider>();
        if (mapProvider.isNavigating) {
          unawaited(mapProvider.clearAll());
          mapProvider.clearRoutes();
          setState(() {
            _previewDestPos = null;
            _routeDistance = 0.0;
            _routeDurationMins = 0;
          });
        }
      }
    }
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
      if (mapProvider.isNavigating) {
        unawaited(mapProvider.setNavArrow(_myLastPos!));
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
      final mapProvider = context.read<MapStateProvider>();
      await mapProvider.clearAll();
      mapProvider.clearRoutes();
      await mapProvider.drawDestinationMarker(destPos, placeName);
      setState(() {
        _previewDestPos = destPos;
        _polylineData = [];
      });
    } catch (e) {
      _showSnackbar('Có lỗi xảy ra: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getDirections() async {
    if (_previewDestPos == null) return;
    setState(() => _isLoading = true);
    try {
      Position? currentPos;
      try {
        currentPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (_) {
        currentPos = await Geolocator.getLastKnownPosition();
      }

      final startLng = currentPos?.longitude ?? 109.1967;
      final startLat = currentPos?.latitude ?? 12.2388;
      final startPos = mapbox.Position(startLng, startLat);

      final routes = await RouteUtils.getMultipleMapboxRoutes(startPos, _previewDestPos!);
      if (routes.isEmpty) { _showSnackbar('Không tìm thấy đường đi tới điểm này!'); return; }

      final mapProvider = context.read<MapStateProvider>();
      mapProvider.setRoutesData(routes, mapProvider.previewDestName ?? '');
      await mapProvider.drawMultipleRoutesPreview();

      await _loadRouteDetails(routes, mapProvider.selectedRouteIndex, startPos);
    } catch (e) {
      _showSnackbar('Có lỗi xảy ra khi tìm đường: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRouteDetails(
    List<dynamic> routes,
    int routeIndex,
    mapbox.Position startPos,
  ) async {
    final mapProvider = context.read<MapStateProvider>();
    final geometry = routes[routeIndex]['geometry']['coordinates'] as List;
    final positions = geometry
        .map((c) => mapbox.Position(c[0].toDouble(), c[1].toDouble()))
        .toList();

    mapProvider.fitBoundsToPositions([startPos, ...positions]);

    _polylineData = RouteUtils.downsamplePolyline(
      geometry.map<Map<String, double>>((c) => {
        'lng': (c[0] as num).toDouble(),
        'lat': (c[1] as num).toDouble(),
      }).toList(),
    );

    await mapProvider.drawWeatherMarkers([]);
    _crossGroupRisks = [];

    final matchPoints = RouteUtils.extractWaypointsEvery50Km(positions);
    if (matchPoints.isNotEmpty) {
      _showSnackbar('Đang phân tích thời tiết trên lộ trình...');
      final weatherWarnings = <WarningMarker>[];
      for (int i = 0; i < matchPoints.length; i++) {
        final w = await WeatherApi.checkWeatherRisk(
          matchPoints[i].lat.toDouble(),
          matchPoints[i].lng.toDouble(),
          progressKm: (i + 1) * 50.0,
        );
        if (w != null) weatherWarnings.add(w);
      }
      if (weatherWarnings.isNotEmpty && mounted) {
        await mapProvider.drawWeatherMarkers(weatherWarnings);
        _showSnackbar('Phát hiện ${weatherWarnings.length} khu vực thời tiết xấu!');
      }
    }

    _crossGroupRisks = await _warningRepo.getRiskLabelsNearRoute(polyline: _polylineData);
    if (_crossGroupRisks.isNotEmpty && mounted) {
      _redrawAllRisks();
      _showSnackbar('Phát hiện ${_crossGroupRisks.length} cảnh báo nguy hiểm trên lộ trình!');
    }
  }

  Future<void> _startRouting() async {
    final mapProvider = context.read<MapStateProvider>();

    // Nếu chưa có routes (bấm "Bắt đầu đi" thẳng từ giai đoạn 1), fetch trước
    if (mapProvider.availableRoutes.isEmpty) {
      await _getDirections();
      if (!mounted || mapProvider.availableRoutes.isEmpty) return;
    }

    setState(() => _isLoading = true);
    try {
      final chosenRoute = mapProvider.availableRoutes[mapProvider.selectedRouteIndex];
      final geometry = chosenRoute['geometry']['coordinates'] as List;
      final routeCoords = geometry
          .map((c) => mapbox.Position(c[0].toDouble(), c[1].toDouble()))
          .toList();

      await mapProvider.drawRoutePolyline(routeCoords);
      mapProvider.setFullRoute(routeCoords);

      if (widget.roomId != null && widget.roomId!.isNotEmpty) {
        await _roomRepo.setRoomRoute(
          roomId: widget.roomId!,
          polyline: _polylineData,
          startName: 'Vị trí hiện tại',
          endName: mapProvider.previewDestName ?? 'Điểm đến',
        );
      }

      if (_polylineData.isNotEmpty) _startCrossGroupRiskTimer(_polylineData);

      mapProvider.startNavigating();
      _startNavGpsStream();
      mapProvider.flyToCurrentLocation();

      setState(() {
        _routeDistance = (chosenRoute['distance'] as num).toDouble() / 1000.0;
        _routeDurationMins = ((chosenRoute['duration'] as num).toDouble() / 60.0).round();
      });
    } catch (e) {
      _showSnackbar('Lỗi bắt đầu điều hướng: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String get _effectiveRoomId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (widget.roomId != null && widget.roomId!.isNotEmpty) return widget.roomId!;
    return uid != null ? uidToSoloRoomCode(uid) : '';
  }

  void _showSnackbar(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildRouteSelector(MapStateProvider mapProvider) {
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
              selMins > 60 ? '${selMins ~/ 60} giờ ${selMins % 60} phút' : '$selMins phút',
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
                    if (!sel || index == mapProvider.selectedRouteIndex) return;
                    mapProvider.selectRoute(index);
                    await mapProvider.drawMultipleRoutesPreview();
                    Position? cur;
                    try { cur = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 3)); }
                    catch (_) { cur = await Geolocator.getLastKnownPosition(); }
                    await _loadRouteDetails(
                      mapProvider.availableRoutes,
                      index,
                      mapbox.Position(cur?.longitude ?? 109.1967, cur?.latitude ?? 12.2388),
                    );
                  },
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapStateProvider>();

    return Stack(
      children: [
        if (!mapProvider.isNavigating)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: RoutingSearchBar(
              onDestinationSelected: _handleDestinationSelected,
              onClear: () async {
                await context.read<MapStateProvider>().clearAll();
                mapProvider.clearRoutes();
                setState(() {
                  _previewDestPos = null;
                  _polylineData = [];
                });
              },
            ),
          ),

        if (_previewDestPos != null && mapProvider.availableRoutes.isEmpty && !mapProvider.isNavigating && !_isLoading)
          _BottomCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        mapProvider.previewDestName ?? 'Điểm đến',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _getDirections,
                        icon: const Icon(Icons.directions, color: Colors.white, size: 18),
                        label: const Text('Đường đi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[700],
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _startRouting,
                        icon: const Icon(Icons.two_wheeler, color: Colors.white, size: 18),
                        label: const Text('Bắt đầu đi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        if (mapProvider.availableRoutes.isNotEmpty && !_isLoading && !mapProvider.isNavigating)
          _BottomCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRouteSelector(mapProvider),
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
                          if (pos == null) { _showSnackbar('Chưa lấy được vị trí GPS'); return; }
                          final roomId = _effectiveRoomId;
                          if (roomId.isEmpty) return;
                          final reported = await RiskReportSheet.show(
                            context,
                            roomId: roomId,
                            lat: pos.lat.toDouble(),
                            lng: pos.lng.toDouble(),
                          );
                          if (reported && mounted) _showSnackbar('Đã báo cáo sự cố thành công!');
                        },
                        child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'stop_nav_fab',
                        onPressed: () async {
                          _riskRefreshTimer?.cancel();
                          _stopNavGpsStream();
                          await context.read<MapStateProvider>().clearAll();
                          mapProvider.clearRoutes();
                          setState(() {
                            _previewDestPos = null;
                            _polylineData = [];
                          });
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

                    final roomId = _effectiveRoomId;
                    final result = await GeminiAiApi.analyzeCommand(
                      spokenText,
                      roomId: roomId,
                      currentLat: currentPos?.latitude,
                      currentLng: currentPos?.longitude,
                    );

                    if (result == null) { _showSnackbar('Không kết nối được AI'); return; }
                    if (!mounted) return;

                    await VoiceActionDispatcher(
                      context: context,
                      isInGroup: widget.roomId?.isNotEmpty == true,
                      roomId: roomId,
                      currentLat: currentPos?.latitude,
                      currentLng: currentPos?.longitude,
                      currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
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

class _BottomCard extends StatelessWidget {
  final Widget child;
  const _BottomCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: child,
      ),
    );
  }
}