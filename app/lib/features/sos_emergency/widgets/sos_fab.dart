import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Import đúng đường dẫn bạn vừa sửa thành công
import '../../group_radar/presentation/providers/members_provider.dart';
import '../services/sos_service.dart';

class SosFab extends StatelessWidget {
  const SosFab({super.key}); // Đã sửa lỗi cảnh báo xanh

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'sos_fab', 
      backgroundColor: Colors.red.shade800,
      onPressed: () async {
        final provider = Provider.of<MembersProvider>(context, listen: false);
        final currentRoomId = provider.roomId; // Sẽ hết đỏ sau khi M3 thêm biến

        if (currentRoomId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lỗi: Chưa có thông tin nhóm!')),
          );
          return;
        }

        // Đã đổi tên hàm khớp với file sos_service.dart
        await SosService().sendEmergencySignal(
          roomId: currentRoomId, 
          onStatusUpdate: (message, color) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message), backgroundColor: color),
            );
          },
        );
      },
      child: const Icon(Icons.sos, color: Colors.white, size: 28),
    );
  }
}