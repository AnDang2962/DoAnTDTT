import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Wrapper dịch vụ vị trí dùng trong project.
///
/// Mở rộng API để tương thích với `MembersProvider`:
/// - `requestLocationPermission()` để xin quyền (trả về enum đơn giản)
/// - `getCurrentPosition()` giữ nguyên hành vi trước đó
/// - `startTracking()` / `positionStream` để theo dõi vị trí theo `distanceFilter`
/// - `dispose()` để giải phóng tài nguyên
enum LocationPermissionStatus { granted, denied, restricted, prompt }

class LocationService {
  StreamController<Position>? _positionController;
  StreamSubscription<Position>? _positionSubscription;

  /// Stream phát các Position khi `startTracking()` được gọi.
  Stream<Position> get positionStream =>
      _positionController?.stream ?? Stream<Position>.empty();

  /// Yêu cầu quyền định vị và trả về trạng thái đơn giản.
  Future<LocationPermissionStatus> requestLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionStatus.prompt;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return LocationPermissionStatus.denied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionStatus.restricted;
    }
    return LocationPermissionStatus.granted;
  }

  /// Lấy vị trí hiện tại (giữ tương thích với phiên bản trước).
  Future<Position?> getCurrentPosition() async {
    try {
      final permissionStatus = await requestLocationPermission();
      if (permissionStatus != LocationPermissionStatus.granted) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  /// Bắt đầu theo dõi vị trí với tham số `distanceFilter` (mét).
  void startTracking({int distanceFilter = 50}) {
    _positionController ??= StreamController<Position>.broadcast();
    _positionSubscription?.cancel();

    final settings = LocationSettings(distanceFilter: distanceFilter);
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
          (position) {
            _positionController?.add(position);
          },
          onError: (error) {
            _positionController?.addError(error);
          },
        );
  }

  /// Giải phóng tài nguyên
  void dispose() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _positionController?.close();
    _positionController = null;
  }
}
