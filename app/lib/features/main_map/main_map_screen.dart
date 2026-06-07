import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'providers/map_state_provider.dart';
import '../../../core/constants/env_keys.dart';

class MainMapScreen extends StatefulWidget {
  final mapbox.Position? initialCenter;

  const MainMapScreen({super.key, this.initialCenter});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  mapbox.Position? _initPos;
  bool _posChecked = false;

  @override
  void initState() {
    super.initState();
    mapbox.MapboxOptions.setAccessToken(EnvKeys.mapboxPublicKey);
    _resolveInitialPosition();
  }

  // Lấy vị trí cached (instant) trước khi render map để tránh flash về Nha Trang
  Future<void> _resolveInitialPosition() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        setState(() {
          _initPos = mapbox.Position(pos.longitude, pos.latitude);
          _posChecked = true;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _posChecked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_posChecked) return const SizedBox.expand();

    final center = _initPos
        ?? widget.initialCenter
        ?? mapbox.Position(109.1967, 12.2388);

    return mapbox.MapWidget(
      cameraOptions: mapbox.CameraOptions(
        center: mapbox.Point(coordinates: center),
        zoom: 14.0,
      ),
      styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
      onScrollListener: (_) {
        context.read<MapStateProvider>().setFollowing(false);
      },
      onTapListener: (gestureContext) {
        final coords = gestureContext.point.coordinates;
        context.read<MapStateProvider>().notifyMapTap(
          mapbox.Position(coords.lng.toDouble(), coords.lat.toDouble()),
        );
      },
      onMapCreated: (mapboxMap) {
        mapboxMap.location.updateSettings(
          mapbox.LocationComponentSettings(enabled: true, pulsingEnabled: true),
        );
        mapboxMap.compass.updateSettings(
          mapbox.CompassSettings(
            position: mapbox.OrnamentPosition.TOP_RIGHT,
            marginTop: 90,
            marginRight: 16,
          ),
        );
        context.read<MapStateProvider>().onMapCreated(mapboxMap);
      },
    );
  }
}
