import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SosHistoryScreen extends StatelessWidget {
  // Biến này sẽ nhận roomId từ màn hình trước truyền sang
  final String roomId;

  const SosHistoryScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử SOS'),
        centerTitle: true,
      ),
      body: roomId.isEmpty 
          ? const Center(
              child: Text("⚠️ Mã phòng không hợp lệ."),
            )
          : StreamBuilder<QuerySnapshot>(
              // Kết nối trực tiếp vào collection sosLogs của phòng này
              stream: FirebaseFirestore.instance
                  .collection('rooms')
                  .doc(roomId)
                  .collection('sosLogs')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                // 1. Xử lý trạng thái lỗi
                if (snapshot.hasError) {
                  return Center(child: Text("Lỗi: ${snapshot.error}"));
                }
                
                // 2. Xử lý trạng thái đang tải
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // 3. Xử lý trạng thái không có dữ liệu
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("Chưa có lịch sử SOS nào."));
                }

                // 4. Hiển thị danh sách dữ liệu
                final logs = snapshot.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final data = logs[index].data() as Map<String, dynamic>;
                    
                    // Xử lý hiển thị thời gian
                    final timestamp = data['createdAt'] as Timestamp?;
                    final timeStr = timestamp != null
                        ? "${timestamp.toDate().hour}:${timestamp.toDate().minute.toString().padLeft(2, '0')} - ${timestamp.toDate().day}/${timestamp.toDate().month}"
                        : "N/A";

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.redAccent,
                          child: Icon(Icons.warning_amber_rounded, color: Colors.white),
                        ),
                        title: Text(
                          'SOS từ: ${data['senderId']?.toString().substring(0, 8) ?? 'Ẩn danh'}...',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('Thời điểm: $timeStr'),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}