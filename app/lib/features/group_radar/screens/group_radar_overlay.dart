import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

// TODO: Đổi lại các đường dẫn import này cho đúng với cấu trúc của nhóm bạn
import '../../../data/models/user_model.dart';
import '../../../data/models/warning_marker.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../data/repositories/warning_repository.dart';
import '../../main_map/main_map_screen.dart';
import '../../main_map/providers/map_state_provider.dart';
import '../../map_routing/widgets/routing_search_bar.dart';
import '../widgets/voice_fab.dart';
import '../../../core/utils/route_utils.dart';
import '../../../core/utils/geo_utils.dart';

class GroupRadarOverlay extends StatefulWidget {
  final String roomId;
  final UserModel currentUser;
  final VoidCallback onLeaveRoom;

  const GroupRadarOverlay({
    Key? key,
    required this.roomId,
    required this.currentUser,
    required this.onLeaveRoom,
  }) : super(key: key);

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

  mapbox.Position? _myLastPos;

  Map<String, dynamic> _memberInfo = {};
  Map<String, mapbox.Position> _memberLocations = {};
  List<WarningMarker> _riskLabels = [];

  bool _isTooFar = false;

  // THÊM BIẾN NÀY ĐỂ QUẢN LÝ THU/MỞ BẢNG THÔNG TIN
  bool _isInfoExpanded = false;

  @override
  void initState() {
    super.initState();
    _startMyGpsTracker();
    _listenToFirebaseStreams();
  }

