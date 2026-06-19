import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/services/tts_service.dart';
import '../../../features/main_map/providers/map_state_provider.dart';
import '../../../features/sos_emergency/services/sos_service.dart';
import '../../../features/map_routing/services/places_api.dart';
import '../../../features/map_routing/widgets/nearby_places_modal.dart';
import '../../../features/map_routing/widgets/weather_detail_modal.dart';
import '../../../features/group_radar/widgets/group_status_sheet.dart';
import '../../../data/models/warning_marker.dart';
import '../../../features/group_radar/presentation/providers/members_provider.dart';

typedef OnNavigateTo = Future<void> Function(mapbox.Position dest, String name);

class VoiceActionDispatcher {
  final BuildContext context;
  final bool isInGroup;
  final String roomId;
  final double? currentLat;
  final double? currentLng;
  final Map<String, mapbox.Position> memberLocations;
  final Map<String, dynamic> memberInfo;
  final String currentUserId;
  final OnNavigateTo? onNavigateTo;
  final void Function(mapbox.Position pos, String name)? onAddWaypoint;
  final Future<void> Function(String message)? onGroupBroadcast;
  final bool isTooFar;
  final List<Map<String, dynamic>> gapDetails;
  final List<Map<String, dynamic>> offRouteWarnings;

  final _sos = SosService();
  final _tts = TtsService();
  bool _isSending = false;
  _SosPendingCallObserver? _pendingCallObserver;

  VoiceActionDispatcher({
    required this.context,
    required this.isInGroup,
    required this.roomId,
    this.currentLat,
    this.currentLng,
    this.memberLocations = const {},
    this.memberInfo = const {},
    this.currentUserId = '',
    this.onNavigateTo,
    this.onAddWaypoint,
    this.onGroupBroadcast,
    this.isTooFar = false,
    this.gapDetails = const [],
    this.offRouteWarnings = const [],
  });

  Future<void> dispatch(Map<String, dynamic> result) async {
    final type = result['type']?.toString() ?? 'command';
    final action = result['action']?.toString() ?? 'unknown';
    final params = result['params'] as Map<String, dynamic>? ?? {};
    final responseText = result['responseText']?.toString() ?? '';

    try {
      if (type == 'risk') {
        final vi = result['vi']?.toString() ?? 'sự cố';
        final autoSaved = result['autoSaved'] == true;
        _showSnackbar(autoSaved ? 'Đã ghi nhận: $vi' : 'Phát hiện: $vi (chưa lưu)');
        if (responseText.isNotEmpty) await _tts.speak(responseText);
        return;
      }

      switch (action) {
        case 'send_sos':
          await _handleSendSos();
          break;
        case 'check_weather':
          await _handleCheckWeather(responseText);
          break;
        case 'check_group_status':
          await _handleCheckGroupStatus(responseText);
          break;
        case 'recommend_rest':
          await _handleFindNearby(
            placeType: 'rest_stop',
            radiusKm: 5.0,
            modalTitle: 'Khuyến nghị nghỉ ngơi',
            responseText: responseText,
          );
          break;
        case 'find_nearby_place':
          await _handleFindNearby(
            placeType: params['place_type']?.toString() ?? 'restaurant',
            radiusKm: (params['radius_km'] as num?)?.toDouble() ?? 5.0,
            modalTitle: _nearbyTitle(params['place_type']?.toString()),
            responseText: responseText,
          );
          break;
        case 'group_broadcast':
          final message = params['message']?.toString() ?? '';
          if (message.isEmpty) break;
          if (onGroupBroadcast == null) {
            _showSnackbar('Tính năng thông báo chỉ dành cho Leader và Chốt đoàn');
            break;
          }
          await onGroupBroadcast!(message);
          _showSnackbar('📢 Đã gửi: $message');
          await _tts.speak(message.replaceAll(RegExp(r'[^\p{L}\p{N}\s,.!?]', unicode: true), '').trim());
          break;
        default:
          if (responseText.isNotEmpty) {
            _showSnackbar(responseText);
            await _tts.speak(responseText);
          }
      }
    } catch (_) {
      _showSnackbar('Có lỗi xảy ra khi thực hiện yêu cầu.');
    }
  }

