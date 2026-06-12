import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';

class TripHistoryScreen extends StatelessWidget {
  const TripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Lịch sử hành trình', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: uid == null
          ? const Center(child: Text('Chưa đăng nhập'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('trips')
                  .orderBy('date', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.route_rounded, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        const Text('Chưa có hành trình nào', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                        const SizedBox(height: 8),
                        const Text('Bắt đầu điều hướng để ghi lại chuyến đi', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final endName = data['endName'] as String? ?? 'Điểm đến';
                    final traveledKm = (data['traveledKm'] as num?)?.toDouble() ?? 0.0;
                    final distanceKm = (data['distanceKm'] as num?)?.toDouble() ?? 0.0;
                    final durationMins = (data['durationMins'] as num?)?.toInt() ?? 0;
                    final completed = data['completed'] as bool? ?? false;
                    final timestamp = data['date'] as Timestamp?;
                    final date = timestamp?.toDate();
                    return _TripCard(
                      endName: endName,
                      traveledKm: traveledKm,
                      distanceKm: distanceKm,
                      durationMins: durationMins,
                      completed: completed,
                      date: date,
                    );
                  },
                );
              },
            ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final String endName;
  final double traveledKm;
  final double distanceKm;
  final int durationMins;
  final bool completed;
  final DateTime? date;

  const _TripCard({
    required this.endName,
    required this.traveledKm,
    required this.distanceKm,
    required this.durationMins,
    required this.completed,
    required this.date,
  });

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int mins) {
    if (mins < 60) return '$mins phút';
    return '${mins ~/ 60} giờ ${mins % 60} phút';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: completed ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              completed ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: completed ? Colors.green : Colors.orange,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(endName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(_formatDate(date), style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${traveledKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.primary)),
              const SizedBox(height: 2),
              Text(_formatDuration(durationMins), style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
