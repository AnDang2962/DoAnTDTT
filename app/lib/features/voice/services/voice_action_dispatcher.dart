import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/tts_service.dart';
import '../../../features/main_map/providers/map_state_provider.dart';
import '../../../features/sos_emergency/services/sos_service.dart';
import '../../../features/map_routing/services/places_api.dart';
import '../../../features/map_routing/widgets/nearby_places_modal.dart';
import '../../../features/map_routing/widgets/weather_detail_modal.dart';
import '../../../features/group_radar/widgets/group_status_sheet.dart';

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

  final _sos = SosService();
  final _tts = TtsService();

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
  });

  Future<void> dispatch(Map<String, dynamic> result) async {
    final type = result['type']?.toString() ?? 'command';
    final action = result['action']?.toString() ?? 'unknown';
    final params = result['params'] as Map<String, dynamic>? ?? {};
    final responseText = result['responseText']?.toString() ?? '';

    debugPrint('[VoiceDispatch] type=$type action=$action');

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
          await _handleSendSos(params, responseText);
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
        default:
          if (responseText.isNotEmpty) _showSnackbar(responseText);
          if (responseText.isNotEmpty) await _tts.speak(responseText);
      }
    } catch (e) {
      debugPrint('[VoiceDispatch] Lỗi: $e');
      _showSnackbar('Có lỗi xảy ra khi thực hiện yêu cầu.');
    }
  }

  Future<void> _handleSendSos(Map<String, dynamic> params, String responseText) async {
    if (!isInGroup) {
      _showSnackbar('Đang gọi 113...');
      await _tts.speak('Đang gọi một một ba, giữ bình tĩnh.');
      await launchUrl(Uri.parse('tel:113'));
      return;
    }
    _showSnackbar('Đang phát tín hiệu SOS...');
    await _tts.speak('Đang gửi SOS đến nhóm.');
    await _sos.sendEmergencySignal(
      roomId: roomId,
      onStatusUpdate: (msg, _) => _showSnackbar(msg),
    );
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
    final summary = warnings.isEmpty
        ? 'Chưa có dữ liệu thời tiết trên lộ trình.'
        : 'Có ${warnings.length} điểm thời tiết. '
          '${warnings.any((w) => w.subtype == "storm" || w.subtype == "rain") ? "Cảnh báo có mưa hoặc bão trên đường." : "Thời tiết ổn định."}';

    if (!context.mounted) return;
    unawaited(_tts.speak(responseText.isNotEmpty ? responseText : summary));
    await WeatherDetailModal.show(context, warnings);
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
    final ttsText = responseText.isNotEmpty
        ? responseText
        : 'Nhóm có ${memberLocations.length} thành viên.';
    unawaited(_tts.speak(ttsText));
    await GroupStatusSheet.show(
      context,
      memberLocations: memberLocations,
      memberInfo: memberInfo,
      currentUserId: currentUserId,
    );
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
    );
  }

  void _showSnackbar(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
