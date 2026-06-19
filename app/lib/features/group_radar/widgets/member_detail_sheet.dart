import 'package:flutter/material.dart';
import '../../../core/utils/badge_helper.dart';

class MemberDetailSheet extends StatelessWidget {
  final String name;
  final String role;
  final String photoUrl;
  final String email;
  final String phoneNumber;
  final double? distanceKm;
  final double? totalKm;

  const MemberDetailSheet({
    super.key,
    required this.name,
    required this.role,
    this.photoUrl = '',
    this.email = '',
    this.phoneNumber = '',
    this.distanceKm,
    this.totalKm,
  });

  static Future<void> show(
    BuildContext context, {
    required String name,
    required String role,
    String photoUrl = '',
    String email = '',
    String phoneNumber = '',
    double? distanceKm,
    double? totalKm,
  }) {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MemberDetailSheet(
        name: name,
        role: role,
        photoUrl: photoUrl,
        email: email,
        phoneNumber: phoneNumber,
        distanceKm: distanceKm,
        totalKm: totalKm,
      ),
    );
  }

  String _roleLabel() {
    switch (role) {
      case 'leader': return 'Leader';
      case 'sweeper': return 'Chốt đoàn';
      default: return 'Thành viên';
    }
  }

  String _distanceText() {
    if (distanceKm == null) return 'Không xác định';
    if (distanceKm! < 0.05) return 'Gần bạn';
    if (distanceKm! < 1.0) return '${(distanceKm! * 1000).round()} m';
    return '${distanceKm!.toStringAsFixed(1)} km';
  }

  Widget _buildAvatar(Color ringColor, Color roleColor) {
    final hasPhoto = photoUrl.isNotEmpty;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2.5),
      ),
      child: ClipOval(
        child: hasPhoto
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, st) => _fallbackAvatar(roleColor),
              )
            : _fallbackAvatar(roleColor),
      ),
    );
  }

  Widget _fallbackAvatar(Color roleColor) {
    return Container(
      color: roleColor.withValues(alpha: 0.12),
      child: Center(
        child: Text(
          BadgeHelper.roleLabel(role),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: roleColor),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color color, {bool muted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(fontSize: 14, color: Colors.grey)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: muted ? Colors.grey : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ringColor = BadgeHelper.ringColor(totalKm);
    final roleColor = BadgeHelper.roleRingColor(role);
    final tierName = BadgeHelper.tierName(totalKm);
    final tierEmoji = BadgeHelper.badgeEmoji(totalKm);
    final phone = phoneNumber.isEmpty ? 'Chưa cập nhật' : phoneNumber;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildAvatar(ringColor, roleColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _roleLabel(),
                            style: TextStyle(fontSize: 12, color: roleColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: ringColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: ringColor.withValues(alpha: 0.4), width: 1),
                          ),
                          child: Text(
                            '$tierEmoji $tierName',
                            style: TextStyle(fontSize: 12, color: ringColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (email.isNotEmpty) _infoRow(Icons.email_outlined, 'Email', email, ringColor),
          _infoRow(Icons.phone_outlined, 'Số điện thoại', phone, ringColor, muted: phoneNumber.isEmpty),
          _infoRow(Icons.social_distance, 'Khoảng cách', _distanceText(), ringColor),
        ],
      ),
    );
  }
}
