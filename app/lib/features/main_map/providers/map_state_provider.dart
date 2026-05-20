import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../../core/utils/marker_builder.dart';
import '../../../core/utils/marker_offset.dart';
import '../../../data/models/warning_marker.dart';
import 'package:geolocator/geolocator.dart';

/// Provider chịu trách nhiệm quản lý toàn bộ trạng thái và các điểm đánh dấu (Markers) trên Mapbox.
/// Việc tách rời logic vẽ bản đồ vào đây giúp giao diện (UI) gọn gàng hơn
/// và các tính năng khác (Radar, Tìm đường) có thể dùng chung một bản đồ duy nhất.
class MapStateProvider extends ChangeNotifier {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _pointManager;
  mapbox.PolylineAnnotationManager? _polylineManager;

  bool get isMapReady => _mapboxMap != null && _pointManager != null && _polylineManager != null;

  // Lưu trữ các Annotation để có thể xóa/cập nhật sau này
  final List<mapbox.PointAnnotation> _memberMarkers = [];
  final List<mapbox.PointAnnotation> _destMarkers = [];
  final List<mapbox.PointAnnotation> _weatherMarkers = [];
  final List<mapbox.PointAnnotation> _riskMarkers = [];

  // Vị trí của điểm đến
  mapbox.Position? _destinationPosition;

  /// Hàm được gọi khi Widget Bản đồ vừa load xong (onMapCreated)
  Future<void> onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    // Khởi tạo các công cụ vẽ Marker và Polyline của Mapbox 2.x
    _pointManager = await mapboxMap.annotations.createPointAnnotationManager();
    _polylineManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    
    // Bật hiển thị chấm xanh (Vị trí hiện tại của user trên máy)
    await _mapboxMap?.location.updateSettings(
      mapbox.LocationComponentSettings(enabled: true, pulsingEnabled: true),
    );
    
    // SỬA LỖI NHẢY VỀ QUẬN 1: Ngay khi map sẵn sàng, tự động bắt GPS và bay thẳng tới đó
    _flyToCurrentLocation();
    
    notifyListeners();
    debugPrint('[MapStateProvider] Bản đồ đã sẵn sàng!');
  }

  /// Tự động lấy GPS hiện tại và đưa camera về đó
  Future<void> _flyToCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      flyTo(mapbox.Position(position.longitude, position.latitude), zoom: 15.0);
    } catch (e) {
      debugPrint('[MapStateProvider] Lỗi lấy GPS tự động: $e');
    }
  }

  /// Bay camera tới một tọa độ nhất định
  void flyTo(mapbox.Position position, {double zoom = 14.0}) {
    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: position),
        zoom: zoom,
      ),
      mapbox.MapAnimationOptions(duration: 800),
    );
  }

  /// 1. VẼ ĐƯỜNG ĐI (POLYLINE)
  Future<void> drawRoutePolyline(List<mapbox.Position> coords) async {
    if (_polylineManager == null) return;

    // Xóa đường cũ
    await _polylineManager!.deleteAll();
    
    // Vẽ đường mới màu xanh dương đậm
    await _polylineManager!.create(mapbox.PolylineAnnotationOptions(
      geometry: mapbox.LineString(coordinates: coords),
      lineColor: 0xFF1F4E79, // Xanh RouteMate
      lineWidth: 6.0,
    ));
    debugPrint('[MapStateProvider] Đã vẽ lộ trình với ${coords.length} điểm.');
  }

  /// 2. VẼ ĐIỂM ĐẾN
  Future<void> drawDestinationMarker(mapbox.Position dest, String name) async {
    if (_pointManager == null) return;

    // Xóa điểm đến cũ
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

  /// 3. VẼ CÁC THÀNH VIÊN TRONG NHÓM (Dùng cho Group Radar)
  Future<void> drawMemberMarkers(
    Map<String, mapbox.Position> locations, 
    Map<String, String> displayNames, 
    Map<String, String> roles
  ) async {
    if (_pointManager == null) return;

    // Xóa marker cũ
    for (final m in _memberMarkers) {
      try { await _pointManager!.delete(m); } catch (_) {}
    }
    _memberMarkers.clear();

    // Vẽ marker mới cho từng người
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

  /// 4. VẼ CÁC CẢNH BÁO RỦI RO (Có thuật toán chống đè)
  Future<void> drawRiskMarkers(List<WarningMarker> risks, Map<String, mapbox.Position> memberLocations) async {
    if (_pointManager == null) return;

    for (final m in _riskMarkers) {
      try { await _pointManager!.delete(m); } catch (_) {}
    }
    _riskMarkers.clear();

    // Thu thập các vị trí ĐÃ BỊ CHIẾM (Để tránh vẽ đè lên nhau)
    final occupiedPositions = <mapbox.Position>[];
    
    // Tránh đè lên thành viên
    for (final memberPos in memberLocations.values) {
      occupiedPositions.add(memberPos);
    }
    // Tránh đè lên điểm đến
    if (_destinationPosition != null) {
      occupiedPositions.add(_destinationPosition!);
    }
    // Tránh đè lên thời tiết
    for (final m in _weatherMarkers) {
      occupiedPositions.add(m.geometry.coordinates);
    }

    // Bắt đầu vẽ cảnh báo
    for (final risk in risks) {
      // Gọi thuật toán tính toán vị trí mới (dời lên trên nếu bị đè)
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
      
      // Đưa vị trí vừa vẽ vào danh sách "Đã bị chiếm" để các marker sau tránh ra
      occupiedPositions.add(adjustedPos);
    }
  }
  
  /// Xóa sạch mọi thứ trên bản đồ (Khi người dùng hủy lộ trình)
  Future<void> clearAll() async {
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
}
