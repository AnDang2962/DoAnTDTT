import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SOSMapOverlay extends StatefulWidget {
  final double latitude;
  final double longitude;

  const SOSMapOverlay({
    super.key, 
    required this.latitude,
    required this.longitude,
  });

  @override
  State<SOSMapOverlay> createState() => _SOSMapOverlayState();
}

class _SOSMapOverlayState extends State<SOSMapOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _animation;

  // ĐÃ XÓA biến _mapboxMap thừa để dọn sạch cảnh báo vàng
  CircleAnnotationManager? _circleAnnotationManager;
  CircleAnnotation? _pulseCircle;

  @override
  void initState() {
    super.initState();
    
    // CẤU HÌNH BẢO MẬT: Load Token an toàn
    MapboxOptions.setAccessToken(
      const String.fromEnvironment('MAPBOX_ACCESS_TOKEN', defaultValue: 'YOUR_MAPBOX_TOKEN_HERE')
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    _pulseController.addListener(_updatePulsingCircle);
  }

  void _updatePulsingCircle() {
    if (_circleAnnotationManager != null && _pulseCircle != null) {
      final double currentRadius = 150 * _animation.value;
      final double currentAlpha = 0.5 * (1.0 - _animation.value);

      _pulseCircle?.circleRadius = currentRadius;
      _pulseCircle?.circleOpacity = currentAlpha;
      
      _circleAnnotationManager?.update(_pulseCircle!);
    }
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();

    // 1. Dấu chấm đỏ tâm vị trí nạn nhân
    await _circleAnnotationManager!.create(CircleAnnotationOptions(
      // ĐÃ SỬA: Bỏ .toJson() để hết lỗi đỏ
      geometry: Point(coordinates: Position(widget.longitude, widget.latitude)),
      circleRadius: 12.0,
      // ĐÃ SỬA: Dùng mã Hex trực tiếp thay cho Colors.red.value để hết cảnh báo xanh
      circleColor: 0xFFFF0000, 
      circleStrokeColor: 0xFFFFFFFF,
      circleStrokeWidth: 3.0,
    ));

    // 2. Vòng tròn nhấp nháy 
    _pulseCircle = await _circleAnnotationManager!.create(CircleAnnotationOptions(
      // ĐÃ SỬA: Bỏ .toJson()
      geometry: Point(coordinates: Position(widget.longitude, widget.latitude)),
      circleRadius: 0.0,
      circleColor: 0xFFFF0000,
      circleOpacity: 0.5,
      circleStrokeWidth: 0.0,
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _launchGoogleMapsNavigation() async {
    final double lat = widget.latitude;
    final double lng = widget.longitude;
    
    final Uri googleMapsUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng?daddr=$lat,$lng');

    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Không thể mở Google Maps. Có thể máy chưa cài app.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // LỚP DƯỚI: Bản đồ Mapbox
        MapWidget(
          viewport: CameraViewportState(
            center: Point(coordinates: Position(widget.longitude, widget.latitude)),
            zoom: 16.5,
          ),
          onMapCreated: _onMapCreated,
        ),

        // LỚP TRÊN: Nút bấm Dẫn đường khẩn cấp
        Positioned(
          bottom: 40,
          left: 20,
          right: 20,
          child: ElevatedButton.icon(
            onPressed: _launchGoogleMapsNavigation,
            icon: const Icon(Icons.navigation, color: Colors.white, size: 28),
            label: const Text(
              "DẪN ĐƯỜNG ĐẾN NẠN NHÂN",
              style: TextStyle(
                color: Colors.white, 
                fontSize: 16, 
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 10,
              shadowColor: Colors.red.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
      ],
    );
  }
}