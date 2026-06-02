import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../../core/utils/marker_builder.dart';
import '../../../core/utils/marker_offset.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../data/models/warning_marker.dart';
import '../../../core/services/location_service.dart';

class MapStateProvider extends ChangeNotifier {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _pointManager;
  mapbox.PolylineAnnotationManager? _polylineManager;
  StreamSubscription<CompassEvent>? _compassSub;

  bool get isMapReady => _mapboxMap != null && _pointManager != null && _polylineManager != null;

  List<dynamic> availableRoutes = [];
  int selectedRouteIndex = 0;
  bool isNavigating = false;
  bool _isFollowing = false;
  bool get isFollowing => _isFollowing;
  double? _lastBearing;
  double get lastBearing => _lastBearing ?? 0.0;
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
    notifyListeners();
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

  final List<mapbox.PointAnnotation> _memberMarkers = [];
  final List<mapbox.PointAnnotation> _destMarkers = [];
  final List<mapbox.PointAnnotation> _weatherMarkers = [];
  final List<mapbox.PointAnnotation> _riskMarkers = [];

  List<WarningMarker> weatherWarnings = [];
  mapbox.Position? _destinationPosition;

  Future<void> onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _pointManager = await mapboxMap.annotations.createPointAnnotationManager();
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
      // Khi đứng yên (không nav): xoay map theo la bàn điện thoại
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
      final position = await LocationService().getCurrentPosition();
      if (position == null) return;
      _mapboxMap?.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(position.longitude, position.latitude),
          ),
          zoom: 15.0,
          bearing: isNavigating ? _lastBearing : null,
          pitch: isNavigating ? 45.0 : 0.0,
        ),
        mapbox.MapAnimationOptions(duration: 800),
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

  Future<void> drawDestinationMarker(mapbox.Position dest, String name) async {
    if (_pointManager == null) return;
    for (final m in _destMarkers) {
      try { await _pointManager!.delete(m); } catch (_) {}
    }
    _destMarkers.clear();

    _destinationPosition = dest;
    final image = await MarkerBuilder.buildDestinationBubble(label: name);
    final annotation = await _pointManager!.create(
      mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: dest),
        image: image,
        iconAnchor: mapbox.IconAnchor.BOTTOM,
      ),
    );
    _destMarkers.add(annotation);
    flyTo(dest, zoom: 13.0);
  }

  Future<void> drawMemberMarkers(
    Map<String, mapbox.Position> locations,
    Map<String, String> displayNames,
    Map<String, String> roles,
  ) async {
    if (_pointManager == null) return;
    for (final m in _memberMarkers) {
      try { await _pointManager!.delete(m); } catch (_) {}
    }
    _memberMarkers.clear();

    for (final entry in locations.entries) {
      final uid = entry.key;
      final pos = entry.value;
      final name = displayNames[uid] ?? uid.substring(0, 6);
      final role = roles[uid] ?? 'member';

      final image = await MarkerBuilder.buildMemberBubble(name: name, role: role);
      final annotation = await _pointManager!.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(coordinates: pos),
          image: image,
          iconAnchor: mapbox.IconAnchor.BOTTOM,
        ),
      );
      _memberMarkers.add(annotation);
    }
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
          lineColor: isSelected ? Colors.blue.value : Colors.grey.value,
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
    weatherWarnings = List.from(weatherList);

    final occupiedPositions = <mapbox.Position>[];
    if (_destinationPosition != null) occupiedPositions.add(_destinationPosition!);
    for (final m in _memberMarkers) { occupiedPositions.add(m.geometry.coordinates); }
    for (final m in _riskMarkers) { occupiedPositions.add(m.geometry.coordinates); }

    for (final w in weatherList) {
      final adjustedPos = MarkerOffsetHelper.adjustForOverlap(
        existingPositions: occupiedPositions,
        newLat: w.lat,
        newLng: w.lng,
      );
      final image = await MarkerBuilder.buildBubble(
        emoji: w.emoji,
        label: w.vi,
        color: w.color,
      );
      final annotation = await _pointManager!.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(coordinates: adjustedPos),
          image: image,
          iconAnchor: mapbox.IconAnchor.BOTTOM,
        ),
      );
      _weatherMarkers.add(annotation);
      occupiedPositions.add(adjustedPos);
    }
  }

  Future<void> drawRiskMarkers(List<WarningMarker> risks, Map<String, mapbox.Position> memberLocations) async {
    if (_pointManager == null) return;
    for (final m in _riskMarkers) {
      try { await _pointManager!.delete(m); } catch (_) {}
    }
    _riskMarkers.clear();

    final occupiedPositions = <mapbox.Position>[
      ...memberLocations.values,
      if (_destinationPosition != null) _destinationPosition!,
      ..._weatherMarkers.map((m) => m.geometry.coordinates),
    ];

    for (final risk in risks) {
      final adjustedPos = MarkerOffsetHelper.adjustForOverlap(
        existingPositions: occupiedPositions,
        newLat: risk.lat,
        newLng: risk.lng,
      );
      final image = await MarkerBuilder.buildBubble(
        emoji: risk.emoji,
        label: risk.vi,
        color: risk.color,
      );
      final annotation = await _pointManager!.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(coordinates: adjustedPos),
          image: image,
          iconAnchor: mapbox.IconAnchor.BOTTOM,
        ),
      );
      _riskMarkers.add(annotation);
      occupiedPositions.add(adjustedPos);
    }
  }

  void fitBoundsToPositions(List<mapbox.Position> positions) {
    if (_mapboxMap == null || positions.isEmpty) return;
    if (positions.length == 1) { flyTo(positions.first, zoom: 14.0); return; }

    final lats = positions.map((p) => p.lat.toDouble());
    final lngs = positions.map((p) => p.lng.toDouble());
    final centerLat = (lats.reduce(min) + lats.reduce(max)) / 2;
    final centerLng = (lngs.reduce(min) + lngs.reduce(max)) / 2;
    final maxSpan = max(lats.reduce(max) - lats.reduce(min), lngs.reduce(max) - lngs.reduce(min));

    double zoom = 14.0;
    if (maxSpan > 0.1) zoom = 10.0;
    else if (maxSpan > 0.05) zoom = 11.5;
    else if (maxSpan > 0.01) zoom = 13.0;

    flyTo(mapbox.Position(centerLng, centerLat), zoom: zoom);
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    super.dispose();
  }

  Future<void> clearAll() async {
    _fullRouteCoords = [];
    _lastTrimPos = null;
    isOffRoute = false;
    _isFollowing = false;
    weatherWarnings = [];
    if (_pointManager != null) {
      await _pointManager!.deleteAll();
      _memberMarkers.clear();
      _destMarkers.clear();
      _weatherMarkers.clear();
      _riskMarkers.clear();
      _destinationPosition = null;
    }
    if (_polylineManager != null) {
      await _polylineManager!.deleteAll();
    }
    notifyListeners();
  }

  void clearRoutesData() {
    availableRoutes = [];
    selectedRouteIndex = 0;
    notifyListeners();
  }
}
