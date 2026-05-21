import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/utils/geo_utils.dart';
import '../../../../data/repositories/group_repository.dart';
import '../../../../core/services/location_service.dart';

/// Model để chứa thông tin của một thành viên (vị trí + vai trò)
class MemberInfo {
  final String id;
  final LatLng location;
  final String role;
  final int timestamp;

  MemberInfo({
    required this.id,
    required this.location,
    required this.role,
    required this.timestamp,
  });

  factory MemberInfo.fromGpsData(
    String id,
    LatLng location,
    String role,
    int timestamp,
  ) {
    return MemberInfo(
      id: id,
      location: location,
      role: role,
      timestamp: timestamp,
    );
  }
}

/// Model để chứa thông tin vòng tròn an toàn
class SafeCircle {
  final LatLng center;
  final double radiusMeters;

  SafeCircle({required this.center, required this.radiusMeters});
}

/// Model cảnh báo hệ thống
class RadarAlert {
  final bool isLeaderSweeperFar; // Khoảng cách Leader-Sweeper >= 150m
  final List<String> lostMembers; // Danh sách thành viên lạc
  final bool hasAlert; // Có cảnh báo nào không

  RadarAlert({required this.isLeaderSweeperFar, required this.lostMembers})
    : hasAlert = isLeaderSweeperFar || lostMembers.isNotEmpty;

  factory RadarAlert.empty() {
    return RadarAlert(isLeaderSweeperFar: false, lostMembers: []);
  }
}

/// MembersProvider: State Management sử dụng ChangeNotifier
class MembersProvider extends ChangeNotifier {
  // Dependencies
  final GroupRepository repository;
  final LocationService locationService;

  // Dữ liệu
  Map<String, MemberInfo> members = {};
  SafeCircle? safeCircle;
  RadarAlert alert = RadarAlert.empty();
  String leaderSweeperDistance = '';
  bool isLoading = false;

  // Tham số
  String? _currentRoomId;
  String? _currentUserId;
  String? _currentRole;

  // Subscription
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<GpsData>>? _gpsStreamSubscription;

  // Hằng số
  static const double DISCONNECTION_THRESHOLD = 150.0; // 150m

  MembersProvider({required this.repository, required this.locationService});

  /// Khởi động theo dõi phòng
  Future<void> initialize({
    required String roomId,
    required String userId,
    required String role,
  }) async {
    _currentRoomId = roomId;
    _currentUserId = userId;
    _currentRole = role;
    isLoading = true;
    notifyListeners();

    try {
      // Bước 1: Yêu cầu quyền định vị
      final permissionStatus = await locationService
          .requestLocationPermission();
      if (permissionStatus != LocationPermissionStatus.granted) {
        throw Exception('Quyền định vị bị từ chối');
      }

      // Bước 2: Lắng nghe stream GPS từ Repository
      _gpsStreamSubscription = repository
          .getGpsStream(roomId)
          .listen(
            (gpsList) {
              _updateMembers(gpsList);
              _evaluateDistance();
              notifyListeners();
            },
            onError: (error) {
              print('Lỗi lắng nghe GPS stream: $error');
            },
          );

      // Bước 3: Bắt đầu theo dõi vị trí thiết bị và đẩy lên Firebase
      locationService.startTracking(distanceFilter: 2); // Cập nhật mỗi 2m
      _positionSubscription = locationService.positionStream.listen((position) {
        _uploadCurrentPosition(lat: position.latitude, lng: position.longitude);
      });

      isLoading = false;
      notifyListeners();
    } catch (e) {
      print('Lỗi khởi động MembersProvider: $e');
      isLoading = false;
      notifyListeners();
    }
  }

  /// Cập nhật danh sách thành viên từ dữ liệu GPS
  void _updateMembers(List<GpsData> gpsList) {
    members.clear();
    for (final gpsData in gpsList) {
      members[gpsData.userId] = MemberInfo.fromGpsData(
        gpsData.userId,
        gpsData.location,
        gpsData.role,
        gpsData.timestamp,
      );
    }
  }

  /// Đẩy vị trí GPS hiện tại lên Firebase
  Future<void> _uploadCurrentPosition({
    required double lat,
    required double lng,
  }) async {
    if (_currentRoomId == null ||
        _currentUserId == null ||
        _currentRole == null) {
      return;
    }

    try {
      await repository.uploadGps(
        roomId: _currentRoomId!,
        userId: _currentUserId!,
        location: LatLng(lat, lng),
        role: _currentRole!,
      );
    } catch (e) {
      print('Lỗi đẩy GPS: $e');
    }
  }