  Future<void> _handleSendSos() async {
    if (_isSending) return;
    _isSending = true;
    try {
      final data = await _sos.collectEmergencyData();

      if (!isInGroup) {
        _showSnackbar('Đang liên hệ khẩn cấp...');
        await _tts.speak('Đang gọi cứu hộ, giữ bình tĩnh.');
        final contacts = await _getEmergencyContacts();
        final smsContacts = contacts.isNotEmpty ? contacts : [SosService.fallbackEmergencyContact];
        final phone = smsContacts.first;
        await _sos.makeCall(phone);
        _callOnResume(() => _sos.openEmergencySms(data, smsContacts));
        return;
      }

      final String leaderPhone = Provider.of<MembersProvider>(context, listen: false).leaderPhoneNumber ?? '';
      _showSnackbar('Đang thu thập tọa độ và phát tín hiệu...', color: Colors.blue);
      await _tts.speak('Đang gửi SOS đến nhóm.');
      await _sos.sendGroupFcmNotification(
        roomId: roomId,
        data: data,
        onStatusUpdate: (msg, color) => _showSnackbar(msg, color: color),
      );
      if (leaderPhone.isNotEmpty) {
        await _sos.makeCall(leaderPhone);
        _callOnResume(() => _sos.openEmergencySms(data, [leaderPhone]));
      }
    } finally {
      _isSending = false;
    }
  }

  Future<List<String>> _getEmergencyContacts() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return [];
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final contacts = doc.data()?['emergencyContacts'];
      if (contacts is List) {
        return contacts.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (e) {
      debugPrint('Lỗi lấy emergency contacts: $e');
    }
    return [];
  }

  void _callOnResume(VoidCallback action) {
    if (_pendingCallObserver != null) {
      WidgetsBinding.instance.removeObserver(_pendingCallObserver!);
      _pendingCallObserver = null;
    }
    late _SosPendingCallObserver obs;
    obs = _SosPendingCallObserver(onResume: () {
      WidgetsBinding.instance.removeObserver(obs);
      _pendingCallObserver = null;
      action();
    });
    _pendingCallObserver = obs;
    WidgetsBinding.instance.addObserver(obs);
  }

  Future<void> _handleCheckWeather(String responseText) async {
    if (!context.mounted) return;
    final mapProvider = context.read<MapStateProvider>();

    if (!mapProvider.isNavigating && mapProvider.weatherWarnings.isEmpty) {
      _showSnackbar('Vui lòng chọn điểm đến và bắt đầu điều hướng trước.');
      await _tts.speak('Vui lòng chọn điểm đến trước.');
      return;
    }

    final warnings = mapProvider.weatherWarnings;
    final ttsText = await _buildWeatherTTS(warnings);

    if (!context.mounted) return;
    unawaited(_tts.speak(ttsText));
    await WeatherDetailModal.show(context, warnings);
  }

