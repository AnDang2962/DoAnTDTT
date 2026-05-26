import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../providers/members_provider.dart';
import '../../widgets/radar_info_panel.dart';
import '../../widgets/radar_warning_banner.dart';

class RadarPage extends StatefulWidget {
  final String roomId;
  final String currentUserId;
  final String selectedRole;

  const RadarPage({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.selectedRole,
  });

  @override
  State<RadarPage> createState() => _RadarPageState();
}

class _RadarPageState extends State<RadarPage> {
  // Mapbox token (replace with your token or use tile provider from project)
  String mapboxAccessToken = dotenv.env['MAPBOX_PUBLIC_KEY'] ?? '';

  // Vị trí mặc định
  static const LatLng initialCenter = LatLng(10.762622, 106.681043);
  static const double initialZoom = 15.0;

  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MembersProvider>().initialize(
        roomId: widget.roomId,
        userId: widget.currentUserId,
        role: widget.selectedRole,
      );
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<MembersProvider>(
          builder: (context, provider, _) {
            return Text(
              'Phòng: ${widget.roomId} (${provider.totalMembers} người)',
              style: const TextStyle(fontSize: 16),
            );
          },
        ),
      ),
      body: Consumer<MembersProvider>(
        builder: (context, provider, _) {
          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: initialCenter,
                  initialZoom: initialZoom,
                  minZoom: 10.0,
                  maxZoom: 18.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token={accessToken}',
                    additionalOptions: {'accessToken': mapboxAccessToken},
                    userAgentPackageName: 'doan_tdtt',
                  ),

                  if (provider.safeCircle != null)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: provider.safeCircle!.center,
                          radius: provider.safeCircle!.radiusMeters,
                          useRadiusInMeter: true,
                          color: Colors.blue.withOpacity(0.15),
                          borderColor: Colors.blue.withOpacity(0.6),
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),

                  MarkerLayer(markers: _buildMarkers(provider)),
                ],
              ),

              const RadarWarningBanner(),
              const RadarInfoPanel(),

              if (provider.isLoading)
                const Center(child: CircularProgressIndicator()),
            ],
          );
        },
      ),
    );
  }

  List<Marker> _buildMarkers(MembersProvider provider) {
    return provider.members.values.map((member) {
      final role = member.role;
      final isLost = provider.alert.lostMembers.contains(member.id);

      final color = role == 'Leader'
          ? Colors.blue
          : role == 'Sweeper'
          ? Colors.green
          : isLost
          ? Colors.red
          : Colors.orange;

      return Marker(
        point: member.location,
        width: 120,
        height: 80,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4),
                ],
              ),
              child: Text(
                member.id,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),

            Icon(Icons.location_on, color: color, size: 36),
          ],
        ),
      );
    }).toList();
  }
}
