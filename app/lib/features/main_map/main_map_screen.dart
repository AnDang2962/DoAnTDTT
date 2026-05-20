import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'providers/map_state_provider.dart';

import '../map_routing/screens/routing_panel.dart'; 
import '../../../core/constants/env_keys.dart'; // Bắt buộc phải có dòng này để lấy Key

class MainMapScreen extends StatefulWidget {
  final mapbox.Position? initialCenter;
  
  const MainMapScreen({Key? key, this.initialCenter}) : super(key: key);

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
    return Scaffold(
      body: Stack(
        children: [
          // Ép bản đồ bung full màn hình
          Positioned.fill(
            child: mapbox.MapWidget(
              // 2. Đã xóa dòng resourceOptions gây lỗi ở đây!
              cameraOptions: mapbox.CameraOptions(
                center: mapbox.Point(
                  // Tọa độ Nha Trang
                  coordinates: widget.initialCenter ?? mapbox.Position(109.1967, 12.2388),
                ),
                zoom: 14.0,
              ),
              styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
              onMapCreated: (mapboxMap) {
                // 1. Lệnh bật dấu chấm xanh (Location Puck) hiển thị vị trí người dùng
                mapboxMap.location.updateSettings(
                  mapbox.LocationComponentSettings(
                    enabled: true, // Bật chấm xanh
                    pulsingEnabled: true, // Bật hiệu ứng sóng tỏa ra cho ngầu
                  ),
                );
                mapboxMap.compass.updateSettings(
                  mapbox.CompassSettings(
                    position: mapbox.OrnamentPosition.BOTTOM_RIGHT,
                    marginBottom: 120, // Nâng lên 1 xíu để không bị đè bởi UI
                    marginRight: 16,
                  )
                );
                context.read<MapStateProvider>().onMapCreated(mapboxMap);
              },
            ),
          ),

          // Lớp UI Overlay (Thanh search trên cùng, Nút bắt đầu dưới đáy)
          const SafeArea( 
            child: RoutingPanel(),
          ),
        ],
      ),
    );
  }
}