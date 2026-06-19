import 'package:flutter/material.dart';
import '../../../data/models/warning_marker.dart';

class MarkerDetailSheet extends StatelessWidget {
  final WarningMarker marker;

  const MarkerDetailSheet({super.key, required this.marker});

  static Future<void> show(BuildContext context, WarningMarker marker) {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MarkerDetailSheet(marker: marker),
    );
  }

  String _ageText() {
    final h = marker.ageHours;
    if (h < 1) return 'Vừa báo cáo';
    if (h < 24) return '${h.floor()} giờ trước';
    return '${(h / 24).floor()} ngày trước';
  }

  String _categoryName() {
    switch (marker.category) {
      case 'WEATHER': return 'Thời tiết';
      case 'ACCIDENT': return 'Tai nạn / Giao thông';
      case 'ROAD_BAD': return 'Đường xấu';
      case 'POLICE': return 'CSGT';
      case 'HAZARD_OTHER': return 'Nguy hiểm khác';
      default: return marker.category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = marker.color;
    final isWeather = marker.category == 'WEATHER';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
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

          // Header: emoji + tên + badge danh mục
          Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(marker.emoji, style: const TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      marker.vi,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _categoryName(),
                        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Chi tiết
          if (marker.note.isNotEmpty) ...[
            _InfoRow(icon: Icons.notes, label: 'Ghi chú', value: marker.note, color: color),
            const SizedBox(height: 10),
          ],

          if (isWeather && marker.progressKm > 0) ...[
            _InfoRow(
              icon: Icons.route,
              label: 'Vị trí trên lộ trình',
              value: 'km ${marker.progressKm.toStringAsFixed(0)}',
              color: color,
            ),
            const SizedBox(height: 10),
          ],

          if (!isWeather) ...[
            _InfoRow(
              icon: Icons.access_time,
              label: 'Thời gian báo cáo',
              value: _ageText(),
              color: color,
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.bar_chart,
              label: 'Mức độ nghiêm trọng',
              value: _severityText(),
              color: color,
            ),
          ],
        ],
      ),
    );
  }

  String _severityText() {
    if (marker.severity >= 0.8) return 'Rất nguy hiểm';
    if (marker.severity >= 0.6) return 'Nguy hiểm';
    if (marker.severity >= 0.4) return 'Trung bình';
    return 'Nhẹ';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoRow({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text('$label: ', style: const TextStyle(fontSize: 14, color: Colors.grey)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
