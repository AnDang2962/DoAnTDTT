import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../../core/utils/geo_utils.dart';

class GroupStatusSheet extends StatelessWidget {
  final Map<String, mapbox.Position> memberLocations;
  final Map<String, dynamic> memberInfo;
  final String currentUserId;
  final bool isTooFar;
  final List<Map<String, dynamic>> gapDetails;
  final List<Map<String, dynamic>> offRouteWarnings;

  const GroupStatusSheet({
    super.key,
    required this.memberLocations,
    required this.memberInfo,
    required this.currentUserId,
    this.isTooFar = false,
    this.gapDetails = const [],
    this.offRouteWarnings = const [],
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, mapbox.Position> memberLocations,
    required Map<String, dynamic> memberInfo,
    required String currentUserId,
    bool isTooFar = false,
    List<Map<String, dynamic>> gapDetails = const [],
    List<Map<String, dynamic>> offRouteWarnings = const [],
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GroupStatusSheet(
        memberLocations: memberLocations,
        memberInfo: memberInfo,
        currentUserId: currentUserId,
        isTooFar: isTooFar,
        gapDetails: gapDetails,
        offRouteWarnings: offRouteWarnings,
      ),
    );
  }

  double? _distanceFromMe(mapbox.Position myPos, mapbox.Position other) {
    return calculateDistanceMeters(
      startLat: myPos.lat.toDouble(),
      startLng: myPos.lng.toDouble(),
      endLat: other.lat.toDouble(),
      endLng: other.lng.toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myPos = memberLocations[currentUserId];
    final members = memberLocations.entries.toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Đoàn (${members.length} thành viên)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isTooFar ? Colors.red[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isTooFar ? Colors.red[300]! : Colors.green[300]!,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isTooFar ? Icons.gpp_bad : Icons.verified_user,
                        color: isTooFar ? Colors.red[700] : Colors.green[700],
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isTooFar ? 'Đội hình đứt đoạn' : 'Đội hình ổn định',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isTooFar ? Colors.red[700] : Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                  if (isTooFar) ...[
                    const SizedBox(height: 6),
                    ...gapDetails.map((g) {
                      final uid = g['memberId']?.toString() ?? '';
                      final name = (memberInfo[uid] as Map?)?['displayName']?.toString() ?? uid.substring(0, 6);
                      final km = (g['distanceKm'] as num?)?.toStringAsFixed(1) ?? '?';
                      return Text('• $name tụt hậu $km km',
                          style: TextStyle(fontSize: 13, color: Colors.red[700]));
                    }),
                    ...offRouteWarnings.map((w) {
                      final uid = w['memberId']?.toString() ?? '';
                      final name = (memberInfo[uid] as Map?)?['displayName']?.toString() ?? uid.substring(0, 6);
                      return Text('• $name đã lệch tuyến đường',
                          style: TextStyle(fontSize: 13, color: Colors.red[700]));
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: members.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final uid = members[i].key;
                final pos = members[i].value;
                final info = memberInfo[uid] as Map? ?? {};
                final name = info['displayName']?.toString() ?? uid.substring(0, 6);
                final role = info['role']?.toString() ?? 'member';
                final isMe = uid == currentUserId;

                double? distM;
                if (!isMe && myPos != null) distM = _distanceFromMe(myPos, pos);

                String distLabel = '';
                if (isMe) {
                  distLabel = 'Vị trí của bạn';
                } else if (distM != null) {
                  distLabel = distM < 1000
                      ? '${distM.toStringAsFixed(0)} m'
                      : '${(distM / 1000).toStringAsFixed(1)} km';
                }

                IconData roleIcon = Icons.person;
                if (role == 'leader') roleIcon = Icons.star;
                if (role == 'sweeper') roleIcon = Icons.last_page;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isMe ? Colors.blue[100] : Colors.grey[200],
                    child: Icon(roleIcon, color: isMe ? Colors.blue : Colors.grey[600]),
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(_roleLabel(role)),
                  trailing: distLabel.isNotEmpty
                      ? Text(distLabel, style: const TextStyle(color: Colors.grey))
                      : null,
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom +
                  MediaQuery.of(context).padding.bottom +
                  16,
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'leader': return 'Trưởng đoàn';
      case 'sweeper': return 'Người quét hậu';
      default: return 'Thành viên';
    }
  }
}
