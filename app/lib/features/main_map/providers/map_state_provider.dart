import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../../core/utils/marker_builder.dart';
import '../../../core/utils/marker_offset.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../core/utils/badge_helper.dart';
import '../../../data/models/warning_marker.dart';

class MapStateProvider extends ChangeNotifier {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _pointManager;
  mapbox.PolylineAnnotationManager? _polylineManager;
  mapbox.Cancelable? _markerTapSub;
  StreamSubscription<CompassEvent>? _compassSub;

  bool get isMapReady => _mapboxMap != null && _pointManager != null && _polylineManager != null;

  bool _groupModeActive = false;
  bool get isGroupModeActive => _groupModeActive;
  void setGroupMode(bool active) {
    _groupModeActive = active;
  }

  void Function(mapbox.Position)? _mapTapHandler;

  void setMapTapHandler(void Function(mapbox.Position)? handler) {
    _mapTapHandler = handler;
  }

  void notifyMapTap(mapbox.Position pos) {
    _mapTapHandler?.call(pos);
  }

  List<dynamic> availableRoutes = [];
  int selectedRouteIndex = 0;
  bool isNavigating = false;
  bool _isFollowing = false;
  bool get isFollowing => _isFollowing;
  double? _lastBearing;
  String? previewDestName;

  void setRoutesData(List<dynamic> routes, String destName) {
    availableRoutes = routes;
    selectedRouteIndex = 0;
    isNavigating = false;
    previewDestName = destName;
    notifyListeners();
  }

  void selectRoute(int index) {
    selectedRouteIndex = index;
    notifyListeners();
  }

  void startNavigating() {
    isNavigating = true;
    _isFollowing = true;
    _mapboxMap?.location.updateSettings(
      mapbox.LocationComponentSettings(enabled: false),
    );
    notifyListeners();
  }