  void _startMyGpsTracker() {
    _gpsSub =
        Geolocator.getPositionStream(
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
        });
  }

  void _listenToFirebaseStreams() {
    // 1. Lắng nghe dữ liệu phòng
    _roomDataSub = _roomRepo.listenToRoomData(widget.roomId).listen((
      doc,
    ) async {
      if (!doc.exists) return;
      final data = doc.data()!;

      setState(() {
        _memberInfo = data['memberInfo'] as Map<String, dynamic>? ?? {};
      });

      final routeData = data['route'] as Map<String, dynamic>?;
      if (routeData != null && routeData['polyline'] != null) {
        final polyList = routeData['polyline'] as List;
        final coords = polyList
            .map(
              (p) => mapbox.Position(
                (p['lng'] as num).toDouble(),
                (p['lat'] as num).toDouble(),
              ),
            )
            .toList();

        if (mounted) {
          context.read<MapStateProvider>().drawRoutePolyline(coords);
          final endName = routeData['endName']?.toString() ?? 'Đích đến';
          if (coords.isNotEmpty) {
            context.read<MapStateProvider>().drawDestinationMarker(
              coords.last,
              endName,
            );
          }
        }
      }
    });

    // 2. Lắng nghe Vị trí thành viên để vẽ lên bản đồ
    _memberLocationsSub = _roomRepo.listenToRoomLocations(widget.roomId).listen(
      (data) {
        final newLocations = <String, mapbox.Position>{};
        data.forEach((uid, info) {
          if (info is Map && info['lat'] != null && info['lng'] != null) {
            if (uid != widget.currentUser.id) {
              newLocations[uid] = mapbox.Position(
                (info['lng'] as num).toDouble(),
                (info['lat'] as num).toDouble(),
              );
            }
          }
        });
        _memberLocations = newLocations;

        _updateMapMembers(); // Cập nhật vẽ marker
        _checkFormationDistance();
      },
    );

    // 3. Lắng nghe cảnh báo rủi ro
    _warningsSub = _warningRepo.listenToRoomWarnings(widget.roomId).listen((
      warnings,
    ) {
      _riskLabels = warnings;
      _updateMapRisks();
    });
  }

  void _updateMapMembers() {
    if (!mounted) return;

    final displayNames = <String, String>{};
    final roles = <String, String>{};

    _memberInfo.forEach((uid, info) {
      if (info is Map) {
        displayNames[uid] = info['displayName']?.toString() ?? 'User';
        roles[uid] = info['role']?.toString() ?? 'member';
      }
    });

    // GỌI SANG M2 ĐỂ VẼ VỊ TRÍ
    context.read<MapStateProvider>().drawMemberMarkers(
      _memberLocations,
      displayNames,
      roles,
    );
  }

  void _updateMapRisks() {
    if (!mounted) return;
    context.read<MapStateProvider>().drawRiskMarkers(
      _riskLabels,
      _memberLocations,
    );
  }

  void _checkFormationDistance() {
    if (_myLastPos == null || _memberLocations.isEmpty) return;

    bool tooFar = false;
    for (final pos in _memberLocations.values) {
      final dist = calculateDistanceMeters(
        startLat: _myLastPos!.lat.toDouble(),
        startLng: _myLastPos!.lng.toDouble(),
        endLat: pos.lat.toDouble(),
        endLng: pos.lng.toDouble(),
      );
      if (dist > 2000.0) {
        tooFar = true;
        break;
      }
    }

    if (tooFar != _isTooFar) {
      setState(() => _isTooFar = tooFar);
    }
  }

  void _handleDestinationSelected(
    mapbox.Position destPos,
    String placeName,
  ) async {
    if (widget.currentUser.role != UserRole.leader) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chỉ Leader mới có quyền tạo lộ trình!')),
      );
      return;
    }

    if (_myLastPos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa lấy được GPS hiện tại của bạn!')),
      );
      return;
    }

    final coords = await RouteUtils.getMapboxRoute(_myLastPos!, destPos);
    if (coords.isEmpty) return;

    final polylineData = coords
        .map((c) => {'lng': c.lng.toDouble(), 'lat': c.lat.toDouble()})
        .toList();

    await _roomRepo.setRoomRoute(
      roomId: widget.roomId,
      polyline: polylineData,
      startName: 'Vị trí hiện tại',
      endName: placeName,
    );
  }

  void _handleVoiceResult(String text) async {
    if (_myLastPos == null) return;

    final result = await _warningRepo.parseRiskFromVoice(
      roomId: widget.roomId,
      voiceText: text,
      lat: _myLastPos!.lat.toDouble(),
      lng: _myLastPos!.lng.toDouble(),
    );

    if (result != null && mounted) {
      final category = result['category'];
      final conf = result['confidence'] as double;
      if (conf > 0.5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'AI đã thêm cảnh báo: $category',
              style: const TextStyle(color: Colors.green),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'AI không chắc chắn đó là rủi ro gì.',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _roomDataSub?.cancel();
    _memberLocationsSub?.cancel();
    _warningsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ĐÃ XÓA TẤM KÍNH SCAFFOLD
    return SafeArea(
      child: Stack(
        children: [
          // Thanh tìm kiếm
          Positioned(
            top: 16, // Chỉnh lại top cho vừa vặn vì đã có SafeArea
            left: 16,
            right: 16,
            child: RoutingSearchBar(
              onDestinationSelected: _handleDestinationSelected,
              onClear: () {
                context.read<MapStateProvider>().clearAll();
              },
            ),
          ),

          // BẢNG THÔNG TIN PHÒNG (HUD PANEL) - ĐÃ LÀM GỌN & THÊM HIỆU ỨNG MỞ RỘNG
          Positioned(
            top: 90,
            left: 16,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isInfoExpanded = !_isInfoExpanded; // Đảo trạng thái thu/mở
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: _isInfoExpanded ? 240 : 150, // Chiều rộng linh hoạt
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // PHẦN HEADER LÚC NÀO CŨNG HIỆN (Bản thu gọn)
                    Row(
                      children: [
                        const Icon(Icons.tag, color: Colors.blue, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Phòng: ${widget.roomId}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          _isInfoExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: Colors.grey,
                        ),
                      ],
                    ),

                    // PHẦN CHI TIẾT (Chỉ hiện khi _isInfoExpanded == true)
                    if (_isInfoExpanded) ...[
                      const Divider(height: 16),
                      // 1. Trạng thái đội hình
                      Row(
                        children: [
                          Icon(
                            _isTooFar ? Icons.gpp_bad : Icons.verified_user,
                            color: _isTooFar ? Colors.red : Colors.green,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Đội hình: ${_isTooFar ? "Đứt đoàn" : "Ổn định"}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _isTooFar ? Colors.red : Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 2. Danh sách thành viên chi tiết
                      Text(
                        'Thành viên (${_memberInfo.length}):',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Giới hạn chiều cao danh sách để không che hết bản đồ nếu nhóm quá đông
                      Container(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: SingleChildScrollView(
                          child: Column(
                            children: _memberInfo.entries.map((entry) {
                              final info = entry.value as Map;
                              final name =
                                  info['displayName']?.toString() ?? 'Ẩn danh';
                              final role = info['role']?.toString() ?? 'member';

                              // Đổi màu theo vai trò cho sinh động
                              Color roleColor = Colors.orange; // Member
                              if (role == 'leader') roleColor = Colors.blue;
                              if (role == 'sweeper') roleColor = Colors.green;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.two_wheeler,
                                      size: 14,
                                      color: roleColor,
                                    ),
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: roleColor.withOpacity(0.1),
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

          // Cảnh báo đứt đoàn
          if (_isTooFar)
            Positioned(
              top: 200,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'CẢNH BÁO ĐỨT ĐỘI HÌNH!\nBạn đang cách xa các thành viên khác hơn 2km.',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            bottom: 30,
            right: 20,
            child: VoiceFab(onVoiceResult: _handleVoiceResult),
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
        ],
      ),
    );
  }
}
