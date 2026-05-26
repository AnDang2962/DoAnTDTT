import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'providers/map_state_provider.dart';

import '../map_routing/screens/routing_panel.dart';
import '../../../core/constants/env_keys.dart'; // Bắt buộc phải có dòng này để lấy Key

class MainMapScreen extends StatefulWidget {
  final mapbox.Position? initialCenter;

  const MainMapScreen({super.key, this.initialCenter});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  @override
  void initState() {
    super.initState();
    // 1. Cung cấp Token cho hệ thống Mapbox ngay khi màn hình vừa mở lên!
    // Sử dụng đúng EnvKeys.mapboxPublicKey của bạn:
    mapbox.MapboxOptions.setAccessToken(EnvKeys.mapboxPublicKey);
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 Chỉ trả về lõi Bản đồ, không chứa UI gì khác
    return mapbox.MapWidget(
      cameraOptions: mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates:
              widget.initialCenter ?? mapbox.Position(109.1967, 12.2388),
        ),
        zoom: 14.0,
      ),
      styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
      onMapCreated: (mapboxMap) {
        mapboxMap.location.updateSettings(
          mapbox.LocationComponentSettings(enabled: true, pulsingEnabled: true),
        );
        mapboxMap.compass.updateSettings(
          mapbox.CompassSettings(
            position: mapbox.OrnamentPosition.BOTTOM_RIGHT,
            marginBottom: 120,
            marginRight: 16,
          ),
        );
        context.read<MapStateProvider>().onMapCreated(mapboxMap);
      },
    );
  }
}