  Future<void> setNavArrow(mapbox.Position pos) async {
    if (_pointManager == null) return;
    _navArrowImage ??= await MarkerBuilder.buildNavigationArrow();
    if (_navArrow != null) {
      _navArrow!.geometry = mapbox.Point(coordinates: pos);
      try { await _pointManager!.update(_navArrow!); } catch (_) {}
    } else {
      _navArrow = await _pointManager!.create(mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: pos),
        image: _navArrowImage,
        iconAnchor: mapbox.IconAnchor.CENTER,
        iconRotate: 0,
      ));
    }
  }

  void resetNorth() {
    _lastBearing = 0.0;
    _mapboxMap?.easeTo(
      mapbox.CameraOptions(bearing: 0.0, pitch: 0.0),
      mapbox.MapAnimationOptions(duration: 500),
    );
    notifyListeners();
  }

  void setFollowing(bool value) {
    if (_isFollowing == value) return;
    _isFollowing = value;
    notifyListeners();
  }

  void clearRoutes() {
    availableRoutes = [];
    isNavigating = false;
    _isFollowing = false;
    previewDestName = null;
    notifyListeners();
  }

  List<mapbox.Position> _fullRouteCoords = [];
  mapbox.Position? _lastTrimPos;
  bool isOffRoute = false;

  double _initialDistanceKm = 0.0;
  int _initialDurationMins = 0;
  double remainingDistanceKm = 0.0;
  int remainingDurationMins = 0;
  double get initialDistanceKm => _initialDistanceKm;

  void setRouteStats(double distanceKm, int durationMins) {
    _initialDistanceKm = distanceKm;
    _initialDurationMins = durationMins;
    remainingDistanceKm = distanceKm;
    remainingDurationMins = durationMins;
  }

  void setRouteStatsFromCoords(List<mapbox.Position> coords) {
    double totalDistM = 0;
    for (int i = 0; i < coords.length - 1; i++) {
      totalDistM += calculateDistanceMeters(
        startLat: coords[i].lat.toDouble(),
        startLng: coords[i].lng.toDouble(),
        endLat: coords[i + 1].lat.toDouble(),
        endLng: coords[i + 1].lng.toDouble(),
      );
    }
    final km = totalDistM / 1000.0;
    setRouteStats(km, (km / 40.0 * 60.0).round());
  }

  void setFullRoute(List<mapbox.Position> coords) {
    _fullRouteCoords = List.from(coords);
    _lastTrimPos = null;
    isOffRoute = false;
  }

  // Debounce 50m để tránh redraw quá nhiều.
  Future<void> trimRouteToProgress(mapbox.Position currentPos) async {
    if (_polylineManager == null || _fullRouteCoords.length < 2) return;

    if (_lastTrimPos != null) {
      final movedM = calculateDistanceMeters(
        startLat: _lastTrimPos!.lat.toDouble(),
        startLng: _lastTrimPos!.lng.toDouble(),
        endLat: currentPos.lat.toDouble(),
        endLng: currentPos.lng.toDouble(),
      );
      if (movedM < 50) return;
    }
    _lastTrimPos = currentPos;

    double minDist = double.infinity;
    int bestIdx = 0;
    for (int i = 0; i < _fullRouteCoords.length; i++) {
      final d = calculateDistanceMeters(
        startLat: currentPos.lat.toDouble(),
        startLng: currentPos.lng.toDouble(),
        endLat: _fullRouteCoords[i].lat.toDouble(),
        endLng: _fullRouteCoords[i].lng.toDouble(),
      );
      if (d < minDist) { minDist = d; bestIdx = i; }
    }

    // 80m threshold cho phép lệch nhỏ khi đi sát lề đường.
    final newOffRoute = minDist > 80;
    if (newOffRoute != isOffRoute) {
      isOffRoute = newOffRoute;
      notifyListeners();
    }
    if (isOffRoute) return;

    final passed = [..._fullRouteCoords.sublist(0, bestIdx + 1), currentPos];
    final remaining = [currentPos, ..._fullRouteCoords.sublist(bestIdx + 1)];
    if (remaining.length < 2) return;

    // Tính lại km + thời gian còn lại
    double remDistM = 0.0;
    for (int i = 0; i < remaining.length - 1; i++) {
      remDistM += calculateDistanceMeters(
        startLat: remaining[i].lat.toDouble(),
        startLng: remaining[i].lng.toDouble(),
        endLat: remaining[i + 1].lat.toDouble(),
        endLng: remaining[i + 1].lng.toDouble(),
      );
    }
    final remKm = remDistM / 1000.0;
    final ratio = _initialDistanceKm > 0 ? remKm / _initialDistanceKm : 0.0;
    remainingDistanceKm = remKm;
    remainingDurationMins = (ratio * _initialDurationMins).round();

    await _polylineManager!.deleteAll();

    if (passed.length >= 2) {
      await _polylineManager!.create(mapbox.PolylineAnnotationOptions(
        geometry: mapbox.LineString(coordinates: passed),
        lineColor: 0xFFBDBDBD,
        lineWidth: 4.0,
        lineOpacity: 0.6,
      ));
    }

    await _polylineManager!.create(mapbox.PolylineAnnotationOptions(
      geometry: mapbox.LineString(coordinates: remaining),
      lineColor: 0xFF1F4E79,
      lineWidth: 6.0,
      lineOpacity: 1.0,
    ));
  }

  final Map<String, mapbox.PointAnnotation> _memberMarkerMap = {};
  Map<String, String> _lastMemberRoles = {};
  Map<String, String> _lastMemberPhotoUrls = {};
  final Map<String, ui.Image> _cachedAvatarImages = {};

  mapbox.PointAnnotation? _navArrow;
  Uint8List? _navArrowImage;

  final List<mapbox.PointAnnotation> _destMarkers = [];
  final List<mapbox.PointAnnotation> _weatherMarkers = [];
  final List<mapbox.PointAnnotation> _riskMarkers = [];
  final Map<String, WarningMarker> _weatherMarkerData = {};
  final Map<String, WarningMarker> _riskMarkerData = {};
  Function(WarningMarker)? _markerTapHandler;

  void setMarkerTapHandler(Function(WarningMarker)? handler) {
    _markerTapHandler = handler;
  }

  List<WarningMarker> weatherWarnings = [];
  mapbox.Position? _destinationPosition;

  Future<void> onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _pointManager = await mapboxMap.annotations.createPointAnnotationManager();
    _markerTapSub = _pointManager!.tapEvents(onTap: (annotation) {
      final marker = _weatherMarkerData[annotation.id] ?? _riskMarkerData[annotation.id];
      if (marker != null) _markerTapHandler?.call(marker);
    });
    _polylineManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    await _mapboxMap?.location.updateSettings(
      mapbox.LocationComponentSettings(enabled: true, pulsingEnabled: true),
    );
    _startCompassTracking();
    flyToCurrentLocation();
    notifyListeners();
  }

  void _startCompassTracking() {
    _compassSub?.cancel();
    _compassSub = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (heading == null || !_isFollowing || isNavigating) return;
      _lastBearing = heading;
      _mapboxMap?.easeTo(
        mapbox.CameraOptions(bearing: heading),
        mapbox.MapAnimationOptions(duration: 100),
      );
    });
  }

  Future<void> flyToCurrentLocation() async {
    _isFollowing = true;
    notifyListeners();
    try {
      // Dùng lastKnownPosition trước — instant, không cần request GPS mới
      Position? pos = await Geolocator.getLastKnownPosition();

      // Nếu không có cache, lấy fresh với timeout ngắn để tránh treo
      if (pos == null) {
        try {
          pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 4),
          );
        } catch (_) {
          return;
        }
      }

      _mapboxMap?.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(pos.longitude, pos.latitude),
          ),
          zoom: 15.0,
          bearing: isNavigating ? _lastBearing : null,
          pitch: isNavigating ? 45.0 : 0.0,
        ),
        mapbox.MapAnimationOptions(duration: 600),
      );
    } catch (e) {
      debugPrint('[MapStateProvider] flyToCurrentLocation error: $e');
    }
  }

  void flyTo(mapbox.Position position, {double zoom = 14.0}) {
    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: position),
        zoom: zoom,
      ),
      mapbox.MapAnimationOptions(duration: 800),
    );
  }

  void easeTo(mapbox.Position position, {double zoom = 15.0, double? bearing}) {
    if (bearing != null) _lastBearing = bearing;
    _mapboxMap?.easeTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: position),
        zoom: zoom,
        bearing: bearing,
        pitch: isNavigating ? 45.0 : 0.0,
      ),
      mapbox.MapAnimationOptions(duration: 300),
    );
  }

  Future<void> drawRoutePolyline(List<mapbox.Position> coords) async {
    if (_polylineManager == null) return;
    await _polylineManager!.deleteAll();
    await _polylineManager!.create(mapbox.PolylineAnnotationOptions(
      geometry: mapbox.LineString(coordinates: coords),
      lineColor: 0xFF1F4E79,
      lineWidth: 6.0,
    ));
  }

  Future<void> drawDestinationMarker(mapbox.Position dest, String name, {bool flyToMarker = true}) async {
    if (_pointManager == null) return;
    for (final m in _destMarkers) {
      try { await _pointManager!.delete(m); } catch (_) {}
    }
    _destMarkers.clear();

    _destinationPosition = dest;
    previewDestName = name;
    final image = await MarkerBuilder.buildDestinationPin();
    final annotation = await _pointManager!.create(
      mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: dest),
        image: image,
        iconAnchor: mapbox.IconAnchor.BOTTOM,
      ),
    );
    _destMarkers.add(annotation);
    if (flyToMarker) flyTo(dest, zoom: 13.0);
  }

  Future<ui.Image?> _loadAvatar(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final codec = await ui.instantiateImageCodec(res.bodyBytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<void> removeMemberMarker(String uid) async {
    if (!_memberMarkerMap.containsKey(uid)) return;
    try { await _pointManager!.delete(_memberMarkerMap[uid]!); } catch (_) {}
    _memberMarkerMap.remove(uid);
  }

  Future<void> drawMemberMarkers(
    Map<String, mapbox.Position> locations,
    Map<String, String> roles, {
    String? skipUid,
    Map<String, String> photoUrls = const {},
  }) async {
    if (_pointManager == null) return;

    final toRemove = _memberMarkerMap.keys
        .where((uid) => !locations.containsKey(uid) || uid == skipUid)
        .toList();
    for (final uid in toRemove) {
      try { await _pointManager!.delete(_memberMarkerMap[uid]!); } catch (_) {}
      _memberMarkerMap.remove(uid);
    }

    for (final entry in locations.entries) {
      final uid = entry.key;
      if (uid == skipUid) continue;
      final pos = entry.value;
      final role = roles[uid] ?? 'member';
      final photoUrl = photoUrls[uid] ?? '';

      // Load/update cached avatar khi photoUrl thay đổi
      if (photoUrl.isNotEmpty && _lastMemberPhotoUrls[uid] != photoUrl) {
        final loaded = await _loadAvatar(photoUrl);
        if (loaded != null) _cachedAvatarImages[uid] = loaded;
      }

      final needsRebuild = _lastMemberRoles[uid] != role ||
          _lastMemberPhotoUrls[uid] != photoUrl;

      if (_memberMarkerMap.containsKey(uid) && !needsRebuild) {
        _memberMarkerMap[uid]!.geometry = mapbox.Point(coordinates: pos);
        try { await _pointManager!.update(_memberMarkerMap[uid]!); } catch (_) {}
      } else {
        if (_memberMarkerMap.containsKey(uid)) {
          try { await _pointManager!.delete(_memberMarkerMap[uid]!); } catch (_) {}
        }
        final image = await MarkerBuilder.buildMemberBubble(
          ringColor: BadgeHelper.roleRingColor(role),
          roleLabel: BadgeHelper.roleLabel(role),
          avatarImage: _cachedAvatarImages[uid],
        );
        _memberMarkerMap[uid] = await _pointManager!.create(mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(coordinates: pos),
          image: image,
          iconAnchor: mapbox.IconAnchor.BOTTOM,
        ));
      }
    }

    _lastMemberRoles = Map.from(roles);
    _lastMemberPhotoUrls = Map.from({
      for (final uid in locations.keys) uid: photoUrls[uid] ?? '',
    });
  }

  Future<void> drawMultipleRoutesPreview() async {
    if (_polylineManager == null || availableRoutes.isEmpty) return;
    await _polylineManager!.deleteAll();

    for (int i = 0; i < availableRoutes.length; i++) {
      final geometry = availableRoutes[i]['geometry']['coordinates'] as List;
      final points = geometry
          .map((c) => mapbox.Position(c[0].toDouble(), c[1].toDouble()))
          .toList();
      final isSelected = (i == selectedRouteIndex);
      await _polylineManager!.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(coordinates: points),
          lineColor: isSelected ? Colors.blue.toARGB32() : Colors.grey.toARGB32(),
          lineWidth: isSelected ? 6.0 : 4.0,
          lineOpacity: isSelected ? 1.0 : 0.5,
        ),
      );
    }
  }

  Future<void> drawWeatherMarkers(List<WarningMarker> weatherList) async {
    if (_pointManager == null) return;
    for (final m in _weatherMarkers) {
      try { await _pointManager!.delete(m); } catch (_) {}
    }
    _weatherMarkers.clear();
    _weatherMarkerData.clear();
    weatherWarnings = List.from(weatherList);

    final occupiedPositions = <mapbox.Position>[];
    if (_destinationPosition != null) occupiedPositions.add(_destinationPosition!);
    for (final m in _memberMarkerMap.values) { occupiedPositions.add(m.geometry.coordinates); }
    for (final m in _riskMarkers) { occupiedPositions.add(m.geometry.coordinates); }

    for (final w in weatherList) {
      final adjustedPos = MarkerOffsetHelper.adjustForOverlap(
        existingPositions: occupiedPositions,
        newLat: w.lat,
        newLng: w.lng,
      );
      final image = await MarkerBuilder.buildBadgeMarker(
        emoji: w.emoji,
        label: w.vi,
        ringColor: w.color,
      );
      final annotation = await _pointManager!.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(coordinates: adjustedPos),
          image: image,
          iconAnchor: mapbox.IconAnchor.BOTTOM,
        ),
      );
      _weatherMarkers.add(annotation);
      _weatherMarkerData[annotation.id] = w;
      occupiedPositions.add(adjustedPos);
    }
  }

  Future<void> drawRiskMarkers(List<WarningMarker> risks, Map<String, mapbox.Position> memberLocations) async {
    if (_pointManager == null) return;
    for (final m in _riskMarkers) {
      try { await _pointManager!.delete(m); } catch (_) {}
    }
    _riskMarkers.clear();
    _riskMarkerData.clear();

    final occupiedPositions = <mapbox.Position>[
      ...memberLocations.values,
      ?_destinationPosition,
      ..._weatherMarkers.map((m) => m.geometry.coordinates),
    ];

    for (final risk in risks) {
      final adjustedPos = MarkerOffsetHelper.adjustForOverlap(
        existingPositions: occupiedPositions,
        newLat: risk.lat,
        newLng: risk.lng,
      );
      final image = await MarkerBuilder.buildBadgeMarker(
        emoji: risk.emoji,
        label: risk.vi,
        ringColor: risk.color,
      );
      final annotation = await _pointManager!.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(coordinates: adjustedPos),
          image: image,
          iconAnchor: mapbox.IconAnchor.BOTTOM,
        ),
      );
      _riskMarkers.add(annotation);
      _riskMarkerData[annotation.id] = risk;
      occupiedPositions.add(adjustedPos);
    }
  }

  Future<void> fitBoundsToPositions(List<mapbox.Position> positions) async {
    if (_mapboxMap == null || positions.isEmpty) return;
    if (positions.length == 1) { flyTo(positions.first, zoom: 14.0); return; }

    final lats = positions.map((p) => p.lat.toDouble());
    final lngs = positions.map((p) => p.lng.toDouble());

    final bounds = mapbox.CoordinateBounds(
      southwest: mapbox.Point(coordinates: mapbox.Position(lngs.reduce(min), lats.reduce(min))),
      northeast: mapbox.Point(coordinates: mapbox.Position(lngs.reduce(max), lats.reduce(max))),
      infiniteBounds: false,
    );
    final cameraOpts = await _mapboxMap!.cameraForCoordinateBounds(
      bounds,
      mapbox.MbxEdgeInsets(top: 80, left: 40, bottom: 200, right: 40),
      null, null, null, null,
    );
    _mapboxMap!.flyTo(cameraOpts, mapbox.MapAnimationOptions(duration: 800));
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _markerTapSub?.cancel();
    super.dispose();
  }

  Future<void> clearAll({bool keepMemberMarkers = false}) async {
    _fullRouteCoords = [];
    _lastTrimPos = null;
    isOffRoute = false;
    isNavigating = false;
    _isFollowing = false;
    weatherWarnings = [];
    previewDestName = null;
    _initialDistanceKm = 0.0;
    _initialDurationMins = 0;
    remainingDistanceKm = 0.0;
    remainingDurationMins = 0;
    if (_pointManager != null) {
      if (!keepMemberMarkers) {
        await _pointManager!.deleteAll();
        _memberMarkerMap.clear();
        _lastMemberRoles.clear();
        _lastMemberPhotoUrls.clear();
        _cachedAvatarImages.clear();
      } else {
        if (_navArrow != null) try { await _pointManager!.delete(_navArrow!); } catch (_) {}
        for (final m in _destMarkers) { try { await _pointManager!.delete(m); } catch (_) {} }
        for (final m in _weatherMarkers) { try { await _pointManager!.delete(m); } catch (_) {} }
        for (final m in _riskMarkers) { try { await _pointManager!.delete(m); } catch (_) {} }
      }
      _destMarkers.clear();
      _weatherMarkers.clear();
      _riskMarkers.clear();
      _weatherMarkerData.clear();
      _riskMarkerData.clear();
      _destinationPosition = null;
    }
    _navArrow = null;
    _navArrowImage = null;
    if (_polylineManager != null) {
      await _polylineManager!.deleteAll();
    }
    await _mapboxMap?.location.updateSettings(
      mapbox.LocationComponentSettings(enabled: true, pulsingEnabled: true),
    );
    notifyListeners();
  }

  void clearRoutesData() {
    availableRoutes = [];
    selectedRouteIndex = 0;
    notifyListeners();
  }
}

