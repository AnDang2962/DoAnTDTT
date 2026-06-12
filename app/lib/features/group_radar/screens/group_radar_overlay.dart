import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../../map_routing/widgets/marker_detail_sheet.dart';
import '../widgets/member_detail_sheet.dart';
import '../../map_routing/services/weather_api.dart';
import '../../map_routing/widgets/risk_report_sheet.dart';
import '../../../core/utils/route_utils.dart';
import '../../map_routing/widgets/waypoint_search_sheet.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/services/sound_service.dart';
import '../../../core/providers/voice_command_provider.dart';
import '../../map_routing/services/gemini_ai_api.dart';
import '../../map_routing/services/geocoding_api.dart';
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
  Set<String> _prevMemberUids = {};
  Map<String, mapbox.Position> _memberLocations = {};
  final Set<String> _announcedRiskIds = {};
  final Set<String> _knownRiskIds = {};
  int _lastRiskCheckMs = 0;
  bool _arrivedNotified = false;
  final Set<String> _arrivedMemberUids = {};
  mapbox.Position? _destPos;

  String? _loadedRouteKey;

  bool _isTooFar = false;
  bool _prevIsTooFar = false;
  Set<String> _prevOffRouteUids = {};
  List<Map<String, dynamic>> _gapDetails = [];
  List<Map<String, dynamic>> _offRouteWarnings = [];
  DateTime? _lastGapCheck;

  String? _sweeperAlertType;
  String? _incomingSweeperAlertType;

  bool _groupStopActive = false;
  String _groupStopLabel = 'Leader';

  int _lastGroupMsgTs = 0;
  List<String> _customMessages = [];

  bool _isLoading = false;

  List<RouteWaypoint> _waypoints = [];
  bool _addingWaypointByMap = false;

  bool _panelOpen = false;
  DateTime? _navStartTime;
  static const double _panelWidth = 256.0;
  static const double _panelHandleWidth = 16.0;
  List<Map<String, double>> _polylineData = [];

  VoiceCommandProvider? _voiceProv;
  int _lastVoiceVersion = 0;
  MapStateProvider? _mapProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapProvider = context.read<MapStateProvider>();
      _mapProvider!.setGroupMode(true);
      _mapProvider!.setMapTapHandler(_onMapTap);
      _mapProvider!.setMarkerTapHandler((m) { if (mounted) MarkerDetailSheet.show(context, m); });
      _mapProvider!.setMemberTapHandler((uid) { if (mounted) _showMemberDetail(uid); });
      if (widget.currentUser.role == UserRole.leader) {
        _mapProvider!.setRouteTapHandler(_onRouteTap);
      }
      _voiceProv = context.read<VoiceCommandProvider>();
      _voiceProv!.addListener(_onVoiceCommand);
    });
    _startMyGpsTracker();
    _listenToFirebaseStreams();
    _loadCustomMessages();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _panelOpen = true);
    });
    Future.delayed(const Duration(milliseconds: 3400), () {
      if (mounted) setState(() => _panelOpen = false);
    });
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
          final heading = pos.heading >= 0 ? pos.heading : null;
          unawaited(mapProvider.setNavArrow(_myLastPos!, bearing: heading));
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
      }
    });
  }

  void _checkNearbyRisks() {
    if (_myLastPos == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRiskCheckMs < 5000) return;
    _lastRiskCheckMs = now;

    final seen = <String>{};
    final allRisks = [..._realtimeRisks, ..._crossGroupRisks]
        .where((r) => seen.add(r.id))
        .toList();
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

  void _listenToFirebaseStreams() {
    _roomDataSub = _roomRepo.listenToRoomData(widget.roomId).listen((doc) async {
      if (!doc.exists) return;
      final data = doc.data()!;

      final newMemberInfo = data['memberInfo'] as Map<String, dynamic>? ?? {};
      final newUids = newMemberInfo.keys.toSet();
      if (_prevMemberUids.isNotEmpty) {
        for (final uid in newUids.difference(_prevMemberUids)) {
          if (uid == widget.currentUser.id) continue;
          unawaited(SoundService().playMemberJoin());
          final name = (newMemberInfo[uid] as Map?)?['displayName']?.toString() ?? 'Thành viên mới';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('👋 $name đã vào phòng'),
              duration: const Duration(seconds: 3),
            ));
          }
        }
        for (final uid in _prevMemberUids.difference(newUids)) {
          if (uid == widget.currentUser.id) continue;
          unawaited(SoundService().playMemberLeave());
          final info = _memberInfo[uid] as Map?;
          final name = info?['displayName']?.toString() ?? 'Một thành viên';
          final role = info?['role']?.toString() ?? 'member';
          if (mounted) {
            final content = role == 'leader' ? '👑 Leader đã rời phòng' : '🚪 $name đã rời phòng';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(content),
              duration: Duration(seconds: role == 'leader' ? 5 : 3),
            ));
          }
        }
      }
      _prevMemberUids = newUids;
      setState(() {
        _memberInfo = newMemberInfo;
      });

      final sweeperAlert = data['sweeperAlert'] as Map<String, dynamic>?;
      final alertType = sweeperAlert?['type']?.toString();
      final alertMsg = sweeperAlert?['message']?.toString();
      if (alertMsg != null && alertType != _incomingSweeperAlertType && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(alertMsg),
          duration: const Duration(seconds: 5),
        ));
      }
      _incomingSweeperAlertType = alertType;

      final groupStop = data['groupStop'] as Map<String, dynamic>?;
      final stopActive = groupStop?['active'] == true;
      final stopLabel = groupStop?['triggerLabel']?.toString() ?? 'Leader';
      if (stopActive != _groupStopActive && mounted) {
        if (stopActive) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$stopLabel yêu cầu dừng đoàn'),
            duration: const Duration(seconds: 6),
          ));
          unawaited(TtsService().speak('$stopLabel yêu cầu dừng đoàn'));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Đoàn tiếp tục di chuyển'),
            duration: Duration(seconds: 3),
          ));
          unawaited(TtsService().speak('Đoàn tiếp tục di chuyển'));
        }
      }
      if (mounted) {
        setState(() {
          _groupStopActive = stopActive;
          _groupStopLabel = stopLabel;
        });
      }

      final groupMsg = data['groupMessage'] as Map<String, dynamic>?;
      if (groupMsg != null) {
        final ts = (groupMsg['ts'] as num?)?.toInt() ?? 0;
        final text = groupMsg['text']?.toString() ?? '';
        final sender = groupMsg['senderName']?.toString() ?? '';
        final senderUid = groupMsg['senderUid']?.toString() ?? '';
        final isSelf = senderUid == widget.currentUser.id;
        if (ts != _lastGroupMsgTs && text.isNotEmpty && mounted) {
          _lastGroupMsgTs = ts;
          if (!isSelf) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('$sender: $text'),
              duration: const Duration(seconds: 5),
            ));
            unawaited(TtsService().speak(text.replaceAll(RegExp(r'[^\p{L}\p{N}\s,.!?]', unicode: true), '').trim()));
          }
        }
      }

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

        // Chỉ xử lý route mới — leader đã set _loadedRouteKey trước khi push nên sẽ skip,
        // tránh overwrite _fullRouteCoords bằng coords đã downsample từ Firebase
        if (mounted && routeKey != _loadedRouteKey) {
          final wasNavigating = _loadedRouteKey != null && (context.read<MapStateProvider>().isNavigating);
          _loadedRouteKey = routeKey;
          final mapProvider = context.read<MapStateProvider>();

          mapProvider.setFullRoute(coords);
          mapProvider.setRouteStatsFromCoords(coords);
          await mapProvider.drawRoutePolyline(coords);
          mapProvider.startNavigating();
          _navStartTime ??= DateTime.now();
          if (_myLastPos != null) unawaited(mapProvider.setNavArrow(_myLastPos!));
          _updateMapMembers();

          final endName = routeData['endName']?.toString() ?? 'Đích đến';
          if (coords.isNotEmpty) {
            _destPos = coords.last;
            await mapProvider.drawDestinationMarker(coords.last, endName, flyToMarker: false);
          }
          _arrivedNotified = false;
          _arrivedMemberUids.clear();
          mapProvider.flyToCurrentLocation();
          if (mounted) {
            final msg = wasNavigating
                ? '📍 Leader đã thay đổi đích đến: $endName'
                : '🚀 Leader đã bắt đầu dẫn đường đến $endName';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(msg),
              duration: const Duration(seconds: 4),
            ));
          }

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
          _announcedRiskIds.clear();
          _lastRiskCheckMs = 0;
          if (_myLastPos == null) {
            final fallback = await Geolocator.getLastKnownPosition();
            if (fallback != null) {
              _myLastPos = mapbox.Position(fallback.longitude, fallback.latitude);
            }
          }
          _checkNearbyRisks();
          await _loadWeatherAlongRoute(coords);
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
      if (_destPos != null && _mapProvider?.isNavigating == true) {
        for (final entry in newLocations.entries) {
          final uid = entry.key;
          if (uid == widget.currentUser.id) continue;
          if (_arrivedMemberUids.contains(uid)) continue;
          final dist = Geolocator.distanceBetween(
            entry.value.lat.toDouble(), entry.value.lng.toDouble(),
            _destPos!.lat.toDouble(), _destPos!.lng.toDouble(),
          );
          if (dist < 300) {
            _arrivedMemberUids.add(uid);
            final name = _memberName(uid);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('✅ $name đã đến nơi'),
                duration: const Duration(seconds: 4),
              ));
            }
          }
        }
      }
    });

    _warningsSub = _warningRepo.listenToRoomWarnings(widget.roomId).listen((warnings) {
      if (!mounted) return;

      // Phát hiện risk mới (chưa có trong _knownRiskIds)
      final newRisks = warnings.where((r) => !_knownRiskIds.contains(r.id)).toList();

      // Lần đầu load (snapshot ban đầu) — chỉ ghi nhận, không notify
      final isInitialLoad = _knownRiskIds.isEmpty && warnings.isNotEmpty;
      for (final r in warnings) { _knownRiskIds.add(r.id); }

      _realtimeRisks = warnings;
      _redrawAllRisks();

      if (!isInitialLoad) {
        for (final r in newRisks) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r.emoji} Leader vừa báo cáo: ${r.vi}'),
            duration: const Duration(seconds: 4),
          ));
        }
      }

      if (_mapProvider?.isNavigating == true) {
        _lastRiskCheckMs = 0;
        _checkNearbyRisks();
      }
    });
  }

  void _redrawAllRisks() {
    if (!mounted) return;
    final merged = <String, WarningMarker>{};
    for (final r in _realtimeRisks) { merged[r.id] = r; }
    for (final r in _crossGroupRisks) { merged[r.id] = r; }
    context.read<MapStateProvider>().drawRiskMarkers(merged.values.toList(), _memberLocations);
  }

  void _updateMapMembers() {
    if (!mounted) return;
    final roles = <String, String>{};
    final photoUrls = <String, String>{};
    _memberInfo.forEach((uid, info) {
      if (info is Map) {
        roles[uid] = info['role']?.toString() ?? 'member';
        final url = info['photoURL']?.toString();
        if (url != null && url.isNotEmpty) photoUrls[uid] = url;
      }
    });
    final mapProvider = context.read<MapStateProvider>();
    mapProvider.drawMemberMarkers(
      _memberLocations,
      roles,
      skipUid: widget.currentUser.id,
      photoUrls: photoUrls,
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
      final newIsTooFar = gaps.isNotEmpty || offRoute.isNotEmpty;
      final newOffRouteUids = offRoute
          .map((e) => e['memberId']?.toString() ?? '')
          .where((uid) => uid.isNotEmpty)
          .toSet();
      setState(() {
        _isTooFar = newIsTooFar;
        _gapDetails = gaps;
        _offRouteWarnings = offRoute;
      });
      for (final uid in newOffRouteUids.difference(_prevOffRouteUids)) {
        if (uid == widget.currentUser.id) continue;
        final name = _memberName(uid);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('⚠️ $name đã lệch tuyến đường'),
            duration: const Duration(seconds: 4),
          ));
        }
      }
      _prevOffRouteUids = newOffRouteUids;
      if (!_prevIsTooFar && newIsTooFar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('⚠️ Đội hình đứt đoạn — kiểm tra lại các thành viên'),
          duration: Duration(seconds: 5),
        ));
      }
      _prevIsTooFar = newIsTooFar;

      // Sweeper alert — chỉ thiết bị sweeper ghi Firestore
      final naturalSweeperId = (data['sweeper'] as Map<Object?, Object?>?)?['id']?.toString();
      String? designatedSweeperUid;
      String? leaderUid;
      _memberInfo.forEach((uid, info) {
        final role = (info as Map?)?['role']?.toString();
        if (role == 'sweeper') designatedSweeperUid = uid;
        if (role == 'leader') leaderUid = uid;
      });

      if (designatedSweeperUid != null && widget.currentUser.id == designatedSweeperUid) {
        String? newType;
        String? newMsg;

        if (naturalSweeperId != null && naturalSweeperId != designatedSweeperUid) {
          newType = 'member_behind';
          newMsg = '⚠️ ${_memberName(naturalSweeperId)} đang đi sau chốt đoàn';
        } else if (leaderUid != null) {
          final leaderGap = gaps.where((g) => g['memberId'] == leaderUid).firstOrNull;
          if (leaderGap != null) {
            final distKm = (leaderGap['distanceKm'] as num?)?.toDouble() ?? 0;
            newType = 'sweeper_gap';
            newMsg = '⚠️ Chốt đoàn cách leader ${distKm.toStringAsFixed(1)} km — đoàn đứt';
          }
        }

        if (newType != _sweeperAlertType) {
          _sweeperAlertType = newType;
          _roomRepo.updateSweeperAlert(
            widget.roomId,
            newType != null ? {'type': newType, 'message': newMsg} : null,
          );
        }
      }
    } catch (_) {}
  }

  void _showSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _showMemberDetail(String uid) async {
    final info = _memberInfo[uid] as Map?;
    if (info == null) return;
    final name = info['displayName']?.toString() ?? 'Thành viên';
    final role = info['role']?.toString() ?? 'member';
    final memberPos = _memberLocations[uid];
    double? distanceKm;
    if (memberPos != null && _myLastPos != null) {
      distanceKm = Geolocator.distanceBetween(
        _myLastPos!.lat.toDouble(), _myLastPos!.lng.toDouble(),
        memberPos.lat.toDouble(), memberPos.lng.toDouble(),
      ) / 1000;
    }

    String photoUrl = info['photoURL']?.toString() ?? '';
    String email = '';
    String phoneNumber = '';
    double? totalKm;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (snap.exists) {
        final data = snap.data()!;
        photoUrl = data['avatarUrl']?.toString() ?? photoUrl;
        email = data['email']?.toString() ?? '';
        phoneNumber = data['phoneNumber']?.toString() ?? '';
        totalKm = (data['totalKm'] as num?)?.toDouble();
      }
    } catch (_) {}

    if (!mounted) return;
    MemberDetailSheet.show(
      context,
      name: name,
      role: role,
      photoUrl: photoUrl,
      email: email,
      phoneNumber: phoneNumber,
      distanceKm: distanceKm,
      totalKm: totalKm,
    );
  }

  Future<void> _toggleGroupStop() async {
    final myInfo = _memberInfo[widget.currentUser.id] as Map?;
    final myName = myInfo?['displayName']?.toString() ?? widget.currentUser.name;
    if (_groupStopActive) {
      await _roomRepo.updateGroupStop(widget.roomId, null);
    } else {
      final triggerLabel = widget.currentUser.role == UserRole.sweeper ? 'Chốt đoàn' : 'Leader';
      await _roomRepo.updateGroupStop(widget.roomId, {
        'active': true,
        'triggerName': myName,
        'triggerLabel': triggerLabel,
        'lat': _myLastPos?.lat ?? 0,
        'lng': _myLastPos?.lng ?? 0,
      });
    }
  }

  static const List<String> _presetMessages = [
    '🏎 Đi nhanh lên',
    '🐢 Đi chậm lại',
    '⛽ Dừng tại trạm xăng',
    '🍜 Dừng ăn uống',
    '⚠️ Chú ý đường xấu phía trước',
    '↰ Rẽ trái phía trước',
    '↱ Rẽ phải phía trước',
    '✅ Đi đúng hướng',
  ];

  Future<void> _loadCustomMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('group_custom_messages_${widget.currentUser.id}') ?? [];
    if (mounted) setState(() => _customMessages = saved);
  }

  Future<void> _saveCustomMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('group_custom_messages_${widget.currentUser.id}', _customMessages);
  }

  Future<void> _sendGroupMessage(String text) async {
    final myInfo = _memberInfo[widget.currentUser.id] as Map?;
    final myName = myInfo?['displayName']?.toString() ?? widget.currentUser.name;
    await _roomRepo.sendGroupMessage(widget.roomId, text, myName, widget.currentUser.id);
  }

  void _showQuickMessageSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _QuickMessageSheet(
        presets: _presetMessages,
        customs: List.from(_customMessages),
        onSend: (text) {
          Navigator.pop(ctx);
          _sendGroupMessage(text);
          unawaited(TtsService().speak(text.replaceAll(RegExp(r'[^\p{L}\p{N}\s,.!?]', unicode: true), '').trim()));
        },
        onCustomsChanged: (updated) {
          setState(() => _customMessages = updated);
          _saveCustomMessages();
        },
      ),
    );
  }

  void _handleDestinationSelected(mapbox.Position destPos, String placeName) async {
    if (widget.currentUser.role != UserRole.leader) {
      _showSnackbar('Chỉ Leader mới có quyền tạo lộ trình!'); return;
    }
    if (_myLastPos == null) {
      _showSnackbar('Chưa lấy được GPS hiện tại của bạn!'); return;
    }
    final mapProvider = context.read<MapStateProvider>();
    await mapProvider.clearAll(keepMemberMarkers: true);
    mapProvider.clearRoutes();
    await mapProvider.drawDestinationMarker(destPos, placeName);
    setState(() {
      _lastDestPos = destPos;
      _lastDestName = placeName;
      _polylineData = [];
      _waypoints = [];
      _addingWaypointByMap = false;
    });
    _destPos = destPos;
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
      await _recalculateAndRestartGroupNav();
    } else {
      if (mapProvider.availableRoutes.isNotEmpty || _polylineData.isNotEmpty) {
        final destName = mapProvider.previewDestName ?? 'Điểm đến';
        await mapProvider.clearAll(keepMemberMarkers: true);
        mapProvider.clearRoutes();
        setState(() => _polylineData = []);
        if (_lastDestPos != null) {
          await mapProvider.drawDestinationMarker(_lastDestPos!, destName, flyToMarker: false);
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
      await _recalculateAndRestartGroupNav();
    } else {
      if (mapProvider.availableRoutes.isNotEmpty || _polylineData.isNotEmpty) {
        final destName = mapProvider.previewDestName ?? 'Điểm đến';
        await mapProvider.clearAll(keepMemberMarkers: true);
        mapProvider.clearRoutes();
        setState(() => _polylineData = []);
        if (_lastDestPos != null) {
          await mapProvider.drawDestinationMarker(_lastDestPos!, destName, flyToMarker: false);
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

  void _onRouteTap(int routeIndex) async {
    if (!mounted) return;
    final mapProvider = context.read<MapStateProvider>();
    if (routeIndex == mapProvider.selectedRouteIndex) return;
    mapProvider.selectRoute(routeIndex);
    await mapProvider.drawMultipleRoutesPreview();
    await _loadRouteDetails(mapProvider.availableRoutes, routeIndex);
  }

  Future<void> _recalculateAndRestartGroupNav() async {
    if (_lastDestPos == null || _myLastPos == null) return;
    final mapProvider = context.read<MapStateProvider>();
    final destName = _lastDestName ?? 'Điểm đến';

    _arrivedNotified = false;
    _announcedRiskIds.clear();
    _lastRiskCheckMs = 0;

    await mapProvider.clearAll(keepMemberMarkers: true);
    mapProvider.clearRoutes();
    setState(() => _polylineData = []);

    await mapProvider.drawDestinationMarker(_lastDestPos!, destName, flyToMarker: false);
    await mapProvider.drawWaypointMarkers(_waypoints.map((w) => w.pos).toList());

    await _getDirections();
    if (!mounted || mapProvider.availableRoutes.isEmpty) return;
    await _startGroupNavigation(mapProvider);
  }

  Future<void> _getDirections() async {
    if (_lastDestPos == null || _myLastPos == null) return;
    setState(() => _isLoading = true);
    try {
      final routes = await RouteUtils.getMultipleMapboxRoutes(
        _myLastPos!,
        _lastDestPos!,
        viaWaypoints: _waypoints.map((w) => w.pos).toList(),
      );
      if (!mounted) return;
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
      final messenger = ScaffoldMessenger.of(context);
      await mapProvider.drawWeatherMarkers(weatherWarnings);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Đã thêm ${weatherWarnings.length} điểm thời tiết'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _onMapTap(mapbox.Position pos) async {
    if (!mounted) return;
    if (widget.currentUser.role != UserRole.leader) return;
    final mapProvider = context.read<MapStateProvider>();
    if (_isLoading) return;

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
    _handleDestinationSelected(pos, name);
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
      onAddWaypoint: widget.currentUser.role == UserRole.leader
          ? (pos, name) => unawaited(_addWaypoint(pos, name))
          : null,
      onGroupBroadcast: (widget.currentUser.role == UserRole.leader ||
              widget.currentUser.role == UserRole.sweeper)
          ? (msg) => _sendGroupMessage(msg)
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

    final distKm = (chosenRoute['distance'] as num).toDouble() / 1000.0;
    final durMins = ((chosenRoute['duration'] as num).toDouble() / 60.0).round();
    mapProvider.clearRoutesData();
    mapProvider.setFullRoute(routeCoords);
    mapProvider.setRouteStats(distKm, durMins);
    await mapProvider.drawRoutePolyline(routeCoords);

    if (widget.roomId.isNotEmpty) {
      await _roomRepo.setRoomRoute(
        roomId: widget.roomId,
        polyline: _polylineData,
        startName: 'Vị trí hiện tại',
        endName: mapProvider.previewDestName ?? 'Điểm đến',
      );
    }

    // Set key trước khi push Firebase để listener không overwrite _fullRouteCoords
    _loadedRouteKey = routeCoords.isEmpty
        ? ''
        : '${routeCoords.first.lng},${routeCoords.first.lat}-${routeCoords.last.lng},${routeCoords.last.lat}';

    if (_polylineData.isNotEmpty) _startCrossGroupRiskTimer(_polylineData);
    _destPos = _lastDestPos;
    _arrivedNotified = false;
    _arrivedMemberUids.clear();
    _announcedRiskIds.clear();
    _lastRiskCheckMs = 0;
    mapProvider.startNavigating();
    _navStartTime ??= DateTime.now();
    if (_myLastPos != null) unawaited(mapProvider.setNavArrow(_myLastPos!));
    _updateMapMembers();

    mapProvider.flyToCurrentLocation();
    if (_myLastPos == null) {
      final fallback = await Geolocator.getLastKnownPosition();
      if (fallback != null) {
        _myLastPos = mapbox.Position(fallback.longitude, fallback.latitude);
      }
    }
    _checkNearbyRisks();
  }

  String _memberName(String uid) {
    final info = _memberInfo[uid];
    if (info is Map) return info['displayName']?.toString() ?? uid.substring(0, 6);
    return uid.substring(0, 6);
  }

  Widget _buildGroupRouteInfo(MapStateProvider mapProvider) {
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

  void _onVoiceCommand() {
    if (!mounted) return;
    final prov = _voiceProv!;
    if (prov.version == _lastVoiceVersion) return;
    _lastVoiceVersion = prov.version;
    _handleVoiceResult(prov.lastCommand);
  }

  @override
  void dispose() {
    _voiceProv?.removeListener(_onVoiceCommand);
    _mapProvider?.setMapTapHandler(null);
    _mapProvider?.setMarkerTapHandler(null);
    _mapProvider?.setMemberTapHandler(null);
    _mapProvider?.setRouteTapHandler(null);
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

  ({String uid, String endName, double totalKm, double traveledKm, int elapsedMins, bool completed})? _captureNavSnapshot() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final mapProvider = _mapProvider;
    if (uid == null || _navStartTime == null || mapProvider == null) return null;
    if (!mapProvider.isNavigating) return null;
    final totalKm = mapProvider.initialDistanceKm;
    if (totalKm < 0.1) return null;
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
    } catch (_) {}
  }

  void _showQrDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Mã QR phòng', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(widget.roomId, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 6, color: Colors.blue)),
              const SizedBox(height: 16),
              QrImageView(
                data: widget.roomId,
                version: QrVersions.auto,
                size: 200,
              ),
              const SizedBox(height: 12),
              const Text('Thành viên quét mã này để vào phòng', style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapStateProvider>();
    return SafeArea(
      child: Stack(
        children: [
          if (_addingWaypointByMap && widget.currentUser.role == UserRole.leader)
            Positioned(
              top: 16, left: 16, right: 16,
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
          else if (!mapProvider.isNavigating && widget.currentUser.role == UserRole.leader)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: RoutingSearchBar(
                onDestinationSelected: _handleDestinationSelected,
                destinationName: _lastDestPos != null ? _lastDestName : null,
                onClear: () async {
                  await mapProvider.clearAll(keepMemberMarkers: true);
                  mapProvider.clearRoutes();
                  _sweeperAlertType = null;
                  _roomRepo.updateSweeperAlert(widget.roomId, null);
                  setState(() {
                    _lastDestPos = null;
                    _lastDestName = null;
                    _polylineData = [];
                    _crossGroupRisks = [];
                    _waypoints = [];
                    _addingWaypointByMap = false;
                  });
                },
              ),
            ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            top: 90,
            left: _panelOpen ? 0.0 : -(_panelWidth - _panelHandleWidth),
            width: _panelWidth,
            child: SizedBox(
              width: _panelWidth,
              child: Stack(
                children: [
                  SizedBox(
                    width: _panelWidth - _panelHandleWidth,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 320),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(4, 0))],
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 16, 8, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.tag, color: Colors.blue, size: 16),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Phòng: ${widget.roomId}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _showQrDialog(context),
                                child: const Icon(Icons.qr_code, color: Colors.blue, size: 20),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                _isTooFar ? Icons.gpp_bad : Icons.verified_user,
                                color: _isTooFar ? Colors.red : Colors.green,
                                size: 15,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Đội hình: ${_isTooFar ? "Đứt đoàn" : "Ổn định"}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _isTooFar ? Colors.red : Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Text(
                            'Thành viên (${_memberInfo.length})',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          ..._memberInfo.entries.map((entry) {
                            final info = entry.value as Map;
                            final name = info['displayName']?.toString() ?? 'Ẩn danh';
                            final role = info['role']?.toString() ?? 'member';
                            final photoUrl = info['photoURL']?.toString() ?? '';
                            final roleColor = role == 'leader'
                                ? Colors.blue
                                : role == 'sweeper'
                                    ? Colors.green
                                    : Colors.orange;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                                    backgroundColor: roleColor.withValues(alpha: 0.15),
                                    child: photoUrl.isEmpty
                                        ? Text(
                                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: roleColor),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: roleColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      role.toUpperCase(),
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: roleColor),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Divider(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final snapshot = _captureNavSnapshot();
                                if (snapshot != null) unawaited(_saveTripFromSnapshot(snapshot));
                                widget.onLeaveRoom();
                              },
                              icon: const Icon(Icons.logout, size: 15, color: Colors.red),
                              label: const Text(
                                'Thoát phòng',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: _panelWidth - _panelHandleWidth,
                  top: 0,
                  bottom: 0,
                  width: _panelHandleWidth,
                  child: GestureDetector(
                    onTap: () => setState(() => _panelOpen = !_panelOpen),
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v > 150) { setState(() => _panelOpen = true); }
                      else if (v < -150) { setState(() => _panelOpen = false); }
                    },
                    behavior: HitTestBehavior.translucent,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 6,
                        height: 48,
                        margin: const EdgeInsets.only(left: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[500],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
            _GroupBottomCard(
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
                      itemBuilder: (_, i) => _GroupWaypointTile(
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
                          label: const Text('Bắt đầu', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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

          if (mapProvider.availableRoutes.isNotEmpty && !_isLoading && !mapProvider.isNavigating &&
              widget.currentUser.role == UserRole.leader)
            _GroupBottomCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildGroupRouteInfo(mapProvider),
                  if (_waypoints.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _waypoints.length,
                      itemBuilder: (_, i) => _GroupWaypointTile(
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
                    onPressed: () => _startGroupNavigation(mapProvider),
                    icon: const Icon(Icons.two_wheeler, color: Colors.white),
                    label: const Text('Bắt đầu',
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
                          final provider = context.read<MapStateProvider>();
                          await provider.clearAll(keepMemberMarkers: true);
                          provider.clearRoutes();
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

          if (mapProvider.isNavigating)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.currentUser.role == UserRole.leader) ...[
                          FloatingActionButton.small(
                            heroTag: 'grp_add_wp_nav_fab',
                            onPressed: _showWaypointSearchSheet,
                            backgroundColor: Colors.blue,
                            child: const Icon(Icons.add_location_alt, color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 6),
                        ],
                        FloatingActionButton.small(
                          heroTag: 'grp_stop_nav_fab',
                          onPressed: () async {
                            _riskRefreshTimer?.cancel();
                            await context.read<MapStateProvider>().clearAll(keepMemberMarkers: true);
                            mapProvider.clearRoutes();
                            _arrivedNotified = false;
                            _arrivedMemberUids.clear();
                            _announcedRiskIds.clear();
                            _lastRiskCheckMs = 0;
                            setState(() {
                              _lastDestPos = null;
                              _destPos = null;
                              _polylineData = [];
                              _waypoints = [];
                              _addingWaypointByMap = false;
                              _loadedRouteKey = null;
                            });
                          },
                          backgroundColor: Colors.redAccent,
                          child: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          if (widget.currentUser.role == UserRole.leader ||
              widget.currentUser.role == UserRole.sweeper)
            Positioned(
              top: 144.0 +
                  (mapProvider.isNavigating ? 50.0 : 0.0) +
                  ((!mapProvider.isNavigating || !mapProvider.isFollowing) ? 50.0 : 0.0) +
                  50.0,
              right: 16,
              child: GestureDetector(
                onTap: _showQuickMessageSheet,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: const Icon(Icons.campaign, color: Colors.blue, size: 20),
                ),
              ),
            ),

          if (widget.currentUser.role == UserRole.leader ||
              widget.currentUser.role == UserRole.sweeper)
            Positioned(
              top: 144.0 +
                  (mapProvider.isNavigating ? 50.0 : 0.0) +
                  ((!mapProvider.isNavigating || !mapProvider.isFollowing) ? 50.0 : 0.0),
              right: 16,
              child: GestureDetector(
                onTap: _toggleGroupStop,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _groupStopActive ? Colors.red : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: Icon(
                    Icons.stop_circle_outlined,
                    color: _groupStopActive ? Colors.white : Colors.red,
                    size: 20,
                  ),
                ),
              ),
            ),

          if (_groupStopActive)
            Positioned(
              top: 92,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stop_circle_outlined, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '$_groupStopLabel yêu cầu dừng đoàn',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (mapProvider.isNavigating)
            Positioned(
              top: 144,
              right: 16,
              child: GestureDetector(
                onTap: _handleRiskReport,
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
              top: mapProvider.isNavigating ? 194 : 144,
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
      ),
    );
  }
}

class _QuickMessageSheet extends StatefulWidget {
  final List<String> presets;
  final List<String> customs;
  final ValueChanged<String> onSend;
  final ValueChanged<List<String>> onCustomsChanged;

  const _QuickMessageSheet({
    required this.presets,
    required this.customs,
    required this.onSend,
    required this.onCustomsChanged,
  });

  @override
  State<_QuickMessageSheet> createState() => _QuickMessageSheetState();
}

class _QuickMessageSheetState extends State<_QuickMessageSheet> {
  late List<String> _customs;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _customs = List.from(widget.customs);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addCustom() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _customs.add(text));
    _controller.clear();
    widget.onCustomsChanged(_customs);
  }

  void _removeCustom(int index) {
    setState(() => _customs.removeAt(index));
    widget.onCustomsChanged(_customs);
  }

  Widget _msgTile(String text, {VoidCallback? onDelete}) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      title: Text(text, style: const TextStyle(fontSize: 14)),
      trailing: onDelete != null
          ? IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              onPressed: onDelete,
            )
          : null,
      onTap: () => widget.onSend(text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Gửi tin nhắn đến đoàn', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              children: [
                ...widget.presets.map((t) => _msgTile(t)),
                if (_customs.isNotEmpty) ...[
                  const Divider(height: 8, indent: 16, endIndent: 16),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text('Câu của bạn', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  ...List.generate(_customs.length, (i) => _msgTile(_customs[i], onDelete: () => _removeCustom(i))),
                ],
                const Divider(height: 16, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: 'Thêm câu mới...',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          onSubmitted: (_) => _addCustom(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _addCustom,
                        icon: const Icon(Icons.add_circle, color: Colors.blue, size: 28),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupWaypointTile extends StatelessWidget {
  final int index;
  final String name;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _GroupWaypointTile({
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

class _GroupBottomCard extends StatelessWidget {
  final Widget child;
  const _GroupBottomCard({required this.child});

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