  Future<String> _buildWeatherTTS(List<WarningMarker> warnings) async {
    if (warnings.isEmpty) return 'Thời tiết dọc tuyến ổn định, không có cảnh báo.';

    final parts = <String>[];
    for (int i = 0; i < warnings.length; i++) {
      final w = warnings[i];
      if (w.subtype != 'storm' && w.subtype != 'rain' && w.subtype != 'fog') continue;
      final locationName = await _reverseGeocode(w.lat, w.lng);
      final location = locationName.isNotEmpty
          ? 'tại $locationName'
          : 'tại km ${w.progressKm > 0 ? w.progressKm.toInt() : (i + 1) * 50}';
      parts.add('$location ${_subtypeToTTS(w.subtype)}');
    }
    if (parts.isEmpty) return 'Thời tiết dọc tuyến ổn định.';
    return 'Cảnh báo thời tiết: ${parts.join(", ")}.';
  }

  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final token = dotenv.env['MAPBOX_PUBLIC_KEY'] ?? '';
      if (token.isEmpty) return '';
      final uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json'
        '?types=place,district,locality&language=vi&access_token=$token',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return '';
      final data = json.decode(res.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return '';
      return features.first['text']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  String _subtypeToTTS(String subtype) {
    const map = {
      'storm': 'có bão',
      'rain': 'đang mưa',
      'fog': 'có sương mù',
      'snow': 'có tuyết',
      'cloudy': 'nhiều mây',
      'sunny': 'nắng đẹp',
    };
    return map[subtype] ?? 'thời tiết bất thường';
  }

  Future<void> _handleCheckGroupStatus(String responseText) async {
    if (!context.mounted) return;

    if (!isInGroup || memberLocations.isEmpty) {
      _showSnackbar('Bạn đang đi một mình.');
      await _tts.speak('Bạn đang đi một mình.');
      return;
    }

    context.read<MapStateProvider>().fitBoundsToPositions(memberLocations.values.toList());

    if (!context.mounted) return;
    final ttsText = _buildGroupStatusTTS();
    unawaited(_tts.speak(ttsText));
    await GroupStatusSheet.show(
      context,
      memberLocations: memberLocations,
      memberInfo: memberInfo,
      currentUserId: currentUserId,
      isTooFar: isTooFar,
      gapDetails: gapDetails,
      offRouteWarnings: offRouteWarnings,
    );
  }

  String _buildGroupStatusTTS() {
    final count = memberLocations.length;
    if (!isTooFar && offRouteWarnings.isEmpty) {
      return 'Đội hình ổn định, có $count thành viên.';
    }
    final parts = <String>[];
    for (final g in gapDetails) {
      final uid = g['memberId']?.toString() ?? '';
      final name = (memberInfo[uid] as Map?)?['displayName']?.toString()
          ?? (uid.length >= 6 ? uid.substring(0, 6) : uid);
      final km = (g['distanceKm'] as num?)?.toStringAsFixed(1) ?? '?';
      parts.add('$name tụt hậu $km ki lô mét');
    }
    for (final w in offRouteWarnings) {
      final uid = w['memberId']?.toString() ?? '';
      final name = (memberInfo[uid] as Map?)?['displayName']?.toString()
          ?? (uid.length >= 6 ? uid.substring(0, 6) : uid);
      parts.add('$name đã lệch tuyến đường');
    }
    return 'Cảnh báo đội hình: ${parts.join(", ")}.';
  }

  Future<void> _handleFindNearby({
    required String placeType,
    required double radiusKm,
    required String modalTitle,
    required String responseText,
  }) async {
    if (!context.mounted) return;

    final lat = currentLat;
    final lng = currentLng;
    if (lat == null || lng == null) {
      _showSnackbar('Chưa lấy được vị trí GPS.');
      return;
    }

    _showSnackbar('Đang tìm kiếm...');

    final places = await PlacesApi.searchNearby(
      lat: lat,
      lng: lng,
      placeType: placeType,
      radiusKm: radiusKm,
    );

    if (!context.mounted) return;

    if (places.isEmpty) {
      _showSnackbar('Không tìm thấy ${_nearbyTitle(placeType)} trong ${radiusKm.toInt()} km.');
      await _tts.speak('Không tìm thấy địa điểm nào gần đây.');
      return;
    }

    final top = places.first;
    final tts = responseText.isNotEmpty
        ? responseText
        : 'Tìm thấy ${places.length} địa điểm. Gần nhất: ${top.name}, cách ${top.distanceKm} ki lô mét.';
    unawaited(_tts.speak(tts));
    await NearbyPlacesModal.show(
      context,
      places: places,
      title: modalTitle,
      onNavigateTo: (place) async {
        if (onNavigateTo != null) await onNavigateTo!(place.position, place.name);
      },
      onAddWaypoint: onAddWaypoint != null
          ? (place) => onAddWaypoint!(place.position, place.name)
          : null,
    );
  }

  void _showSnackbar(String message, {Color? color}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _nearbyTitle(String? placeType) {
    const titles = {
      'gas_station': 'Trạm xăng gần đây',
      'restaurant': 'Quán ăn gần đây',
      'hotel': 'Khách sạn gần đây',
      'rest_stop': 'Trạm dừng nghỉ gần đây',
      'hospital': 'Bệnh viện gần đây',
      'atm': 'ATM gần đây',
      'mechanic': 'Tiệm sửa xe gần đây',
    };
    return titles[placeType] ?? 'Địa điểm gần đây';
  }
}

class _SosPendingCallObserver with WidgetsBindingObserver {
  final VoidCallback onResume;
  _SosPendingCallObserver({required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
