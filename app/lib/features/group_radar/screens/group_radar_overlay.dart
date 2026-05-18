import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

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

/// Màn hình Lõi của ứng dụng: Nhúng Main Map và phủ lên các tính năng (Overlays)
/// Nó đóng vai trò "Nhạc trưởng" điều phối dữ liệu từ Firebase và ra lệnh cho MapStateProvider vẽ.
class GroupRadarOverlay extends StatefulWidget {
  final String roomId;
  final UserModel currentUser;

  const GroupRadarOverlay({
    Key? key,
    required this.roomId,
    required this.currentUser,
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
  
  // Lưu trữ dữ liệu lấy từ Firebase
  Map<String, dynamic> _memberInfo = {}; // Chứa tên, vai trò của các thành viên
  Map<String, mapbox.Position> _memberLocations = {}; // Chứa tọa độ GPS của thành viên
  List<WarningMarker> _riskLabels = []; // Các cảnh báo nguy hiểm trên đường

  bool _isTooFar = false; // Cờ cảnh báo đứt đội hình

  @override
  void initState() {
    super.initState();
    _startMyGpsTracker();
    _listenToFirebaseStreams();
  }

  /// 1. Liên tục lấy GPS của máy mình và bắn lên Realtime DB
  void _startMyGpsTracker() {
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Di chuyển 10 mét thì cập nhật 1 lần
      ),
    ).listen((pos) {
      _myLastPos = mapbox.Position(pos.longitude, pos.latitude);
      
      // Bắn lên Firebase Realtime DB
      _roomRepo.updateUserLocation(
        widget.roomId, 
        widget.currentUser.id, 
        pos.latitude, 
        pos.longitude
      );

      // Kiểm tra xem mình có đi quá xa đội hình không
      _checkFormationDistance();
    });
  }

  /// 2. Lắng nghe mọi thứ từ Firebase (Người khác đi tới đâu, ai vừa báo ổ gà...)
  void _listenToFirebaseStreams() {
    // A. Lắng nghe thông tin phòng (Để lấy lộ trình và danh sách thành viên)
    _roomDataSub = _roomRepo.listenToRoomData(widget.roomId).listen((doc) async {
      if (!doc.exists) return;
      final data = doc.data()!;
      
      // Cập nhật thông tin thành viên
      _memberInfo = data['memberInfo'] as Map<String, dynamic>? ?? {};

      // Vẽ lộ trình nếu Leader đã tạo lộ trình
      final routeData = data['route'] as Map<String, dynamic>?;
      if (routeData != null && routeData['polyline'] != null) {
        final polyList = routeData['polyline'] as List;
        final coords = polyList.map((p) => mapbox.Position(
          (p['lng'] as num).toDouble(),
          (p['lat'] as num).toDouble()
        )).toList();
        
        if (mounted) {
          // Ra lệnh cho Provider vẽ đường
          context.read<MapStateProvider>().drawRoutePolyline(coords);
          
          // Vẽ Điểm đến
          final endName = routeData['endName']?.toString() ?? 'Đích đến';
          if (coords.isNotEmpty) {
            context.read<MapStateProvider>().drawDestinationMarker(coords.last, endName);
          }
        }
      }
    });

    // B. Lắng nghe GPS thời gian thực của nhóm
    _memberLocationsSub = _roomRepo.listenToRoomLocations(widget.roomId).listen((data) {
      final newLocations = <String, mapbox.Position>{};
      data.forEach((uid, info) {
        if (info is Map && info['lat'] != null && info['lng'] != null) {
          // KHÔNG vẽ chính mình lên bản đồ, vì Mapbox đã có chấm xanh rùi
          if (uid != widget.currentUser.id) {
             newLocations[uid] = mapbox.Position(
               (info['lng'] as num).toDouble(),
               (info['lat'] as num).toDouble(),
             );
          }
        }
      });
      _memberLocations = newLocations;
      _updateMapMembers();
      _checkFormationDistance();
    });

    // C. Lắng nghe Cảnh báo (Ổ gà, CSGT...)
    _warningsSub = _warningRepo.listenToRoomWarnings(widget.roomId).listen((warnings) {
      _riskLabels = warnings;
      _updateMapRisks();
    });
  }

  /// Gọi Provider để vẽ Members
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

    context.read<MapStateProvider>().drawMemberMarkers(_memberLocations, displayNames, roles);
  }

  /// Gọi Provider để vẽ Risks
  void _updateMapRisks() {
    if (!mounted) return;
    context.read<MapStateProvider>().drawRiskMarkers(_riskLabels, _memberLocations);
  }

  /// Thuật toán kiểm tra "Đứt đội hình" (Xa nhau quá 2km)
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
      if (dist > 2000.0) { // Lớn hơn 2000 mét (2km)
        tooFar = true;
        break;
      }
    }

    if (tooFar != _isTooFar) {
      setState(() => _isTooFar = tooFar);
    }
  }

  /// Xử lý khi user chọn một điểm đến trên thanh tìm kiếm (Chỉ Leader)
  void _handleDestinationSelected(mapbox.Position destPos, String placeName) async {
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

    // 1. Dùng RouteUtils gọi Mapbox API tìm đường
    final coords = await RouteUtils.getMapboxRoute(_myLastPos!, destPos);
    if (coords.isEmpty) return;

    // 2. Format dữ liệu để ném lên Cloud Function
    final polylineData = coords.map((c) => {'lng': c.lng.toDouble(), 'lat': c.lat.toDouble()}).toList();

    // 3. Gọi Backend để chia sẻ cho cả nhóm
    await _roomRepo.setRoomRoute(
      roomId: widget.roomId,
      polyline: polylineData,
      startName: 'Vị trí hiện tại',
      endName: placeName,
    );
  }

  /// Xử lý khi user đọc Voice AI (Ví dụ: "Phía trước có ổ gà")
  void _handleVoiceResult(String text) async {
    if (_myLastPos == null) return;
    
    // Đẩy text cho Backend gọi Gemini
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
           SnackBar(content: Text('AI đã thêm cảnh báo: $category', style: const TextStyle(color: Colors.green))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('AI không chắc chắn đó là rủi ro gì.', style: TextStyle(color: Colors.orange))),
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
    return Scaffold(
      body: Stack(
        children: [
          // LỚP ĐÁY: BẢN ĐỒ CHÍNH (Ngu ngơ, chỉ biết hiển thị)
          const MainMapScreen(),

          // LỚP TRÊN: THANH TÌM KIẾM
          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: RoutingSearchBar(
              onDestinationSelected: _handleDestinationSelected,
              onClear: () {
                context.read<MapStateProvider>().clearAll();
              },
            ),
          ),

          // CẢNH BÁO ĐỨT ĐỘI HÌNH
          if (_isTooFar)
            Positioned(
              top: 130,
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
                    Icon(Icons.warning_amber_rounded, color: Colors.white, size: 30),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'CẢNH BÁO ĐỨT ĐỘI HÌNH!\nBạn đang cách xa các thành viên khác hơn 2km.',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // LỚP NỔI: NÚT THU ÂM BÁO RỦI RO
          Positioned(
            bottom: 30,
            right: 20,
            child: VoiceFab(
              onVoiceResult: _handleVoiceResult,
            ),
          ),

          // LỚP NỔI: NÚT QUAY LẠI
          Positioned(
            bottom: 30,
            left: 20,
            child: FloatingActionButton(
              heroTag: 'back_fab',
              backgroundColor: Colors.white,
              onPressed: () => Navigator.of(context).pop(),
              child: const Icon(Icons.arrow_back, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}
