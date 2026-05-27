import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SosHistoryScreen extends StatelessWidget {
  final String roomId; // Nhận roomId trực tiếp từ nơi gọi

  const SosHistoryScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử SOS')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rooms')
            .doc(roomId) // Dùng roomId nhận từ constructor
            .collection('sosLogs')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Lỗi: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return const Center(child: Text("Chưa có lịch sử."));

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.warning, color: Colors.red),
                  title: Text('SOS từ: ${data['senderId'] ?? 'Ẩn danh'}'),
                  subtitle: Text('Thời gian: ${data['createdAt']?.toDate().toString() ?? 'N/A'}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}