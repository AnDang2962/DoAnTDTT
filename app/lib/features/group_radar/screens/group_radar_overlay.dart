import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:cloud_functions/cloud_functions.dart';

import '../../../data/models/user_model.dart';
import '../../../data/models/warning_marker.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../data/repositories/warning_repository.dart';
import '../../main_map/providers/map_state_provider.dart';
import '../../map_routing/widgets/routing_search_bar.dart';
import '../../map_routing/services/weather_api.dart';
import '../../map_routing/widgets/risk_report_sheet.dart';
import '../widgets/voice_fab.dart';
import '../../../core/utils/route_utils.dart';
import '../../map_routing/services/gemini_ai_api.dart';
import '../../voice/services/voice_action_dispatcher.dart';

class GroupRadarOverlay extends StatefulWidget {
  final String roomId;
  final UserModel currentUser;
  final VoidCallback onLeaveRoom;

  const GroupRadarOverlay({
    super.key,
    required this.roomId,
    required this.currentUser,
    required this.onLeaveRoom,
  });

  @override
  State<GroupRadarOverlay> createState() => _GroupRadarOverlayState();
}

class _GroupRadarOverlayState extends State<GroupRadarOverlay> {
  final RoomRepository _roomRepo = RoomRepository();
  final WarningRepository _warningRepo = WarningRepository();

  StreamSubscription? _gpsSub;
  StreamSubscription? _roomDataSub;
  StreamSubscription? _memberLocationsSub;
  StreamSubscription? _warningsSub;
  Timer? _riskRefreshTimer;

  List<WarningMarker> _realtimeRisks = [];
  List<WarningMarker> _crossGroupRisks = [];

  mapbox.Position? _myLastPos;
  mapbox.Position? _lastDestPos;
  String? _lastDestName;

  Map<String, dynamic> _memberInfo = {};
  Map<String, mapbox.Position> _memberLocations = {};

  String? _loadedRouteKey;

  bool _isTooFar = false;
  List<Map<String, dynamic>> _gapDetails = [];
  List<Map<String, dynamic>> _offRouteWarnings = [];
  DateTime? _lastGapCheck;

