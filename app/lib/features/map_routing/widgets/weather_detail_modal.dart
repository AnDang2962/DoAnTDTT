import 'package:flutter/material.dart';
import '../../../data/models/warning_marker.dart';

class WeatherDetailModal extends StatelessWidget {
  final List<WarningMarker> warnings;

  const WeatherDetailModal({super.key, required this.warnings});

  static Future<void> show(BuildContext context, List<WarningMarker> warnings) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => WeatherDetailModal(warnings: warnings),
    );
  }

  bool _isDangerous(WarningMarker w) =>
      w.subtype == 'storm' || w.subtype == 'rain' || w.subtype == 'fog';

  String _subtypeLabel(String subtype) {
    const labels = {
      'storm': 'Có bão',
      'rain': 'Đang mưa',
      'fog': 'Có sương mù',
      'snow': 'Có tuyết',
      'cloudy': 'Nhiều mây',
      'sunny': 'Nắng đẹp',
    };
    return labels[subtype] ?? 'Thời tiết khác';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
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
          const Text(
            'Thời tiết dọc lộ trình',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: warnings.isEmpty
                ? const Center(
                    child: Text(
                      'Chưa có dữ liệu thời tiết.\nHãy bắt đầu điều hướng trước.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: warnings.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final w = warnings[i];
                      final km = w.progressKm > 0 ? w.progressKm.toInt() : (i + 1) * 50;
                      final dangerous = _isDangerous(w);
                      return ListTile(
                        leading: Text(w.emoji, style: const TextStyle(fontSize: 28)),
                        title: Text(
                          'Km $km: ${_subtypeLabel(w.subtype)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: dangerous ? Colors.red[700] : Colors.black87,
                          ),
                        ),
                        subtitle: Text(w.vi, style: const TextStyle(color: Colors.grey)),
                        trailing: dangerous
                            ? const Icon(Icons.warning_amber_rounded, color: Colors.red)
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
}
