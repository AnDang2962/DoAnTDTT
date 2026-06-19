import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:route_mate_app/core/utils/route_utils.dart';
import 'package:route_mate_app/core/services/solo_room_service.dart';
import 'package:route_mate_app/features/main_map/providers/map_state_provider.dart';

import '../services/weather_api.dart';
import '../../../data/models/warning_marker.dart';
import '../../../core/services/tts_service.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../data/repositories/warning_repository.dart';

import '../widgets/routing_search_bar.dart';
import '../widgets/risk_report_sheet.dart';
import '../widgets/marker_detail_sheet.dart';
import '../widgets/waypoint_search_sheet.dart';
import '../services/gemini_ai_api.dart';
import '../services/geocoding_api.dart';
import '../../voice/services/voice_action_dispatcher.dart';
import '../../../core/providers/voice_command_provider.dart';

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
  DateTime? _navStartTime;

  final RoomRepository _roomRepo = RoomRepository();
  final WarningRepository _warningRepo = WarningRepository();
  StreamSubscription<List<WarningMarker>>? _riskSub;
  Timer? _riskRefreshTimer;
  StreamSubscription<Position>? _navGpsSub;

  List<WarningMarker> _realtimeRisks = [];
  List<WarningMarker> _crossGroupRisks = [];
  List<Map<String, double>> _polylineData = [];
  final Set<String> _announcedRiskIds = {};
  int _lastRiskCheckMs = 0;
  bool _arrivedNotified = false;

  List<RouteWaypoint> _waypoints = [];
  bool _addingWaypointByMap = false;

  void _redrawAllRisks() {
    if (!mounted) return;
    final mapProvider = context.read<MapStateProvider>();
    if (mapProvider.isGroupModeActive) return;
    if (_previewDestPos == null && !mapProvider.isNavigating) return;
    mapProvider.drawRiskMarkers(_crossGroupRisks, {});
  }

  VoiceCommandProvider? _voiceProv;
  int _lastVoiceVersion = 0;
  MapStateProvider? _mapProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapProvider = context.read<MapStateProvider>();
      _mapProvider!.addListener(_onSosTargetChanged);
      _startSoloRiskListener();
      _voiceProv = context.read<VoiceCommandProvider>();
      _voiceProv!.addListener(_onVoiceCommand);
      if (widget.isActive) {
        _mapProvider!.setMapTapHandler(_onMapTap);
        _mapProvider!.setMarkerTapHandler(_onMarkerTap);
        _mapProvider!.setRouteTapHandler(_onRouteTap);
      }
    });
  }

  @override
  void didUpdateWidget(RoutingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _mapProvider?.setMapTapHandler(widget.isActive ? _onMapTap : null);
      _mapProvider?.setMarkerTapHandler(widget.isActive ? _onMarkerTap : null);
      _mapProvider?.setRouteTapHandler(widget.isActive ? _onRouteTap : null);
    }
    if (!widget.isActive && oldWidget.isActive) {
      _stopNavGpsStream();
      _riskRefreshTimer?.cancel();
      _riskSub?.cancel();
      _riskSub = null;
      if (mounted) {
        final mapProvider = context.read<MapStateProvider>();
        if (mapProvider.isNavigating) {
          unawaited(mapProvider.clearAll());
          mapProvider.clearRoutes();
          setState(() {
            _previewDestPos = null;
            _waypoints = [];
            _addingWaypointByMap = false;
          });
        }
      }
    }
    if (widget.isActive && !oldWidget.isActive) {
      _startSoloRiskListener();
      final sosTarget = _mapProvider?.sosRoutingTarget;
      if (sosTarget != null) {
        _mapProvider?.clearSosRoutingTarget();
        unawaited(_handleDestinationSelected(sosTarget, 'Vị trí nạn nhân SOS'));
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
      final prevCount = _realtimeRisks.length;
      _realtimeRisks = risks;
      // Chỉ refresh near-route risks khi có risk mới xuất hiện
      if (risks.length > prevCount && _polylineData.isNotEmpty) {
        _warningRepo.getRiskLabelsNearRoute(polyline: _polylineData).then((nearby) {
          if (!mounted) return;
          _crossGroupRisks = nearby;
          _redrawAllRisks();
          _lastRiskCheckMs = 0;
          _checkNearbyRisks();
        });
      }
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
        _checkNearbyRisks();
        if (!_arrivedNotified && mapProvider.remainingDistanceKm < 0.3) {
          _arrivedNotified = true;
          final destName = mapProvider.previewDestName ?? 'Điểm đến';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('🎉 Bạn đã đến $destName!'),
            duration: const Duration(seconds: 5),
          ));
        }
      }
    });
  }

  void _checkNearbyRisks() {
    if (_myLastPos == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRiskCheckMs < 5000) return;
    _lastRiskCheckMs = now;

    final allRisks = _crossGroupRisks;
    final announcements = <String>[];
    for (final risk in allRisks) {
      if (_announcedRiskIds.contains(risk.id)) continue;
      final dist = Geolocator.distanceBetween(
        _myLastPos!.lat.toDouble(), _myLastPos!.lng.toDouble(),
        risk.lat, risk.lng,
      );
      if (dist <= 500) {
        _announcedRiskIds.add(risk.id);
        final distText = dist < 100 ? 'ngay phía trước' : 'phía trước ${dist.round()} mét';
        final note = risk.note.isNotEmpty ? ', ${risk.note}' : '';
        announcements.add('$distText có ${risk.vi}$note');
      }
    }
    if (announcements.isNotEmpty) {
      unawaited(TtsService().speak(announcements.join('. ')));
    }
  }

  ({String uid, String endName, double totalKm, double traveledKm, int elapsedMins, bool completed})? _captureNavSnapshot(MapStateProvider mapProvider) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _navStartTime == null) return null;
    final totalKm = mapProvider.initialDistanceKm;
    final remainingKm = mapProvider.remainingDistanceKm;
    final snapshot = (
      uid: uid,
      endName: mapProvider.previewDestName ?? 'Điểm đến',
      totalKm: totalKm,
      traveledKm: (totalKm - remainingKm).clamp(0.0, totalKm),
      elapsedMins: DateTime.now().difference(_navStartTime!).inMinutes,
      completed: remainingKm < 0.5,
    );
    _navStartTime = null;
    return snapshot;
  }

  Future<void> _saveTripFromSnapshot(({String uid, String endName, double totalKm, double traveledKm, int elapsedMins, bool completed}) s) async {
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      batch.set(db.collection('users').doc(s.uid).collection('trips').doc(), {
        'endName': s.endName,
        'distanceKm': s.totalKm,
        'traveledKm': s.traveledKm,
        'durationMins': s.elapsedMins,
        'date': FieldValue.serverTimestamp(),
        'completed': s.completed,
      });
      batch.set(db.collection('users').doc(s.uid), {
        'totalKm': FieldValue.increment(s.traveledKm),
        'totalTrips': FieldValue.increment(1),
      }, SetOptions(merge: true));
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('💾 Chuyến đi đã được lưu vào lịch sử'),
          duration: Duration(seconds: 3),
        ));
      }
    } catch (_) {}
  }

  void _stopNavGpsStream() {
    _navGpsSub?.cancel();
    _navGpsSub = null;
  }

  void _onMarkerTap(WarningMarker marker) {
    if (!mounted) return;
    MarkerDetailSheet.show(context, marker);
  }

  @override
  void dispose() {
    _voiceProv?.removeListener(_onVoiceCommand);
    _mapProvider?.removeListener(_onSosTargetChanged);
    _mapProvider?.setMapTapHandler(null);
    _mapProvider?.setMarkerTapHandler(null);
    _mapProvider?.setRouteTapHandler(null);
    _riskSub?.cancel();
    _riskRefreshTimer?.cancel();
    _navGpsSub?.cancel();
    super.dispose();
  }

  void _onMapTap(mapbox.Position pos) async {
    if (!mounted) return;
    final mapProvider = context.read<MapStateProvider>();
    if (mapProvider.isGroupModeActive || _isLoading) return;

    if (_addingWaypointByMap) {
      setState(() => _addingWaypointByMap = false);
      final name = await GeocodingApi.reverseGeocode(pos.lat.toDouble(), pos.lng.toDouble());
      if (!mounted) return;
      unawaited(_addWaypoint(pos, name));
      return;
    }

    if (mapProvider.isNavigating) return;
    if (mapProvider.availableRoutes.isNotEmpty) return;
    final name = await GeocodingApi.reverseGeocode(pos.lat.toDouble(), pos.lng.toDouble());
    if (!mounted) return;
    await _handleDestinationSelected(pos, name);
  }

  void _onRouteTap(int routeIndex) async {
    if (!mounted) return;
    final mapProvider = context.read<MapStateProvider>();
    if (routeIndex == mapProvider.selectedRouteIndex) return;
    mapProvider.selectRoute(routeIndex);
    await mapProvider.drawMultipleRoutesPreview();
    Position? cur;
    try { cur = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 3)); }
    catch (_) { cur = await Geolocator.getLastKnownPosition(); }
    await _loadRouteDetails(
      mapProvider.availableRoutes,
      routeIndex,
      mapbox.Position(cur?.longitude ?? 109.1967, cur?.latitude ?? 12.2388),
    );
  }

  void _onSosTargetChanged() {
    if (!mounted || !widget.isActive) return;
    final target = _mapProvider?.sosRoutingTarget;
    if (target == null) return;
    _mapProvider?.clearSosRoutingTarget();
    unawaited(_handleDestinationSelected(target, 'Vị trí nạn nhân SOS'));
  }

  void _onVoiceCommand() async {
    if (!mounted) return;
    // Nhường cho GroupRadarOverlay xử lý khi đang ở chế độ nhóm
    if (context.read<MapStateProvider>().isGroupModeActive) return;
    final prov = _voiceProv!;
    if (prov.version == _lastVoiceVersion) return;
    _lastVoiceVersion = prov.version;
    final spokenText = prov.lastCommand;
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

    final isNavigating = context.read<MapStateProvider>().isNavigating;
    final resultType = result['type']?.toString() ?? 'command';
    final resultAction = result['action']?.toString() ?? '';

    // Các lệnh chỉ có ý nghĩa khi đang định tuyến
    const navOnlyActions = {'check_weather'};
    final isNavOnly = resultType == 'risk' || navOnlyActions.contains(resultAction);

    if (!isNavigating && isNavOnly) {
      _showSnackbar('Bạn chưa bắt đầu định tuyến, không thể thực hiện tác vụ này');
      return;
    }

    await VoiceActionDispatcher(
      context: context,
      isInGroup: widget.roomId?.isNotEmpty == true,
      roomId: roomId,
      currentLat: currentPos?.latitude,
      currentLng: currentPos?.longitude,
      currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
      onNavigateTo: _handleDestinationSelected,
      onAddWaypoint: (pos, name) => unawaited(_addWaypoint(pos, name)),
    ).dispatch(result);
  }

  Future<void> _handleDestinationSelected(mapbox.Position destPos, String placeName) async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final mapProvider = context.read<MapStateProvider>();
      await mapProvider.clearAll(keepMemberMarkers: mapProvider.isGroupModeActive);
      mapProvider.clearRoutes();
      await mapProvider.drawDestinationMarker(destPos, placeName);
      if (_waypoints.isNotEmpty) {
        await mapProvider.drawWaypointMarkers(_waypoints.map((w) => w.pos).toList());
      }
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

      final routes = await RouteUtils.getMultipleMapboxRoutes(
        startPos,
        _previewDestPos!,
        viaWaypoints: _waypoints.map((w) => w.pos).toList(),
      );
      if (!mounted) return;
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
    if (!mounted) return;
    _redrawAllRisks();
    if (_crossGroupRisks.isNotEmpty) {
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

      final distKm = (chosenRoute['distance'] as num).toDouble() / 1000.0;
      final durMins = ((chosenRoute['duration'] as num).toDouble() / 60.0).round();
      mapProvider.setRouteStats(distKm, durMins);
      mapProvider.startNavigating();
      _arrivedNotified = false;
      _navStartTime = DateTime.now();
      _announcedRiskIds.clear();
      _lastRiskCheckMs = 0;
      _checkNearbyRisks();
      _startNavGpsStream();
      mapProvider.flyToCurrentLocation();
      if (mounted) {
        final destName = mapProvider.previewDestName ?? 'Điểm đến';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🗺️ Bắt đầu dẫn đường đến $destName'),
          duration: const Duration(seconds: 3),
        ));
      }
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

  void _showWaypointSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => WaypointSearchSheet(
        onSelected: (pos, name) {
          Navigator.pop(context);
          unawaited(_addWaypoint(pos, name));
        },
      ),
    );
  }

  Future<void> _addWaypoint(mapbox.Position pos, String name) async {
    final mapProvider = context.read<MapStateProvider>();
    final wasNavigating = mapProvider.isNavigating;
    setState(() => _waypoints.add(RouteWaypoint(pos: pos, name: name)));

    if (wasNavigating) {
      await _recalculateAndRestartNav();
    } else {
      if (mapProvider.availableRoutes.isNotEmpty || _polylineData.isNotEmpty) {
        final destName = mapProvider.previewDestName ?? 'Điểm đến';
        await mapProvider.clearAll();
        mapProvider.clearRoutes();
        setState(() => _polylineData = []);
        if (_previewDestPos != null) {
          await mapProvider.drawDestinationMarker(_previewDestPos!, destName, flyToMarker: false);
        }
      }
      await mapProvider.drawWaypointMarkers(_waypoints.map((w) => w.pos).toList());
      _showSnackbar('Đã thêm: $name');
    }
  }

  Future<void> _removeWaypoint(int index) async {
    final mapProvider = context.read<MapStateProvider>();
    final wasNavigating = mapProvider.isNavigating;
    setState(() => _waypoints.removeAt(index));

    if (wasNavigating) {
      await _recalculateAndRestartNav();
    } else {
      if (mapProvider.availableRoutes.isNotEmpty || _polylineData.isNotEmpty) {
        final destName = mapProvider.previewDestName ?? 'Điểm đến';
        await mapProvider.clearAll();
        mapProvider.clearRoutes();
        setState(() => _polylineData = []);
        if (_previewDestPos != null) {
          await mapProvider.drawDestinationMarker(_previewDestPos!, destName, flyToMarker: false);
        }
      }
      await mapProvider.drawWaypointMarkers(_waypoints.map((w) => w.pos).toList());
    }
  }

  void _moveWaypoint(int fromIndex, int toIndex) {
    setState(() {
      final item = _waypoints.removeAt(fromIndex);
      _waypoints.insert(toIndex, item);
    });
    final mapProvider = context.read<MapStateProvider>();
    if (mapProvider.availableRoutes.isNotEmpty) mapProvider.clearRoutesData();
    unawaited(mapProvider.drawWaypointMarkers(_waypoints.map((w) => w.pos).toList()));
  }

  Future<void> _recalculateAndRestartNav() async {
    if (_previewDestPos == null) return;
    final mapProvider = context.read<MapStateProvider>();
    final destName = mapProvider.previewDestName ?? 'Điểm đến';

    _stopNavGpsStream();
    _riskRefreshTimer?.cancel();
    _arrivedNotified = false;
    _announcedRiskIds.clear();
    _lastRiskCheckMs = 0;

    await mapProvider.clearAll();
    mapProvider.clearRoutes();
    setState(() => _polylineData = []);

    await mapProvider.drawDestinationMarker(_previewDestPos!, destName, flyToMarker: false);
    await mapProvider.drawWaypointMarkers(_waypoints.map((w) => w.pos).toList());

    await _getDirections();
    if (!mounted || mapProvider.availableRoutes.isEmpty) return;
    await _startRouting();
  }

  Widget _buildRouteInfo(MapStateProvider mapProvider) {
    final routes = mapProvider.availableRoutes;
    final selected = routes[mapProvider.selectedRouteIndex];
    final selKm = (selected['distance'] / 1000).toStringAsFixed(1);
    final selMins = (selected['duration'] / 60).round();
    final timeText = selMins > 60
        ? '${selMins ~/ 60} giờ ${selMins % 60} phút'
        : '$selMins phút';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.straighten, size: 16, color: Colors.blueAccent),
        const SizedBox(width: 4),
        Text('$selKm km', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
        const SizedBox(width: 16),
        const Icon(Icons.schedule, size: 16, color: Colors.blueAccent),
        const SizedBox(width: 4),
        Text(timeText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
        if (routes.length > 1) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Text(
              'T.${mapProvider.selectedRouteIndex + 1}/${routes.length}',
              style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapStateProvider>();

    final safePad = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        if (_addingWaypointByMap)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Material(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(25),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Nhấn bản đồ để chọn điểm dừng',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _addingWaypointByMap = false),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (!mapProvider.isNavigating)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: RoutingSearchBar(
              onDestinationSelected: _handleDestinationSelected,
              destinationName: _previewDestPos != null ? mapProvider.previewDestName : null,
              onClear: () async {
                await context.read<MapStateProvider>().clearAll();
                mapProvider.clearRoutes();
                setState(() {
                  _previewDestPos = null;
                  _polylineData = [];
                  _waypoints = [];
                  _addingWaypointByMap = false;
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
                if (_waypoints.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _waypoints.length,
                    itemBuilder: (_, i) => _WaypointTile(
                      key: ValueKey(i),
                      index: i,
                      name: _waypoints[i].name,
                      onDelete: () => unawaited(_removeWaypoint(i)),
                      onMoveUp: i > 0 ? () => _moveWaypoint(i, i - 1) : null,
                      onMoveDown: i < _waypoints.length - 1 ? () => _moveWaypoint(i, i + 1) : null,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showWaypointSearchSheet,
                        icon: const Icon(Icons.add_location_alt, size: 15),
                        label: const Text('Thêm điểm dừng', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          side: const BorderSide(color: Colors.blue),
                          foregroundColor: Colors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => setState(() => _addingWaypointByMap = true),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        side: const BorderSide(color: Colors.blue),
                        foregroundColor: Colors.blue,
                      ),
                      child: const Icon(Icons.touch_app, size: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                        label: const Text('Bắt đầu', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
                _buildRouteInfo(mapProvider),
                if (_waypoints.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _waypoints.length,
                    itemBuilder: (_, i) => _WaypointTile(
                      key: ValueKey(i),
                      index: i,
                      name: _waypoints[i].name,
                      onDelete: () => unawaited(_removeWaypoint(i)),
                      onMoveUp: i > 0 ? () => _moveWaypoint(i, i - 1) : null,
                      onMoveDown: i < _waypoints.length - 1 ? () => _moveWaypoint(i, i + 1) : null,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _showWaypointSearchSheet,
                  icon: const Icon(Icons.add_location_alt, size: 15),
                  label: const Text('Thêm điểm dừng', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    side: const BorderSide(color: Colors.blue),
                    foregroundColor: Colors.blue,
                    minimumSize: const Size(double.infinity, 0),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _startRouting,
                  icon: const Icon(Icons.two_wheeler, color: Colors.white),
                  label: const Text('Bắt đầu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
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
                          mapProvider.remainingDurationMins > 60
                              ? '${mapProvider.remainingDurationMins ~/ 60} giờ ${mapProvider.remainingDurationMins % 60} phút'
                              : '${mapProvider.remainingDurationMins} phút',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${mapProvider.remainingDistanceKm.toStringAsFixed(1)} km • Đi bằng xe máy',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        if (_waypoints.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${_waypoints.length} điểm dừng trên đường',
                              style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w500),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'add_wp_nav_fab',
                        onPressed: _showWaypointSearchSheet,
                        backgroundColor: Colors.blue,
                        child: const Icon(Icons.add_location_alt, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 6),
                      FloatingActionButton.small(
                        heroTag: 'stop_nav_fab',
                        onPressed: () async {
                          _riskRefreshTimer?.cancel();
                          final snapshot = _captureNavSnapshot(mapProvider);
                          _stopNavGpsStream();
                          await context.read<MapStateProvider>().clearAll();
                          mapProvider.clearRoutes();
                          setState(() {
                            _previewDestPos = null;
                            _polylineData = [];
                            _waypoints = [];
                            _addingWaypointByMap = false;
                          });
                          if (snapshot != null) unawaited(_saveTripFromSnapshot(snapshot));
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

        if (mapProvider.isNavigating)
          Positioned(
            top: 144 - safePad,
            right: 16,
            child: GestureDetector(
              onTap: () async {
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
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
              ),
            ),
          ),

        if (!mapProvider.isNavigating || !mapProvider.isFollowing)
          Positioned(
            top: mapProvider.isNavigating ? 194 - safePad : 144 - safePad,
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

      ],
    );
  }
}

class _WaypointTile extends StatelessWidget {
  final int index;
  final String name;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _WaypointTile({
    super.key,
    required this.index,
    required this.name,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: key,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 24, height: 24,
        decoration: const BoxDecoration(color: Color(0xFF1A73E8), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      title: Text(name, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onMoveUp,
            child: Icon(Icons.keyboard_arrow_up, size: 20, color: onMoveUp != null ? Colors.blue : Colors.grey[300]),
          ),
          GestureDetector(
            onTap: onMoveDown,
            child: Icon(Icons.keyboard_arrow_down, size: 20, color: onMoveDown != null ? Colors.blue : Colors.grey[300]),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.close, size: 16, color: Colors.red),
          ),
        ],
      ),
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