  bool _isInfoExpanded = false;
  bool _isLoading = false;
  List<Map<String, double>> _polylineData = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MapStateProvider>().setGroupMode(true);
    });
    _startMyGpsTracker();
    _listenToFirebaseStreams();
  }

  void _startMyGpsTracker() {
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      _myLastPos = mapbox.Position(pos.longitude, pos.latitude);
      _roomRepo.updateUserLocation(
        widget.roomId,
        widget.currentUser.id,
        pos.latitude,
        pos.longitude,
      );
      _checkFormationDistance();
      if (mounted) {
        final mapProvider = context.read<MapStateProvider>();
        mapProvider.trimRouteToProgress(_myLastPos!);
        if (mapProvider.isNavigating && mapProvider.isFollowing) {
          mapProvider.easeTo(_myLastPos!, bearing: pos.heading >= 0 ? pos.heading : null);
        }
        if (mapProvider.isNavigating) {
          unawaited(mapProvider.setNavArrow(_myLastPos!));
        }
      }
    });
  }

  void _listenToFirebaseStreams() {
    _roomDataSub = _roomRepo.listenToRoomData(widget.roomId).listen((doc) async {
      if (!doc.exists) return;
      final data = doc.data()!;

      setState(() {
        _memberInfo = data['memberInfo'] as Map<String, dynamic>? ?? {};
      });

      final routeData = data['route'] as Map<String, dynamic>?;
      if (routeData != null && routeData['polyline'] != null) {
        final polyList = routeData['polyline'] as List;
        final coords = polyList
            .map((p) => mapbox.Position(
                  (p['lng'] as num).toDouble(),
                  (p['lat'] as num).toDouble(),
                ))
            .toList();

        // Tạo key từ điểm đầu + cuối để phát hiện route mới
        final routeKey = coords.isEmpty ? '' : '${coords.first.lng},${coords.first.lat}-${coords.last.lng},${coords.last.lat}';

        if (mounted) {
          final mapProvider = context.read<MapStateProvider>();
          mapProvider.setFullRoute(coords);
          await mapProvider.drawRoutePolyline(coords);
          mapProvider.startNavigating();
          final endName = routeData['endName']?.toString() ?? 'Đích đến';
          if (coords.isNotEmpty) {
            await mapProvider.drawDestinationMarker(coords.last, endName, flyToMarker: false);
          }
          mapProvider.flyToCurrentLocation();

          // Load risk + thời tiết khi route mới (member join sau hoặc leader đổi tuyến)
          if (routeKey != _loadedRouteKey) {
            _loadedRouteKey = routeKey;
            final polylineData = polyList
                .map<Map<String, double>>((p) => {
                      'lng': (p['lng'] as num).toDouble(),
                      'lat': (p['lat'] as num).toDouble(),
                    })
                .toList();
            _crossGroupRisks = await _warningRepo.getRiskLabelsNearRoute(
              polyline: polylineData,
            );
            _redrawAllRisks();
            _startCrossGroupRiskTimer(polylineData);
            await _loadWeatherAlongRoute(coords);
          }
        }
      }
    });

    _memberLocationsSub = _roomRepo.listenToRoomLocations(widget.roomId).listen((data) {
      final newLocations = <String, mapbox.Position>{};
      data.forEach((uid, info) {
        if (info is Map && info['lat'] != null && info['lng'] != null) {
          newLocations[uid] = mapbox.Position(
            (info['lng'] as num).toDouble(),
            (info['lat'] as num).toDouble(),
          );
        }
      });
      _memberLocations = newLocations;
      _updateMapMembers();
      _checkFormationDistance();
    });

    _warningsSub = _warningRepo.listenToRoomWarnings(widget.roomId).listen((warnings) {
      _realtimeRisks = warnings;
      _redrawAllRisks();
    });
  }

  void _redrawAllRisks() {
    if (!mounted) return;
    final merged = <String, WarningMarker>{};
    for (final r in _realtimeRisks) merged[r.id] = r;
    for (final r in _crossGroupRisks) merged[r.id] = r;
    context.read<MapStateProvider>().drawRiskMarkers(merged.values.toList(), _memberLocations);
  }

  void _updateMapMembers() {
    if (!mounted) return;
    final roles = <String, String>{};
    _memberInfo.forEach((uid, info) {
      if (info is Map) roles[uid] = info['role']?.toString() ?? 'member';
    });
    final mapProvider = context.read<MapStateProvider>();
    mapProvider.drawMemberMarkers(
      _memberLocations,
      roles,
      skipUid: mapProvider.isNavigating ? widget.currentUser.id : null,
    );
  }

  void _checkFormationDistance() {
    if (_memberLocations.isEmpty) return;
    final now = DateTime.now();
    if (_lastGapCheck != null && now.difference(_lastGapCheck!).inSeconds < 30) return;
    _lastGapCheck = now;
    _checkGroupGapFromBackend();
  }

  Future<void> _checkGroupGapFromBackend() async {
    if (!mounted) return;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('checkGroupGap');
      final result = await callable.call<Map<Object?, Object?>>({
        'roomId': widget.roomId,
        'thresholdKm': 2.0,
      });

      final data = Map<String, dynamic>.from(result.data);
      final gaps = (data['gaps'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      final offRoute = (data['offRouteWarnings'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];

      if (!mounted) return;
      setState(() {
        _isTooFar = gaps.isNotEmpty || offRoute.isNotEmpty;
        _gapDetails = gaps;
        _offRouteWarnings = offRoute;
      });
    } catch (e) {
      debugPrint('[GroupGap] Lỗi checkGroupGap: $e');
    }
  }

  void _showSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _handleDestinationSelected(mapbox.Position destPos, String placeName) async {
    if (widget.currentUser.role != UserRole.leader) {
      _showSnackbar('Chỉ Leader mới có quyền tạo lộ trình!'); return;
    }
    if (_myLastPos == null) {
      _showSnackbar('Chưa lấy được GPS hiện tại của bạn!'); return;
    }
    final mapProvider = context.read<MapStateProvider>();
    await mapProvider.clearAll();
    mapProvider.clearRoutes();
    await mapProvider.drawDestinationMarker(destPos, placeName);
    setState(() { _lastDestPos = destPos; _lastDestName = placeName; _polylineData = []; });
  }

  Future<void> _getDirections() async {
    if (_lastDestPos == null || _myLastPos == null) return;
    setState(() => _isLoading = true);
    try {
      final routes = await RouteUtils.getMultipleMapboxRoutes(_myLastPos!, _lastDestPos!);
      if (routes.isEmpty) { _showSnackbar('Không tìm thấy đường đi tới điểm này!'); return; }
      final mapProvider = context.read<MapStateProvider>();
      mapProvider.setRoutesData(routes, _lastDestName ?? 'Điểm đến');
      await mapProvider.drawMultipleRoutesPreview();
      await _loadRouteDetails(routes, mapProvider.selectedRouteIndex);
    } catch (e) {
      _showSnackbar('Có lỗi khi tìm đường: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Load weather + risk + polylineData cho tuyến cụ thể — gọi lại khi đổi tuyến.
  Future<void> _loadRouteDetails(List<dynamic> routes, int routeIndex) async {
    if (_myLastPos == null) return;
    final mapProvider = context.read<MapStateProvider>();
    final geometry = routes[routeIndex]['geometry']['coordinates'] as List;
    final positions = geometry
        .map((c) => mapbox.Position((c[0] as num).toDouble(), (c[1] as num).toDouble()))
        .toList();

    mapProvider.fitBoundsToPositions([_myLastPos!, ...positions]);

    _polylineData = RouteUtils.downsamplePolyline(
      geometry.map<Map<String, double>>((c) => {
        'lng': (c[0] as num).toDouble(),
        'lat': (c[1] as num).toDouble(),
      }).toList(),
    );

    await mapProvider.drawWeatherMarkers([]);
    _crossGroupRisks = [];

    await _loadWeatherAlongRoute(positions);

    _crossGroupRisks = await _warningRepo.getRiskLabelsNearRoute(polyline: _polylineData);
    if (_crossGroupRisks.isNotEmpty && mounted) {
      _redrawAllRisks();
      _showSnackbar('Phát hiện ${_crossGroupRisks.length} cảnh báo trên lộ trình!');
    }
  }

  Future<void> _loadWeatherAlongRoute(List<mapbox.Position> coords) async {
    if (coords.length < 2 || !mounted) return;

    final waypoints = RouteUtils.extractWaypointsEvery50Km(coords);
    final weatherWarnings = <WarningMarker>[];

    for (int i = 0; i < waypoints.length; i++) {
      final warning = await WeatherApi.checkWeatherRisk(
        waypoints[i].lat.toDouble(),
        waypoints[i].lng.toDouble(),
        progressKm: (i + 1) * 50.0,
      );
      if (warning != null) weatherWarnings.add(warning);
    }

    if (weatherWarnings.isNotEmpty && mounted) {
      final mapProvider = context.read<MapStateProvider>();
      await mapProvider.drawWeatherMarkers(weatherWarnings);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã thêm ${weatherWarnings.length} điểm thời tiết'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleVoiceResult(String text) async {
    if (_myLastPos == null) return;

    final result = await GeminiAiApi.analyzeCommand(
      text,
      roomId: widget.roomId,
      currentLat: _myLastPos!.lat.toDouble(),
      currentLng: _myLastPos!.lng.toDouble(),
    );

    if (result == null || !mounted) return;

    await VoiceActionDispatcher(
      context: context,
      isInGroup: true,
      roomId: widget.roomId,
      currentLat: _myLastPos!.lat.toDouble(),
      currentLng: _myLastPos!.lng.toDouble(),
      memberLocations: _memberLocations,
      memberInfo: _memberInfo,
      currentUserId: widget.currentUser.id,
      onNavigateTo: widget.currentUser.role == UserRole.leader
          ? (pos, name) async => _handleDestinationSelected(pos, name)
          : null,
      isTooFar: _isTooFar,
      gapDetails: _gapDetails,
      offRouteWarnings: _offRouteWarnings,
    ).dispatch(result);
  }

  Future<void> _handleRiskReport() async {
    if (widget.currentUser.role != UserRole.leader) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chỉ Leader mới có thể báo cáo sự cố')),
      );
      return;
    }
    if (_myLastPos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa lấy được vị trí GPS')),
      );
      return;
    }
    final reported = await RiskReportSheet.show(
      context,
      roomId: widget.roomId,
      lat: _myLastPos!.lat.toDouble(),
      lng: _myLastPos!.lng.toDouble(),
    );
    if (reported && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã báo cáo sự cố thành công!')),
      );
    }
  }

  void _startCrossGroupRiskTimer(List<Map<String, double>> polylineData) {
    _riskRefreshTimer?.cancel();
    _riskRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (!mounted) { _riskRefreshTimer?.cancel(); return; }
      final risks = await _warningRepo.getRiskLabelsNearRoute(polyline: polylineData);
      if (mounted) {
        _crossGroupRisks = risks;
        _redrawAllRisks();
      }
    });
  }

  Future<void> _startGroupNavigation(MapStateProvider mapProvider) async {
    if (mapProvider.availableRoutes.isEmpty) return;
    final chosenRoute = mapProvider.availableRoutes[mapProvider.selectedRouteIndex];
    final geometry = chosenRoute['geometry']['coordinates'] as List;
    final routeCoords = geometry
        .map((c) => mapbox.Position((c[0] as num).toDouble(), (c[1] as num).toDouble()))
        .toList();

    mapProvider.clearRoutesData();
    mapProvider.setFullRoute(routeCoords);
    await mapProvider.drawRoutePolyline(routeCoords);

    if (widget.roomId.isNotEmpty) {
      await _roomRepo.setRoomRoute(
        roomId: widget.roomId,
        polyline: _polylineData,
        startName: 'Vị trí hiện tại',
        endName: mapProvider.previewDestName ?? 'Điểm đến',
      );
    }

    if (_polylineData.isNotEmpty) _startCrossGroupRiskTimer(_polylineData);
    mapProvider.startNavigating();
    mapProvider.flyToCurrentLocation();
  }

  String _memberName(String uid) {
    final info = _memberInfo[uid];
    if (info is Map) return info['displayName']?.toString() ?? uid.substring(0, 6);
    return uid.substring(0, 6);
  }

  Widget _buildGapWarningText() {
    final lines = <String>['CẢNH BÁO ĐỨT ĐỘI HÌNH!'];
    for (final g in _gapDetails) {
      final name = _memberName(g['memberId']?.toString() ?? '');
      final km = (g['distanceKm'] as num?)?.toStringAsFixed(1) ?? '?';
      lines.add('• $name đang tụt hậu $km km');
    }
    for (final w in _offRouteWarnings) {
      final name = _memberName(w['memberId']?.toString() ?? '');
      lines.add('• $name đã lệch tuyến đường');
    }
    return Text(
      lines.join('\n'),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    );
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _roomDataSub?.cancel();
    _memberLocationsSub?.cancel();
    _warningsSub?.cancel();
    _riskRefreshTimer?.cancel();
    FirebaseDatabase.instance
        .ref('gps/${widget.roomId}/${widget.currentUser.id}')
        .remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapStateProvider>();
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: RoutingSearchBar(
              onDestinationSelected: _handleDestinationSelected,
              onClear: () => context.read<MapStateProvider>().clearAll(),
            ),
          ),

          Positioned(
            top: 90,
            left: 16,
            child: GestureDetector(
              onTap: () => setState(() => _isInfoExpanded = !_isInfoExpanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: _isInfoExpanded ? 240 : 150,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tag, color: Colors.blue, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Phòng: ${widget.roomId}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          _isInfoExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                    if (_isInfoExpanded) ...[
                      const Divider(height: 16),
                      Row(
                        children: [
                          Icon(
                            _isTooFar ? Icons.gpp_bad : Icons.verified_user,
                            color: _isTooFar ? Colors.red : Colors.green,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Đội hình: ${_isTooFar ? "Đứt đoàn" : "Ổn định"}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _isTooFar ? Colors.red : Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Thành viên (${_memberInfo.length}):',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: SingleChildScrollView(
                          child: Column(
                            children: _memberInfo.entries.map((entry) {
                              final info = entry.value as Map;
                              final name = info['displayName']?.toString() ?? 'Ẩn danh';
                              final role = info['role']?.toString() ?? 'member';
                              final roleColor = role == 'leader'
                                  ? Colors.blue
                                  : role == 'sweeper'
                                      ? Colors.green
                                      : Colors.orange;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.two_wheeler, size: 14, color: roleColor),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: roleColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        role.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: roleColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          if (_isTooFar)
            Positioned(
              top: 200,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Expanded(child: _buildGapWarningText()),
                  ],
                ),
              ),
            ),

          if (_lastDestPos != null && mapProvider.availableRoutes.isEmpty &&
              !mapProvider.isNavigating && !_isLoading &&
              widget.currentUser.role == UserRole.leader)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: _GroupBottomCard(
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
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await _getDirections();
                              if (!mounted || mapProvider.availableRoutes.isEmpty) return;
                              await _startGroupNavigation(mapProvider);
                            },
                            icon: const Icon(Icons.two_wheeler, color: Colors.white, size: 18),
                            label: const Text('Bắt đầu đi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          if (mapProvider.availableRoutes.isNotEmpty && !mapProvider.isNavigating &&
              widget.currentUser.role == UserRole.leader)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: _GroupBottomCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(
                          mapProvider.availableRoutes.length,
                          (index) => Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text('Tuyến ${index + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              selected: mapProvider.selectedRouteIndex == index,
                              selectedColor: Colors.blue.withValues(alpha: 0.3),
                              onSelected: (selected) async {
                                if (!selected || index == mapProvider.selectedRouteIndex) return;
                                mapProvider.selectRoute(index);
                                await mapProvider.drawMultipleRoutesPreview();
                                await _loadRouteDetails(mapProvider.availableRoutes, index);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _startGroupNavigation(mapProvider),
                      icon: const Icon(Icons.two_wheeler, color: Colors.white),
                      label: const Text('Bắt đầu đi cùng nhóm',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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

          if (mapProvider.isOffRoute && mapProvider.isNavigating)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 80, left: 16, right: 16),
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
                    if (widget.currentUser.role == UserRole.leader && _lastDestPos != null)
                      TextButton(
                        onPressed: () async {
                          final dest = _lastDestPos!;
                          final name = _lastDestName ?? 'Điểm đến';
                          await context.read<MapStateProvider>().clearAll();
                          context.read<MapStateProvider>().clearRoutes();
                          _handleDestinationSelected(dest, name);
                        },
                        child: const Text(
                          'Tính lại',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.redAccent.withValues(alpha: 0.4), blurRadius: 15, spreadRadius: 2),
                  ],
                ),
                child: VoiceFab(onVoiceResult: _handleVoiceResult),
              ),
            ),
          ),

          Positioned(
            bottom: 30,
            left: 20,
            child: FloatingActionButton(
              heroTag: 'back_fab',
              backgroundColor: Colors.white,
              onPressed: widget.onLeaveRoom,
              child: const Icon(Icons.arrow_back, color: Colors.black),
            ),
          ),

          Positioned(
            bottom: 30,
            left: 90,
            child: FloatingActionButton(
              heroTag: 'risk_fab',
              backgroundColor: Colors.orange[700],
              onPressed: _handleRiskReport,
              child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
            ),
          ),

          if (!mapProvider.isNavigating || !mapProvider.isFollowing)
            Positioned(
              bottom: 200,
              right: 16,
              child: GestureDetector(
                onTap: () => context.read<MapStateProvider>().flyToCurrentLocation(),
                child: Container(
                  width: 44,
                  height: 44,
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
        ],
      ),
    );
  }
}

class _GroupBottomCard extends StatelessWidget {
  final Widget child;
  const _GroupBottomCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: child,
    );
  }
}
