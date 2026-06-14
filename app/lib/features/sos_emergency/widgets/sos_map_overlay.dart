import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SOSMapOverlay extends StatefulWidget {
  final double latitude;
  final double longitude;
  final VoidCallback? onNavigateToVictim;

  const SOSMapOverlay({
    super.key,
    required this.latitude,
    required this.longitude,
    this.onNavigateToVictim,
  });

  @override
  State<SOSMapOverlay> createState() => _SOSMapOverlayState();
}

class _SOSMapOverlayState extends State<SOSMapOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _animation;

  CircleAnnotationManager? _circleAnnotationManager;
  CircleAnnotation? _pulseCircle;

  @override
  void initState() {
    super.initState();
    
    final String mapboxToken = dotenv.env['MAPBOX_PUBLIC_KEY'] ?? '';
    MapboxOptions.setAccessToken(mapboxToken);

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
    await _circleAnnotationManager!.create(CircleAnnotationOptions(
      geometry: Point(coordinates: Position(widget.longitude, widget.latitude)),
      circleRadius: 12.0,
      circleColor: 0xFFFF0000,
      circleStrokeColor: 0xFFFFFFFF,
      circleStrokeWidth: 3.0,
    ));
    _pulseCircle = await _circleAnnotationManager!.create(CircleAnnotationOptions(
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

  void _handleNavigate() {
    Navigator.of(context).pop();
    widget.onNavigateToVictim!();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VỊ TRÍ NẠN NHÂN'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // LỚP DƯỚI: Bản đồ Mapbox
          MapWidget(
            styleUri: MapboxStyles.MAPBOX_STREETS,
            viewport: CameraViewportState(
              center: Point(coordinates: Position(widget.longitude, widget.latitude)),
              zoom: 16.5,
            ),
            onMapCreated: _onMapCreated,
          ),

          if (widget.onNavigateToVictim != null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: ElevatedButton.icon(
                onPressed: _handleNavigate,
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
      ),
    );
  }
}