  /// THUẬT TOÁN TÍNH TOÁN VÒNG TRÒN AN TOÀN VÀ PHÁT HIỆN CẢNH BÁO
  void _evaluateDistance() {
    MemberInfo? leader;
    MemberInfo? sweeper;

    // Bước 1: Tìm Leader và Sweeper
    for (final member in members.values) {
      if (member.role == 'Leader') {
        leader = member;
      } else if (member.role == 'Sweeper') {
        sweeper = member;
      }
    }

    // Bước 2: Nếu không đủ Leader và Sweeper, reset tất cả dữ liệu
    if (leader == null || sweeper == null) {
      alert = RadarAlert.empty();
      safeCircle = null;
      leaderSweeperDistance = '';
      return;
    }

    // Bước 3: Tính khoảng cách giữa Leader và Sweeper
    final distanceLeaderSweeper = calculateDistanceMeters(
      startLat: leader.location.latitude,
      startLng: leader.location.longitude,
      endLat: sweeper.location.latitude,
      endLng: sweeper.location.longitude,
    );

    leaderSweeperDistance = '${distanceLeaderSweeper.toStringAsFixed(1)} m';

    // Bước 4: Xác định tâm vòng tròn (điểm giữa Leader và Sweeper)
    final centerLat =
        (leader.location.latitude + sweeper.location.latitude) / 2;
    final centerLng =
        (leader.location.longitude + sweeper.location.longitude) / 2;
    final circleCenter = LatLng(centerLat, centerLng);

    // Bước 5: Xác định bán kính vòng tròn (nửa khoảng cách Leader-Sweeper)
    final radiusMeters = distanceLeaderSweeper / 2;

    safeCircle = SafeCircle(center: circleCenter, radiusMeters: radiusMeters);

    // Bước 6: Quét các Member để tìm người lạc (nằm ngoài vòng tròn)
    final lostMembersList = <String>[];
    for (final entry in members.entries) {
      final memberId = entry.key;
      final member = entry.value;

      // Bỏ qua Leader và Sweeper
      if (member.role == 'Leader' || member.role == 'Sweeper') {
        continue;
      }

      // Tính khoảng cách từ vị trí member đến tâm vòng tròn
      final distanceToCenter = calculateDistanceMeters(
        startLat: member.location.latitude,
        startLng: member.location.longitude,
        endLat: circleCenter.latitude,
        endLng: circleCenter.longitude,
      );

      // Nếu khoảng cách > bán kính, member này đã lạc
      if (distanceToCenter > radiusMeters) {
        lostMembersList.add(memberId);
      }
    }

    // Bước 7: Phát hiện cảnh báo
    final isLeaderSweeperFar = distanceLeaderSweeper >= DISCONNECTION_THRESHOLD;

    alert = RadarAlert(
      isLeaderSweeperFar: isLeaderSweeperFar,
      lostMembers: lostMembersList,
    );
  }

  /// Lấy thông tin Leader
  MemberInfo? get leader {
    return members.values.cast<MemberInfo?>().firstWhere(
      (member) => member?.role == 'Leader',
      orElse: () => null,
    );
  }

  /// Lấy thông tin Sweeper
  MemberInfo? get sweeper {
    return members.values.cast<MemberInfo?>().firstWhere(
      (member) => member?.role == 'Sweeper',
      orElse: () => null,
    );
  }

  /// Lấy danh sách các Member (không bao gồm Leader và Sweeper)
  List<MemberInfo> get membersList {
    return members.values.where((member) => member.role == 'Member').toList();
  }

  /// Lấy ID của Leader
  String? get leaderId {
    return leader?.id;
  }

  /// Lấy ID của Sweeper
  String? get sweeperId {
    return sweeper?.id;
  }

  /// Số lượng thành viên trong phòng
  int get totalMembers => members.length;

  /// Có cảnh báo hay không
  bool get hasAlert => alert.hasAlert;

  /// Giải phóng tài nguyên
  @override
  void dispose() {
    _positionSubscription?.cancel();
    _gpsStreamSubscription?.cancel();
    locationService.dispose();
    repository.dispose();
    super.dispose();
  }
}
