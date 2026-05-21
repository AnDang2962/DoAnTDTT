import 'package:flutter/material.dart';

// Đổi lại các đường dẫn import này cho đúng với dự án của nhóm bạn
import 'group_radar_overlay.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/room_repository.dart'; // Đã thêm Import Repo

class RoomLobbyScreen extends StatefulWidget {
  const RoomLobbyScreen({Key? key}) : super(key: key);

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  bool isCreatingRoom = true;
  String selectedRole = 'member';
  bool isLoading = false; // Cờ trạng thái chờ Firebase

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();
  final RoomRepository _roomRepo =
      RoomRepository(); // Khởi tạo vũ khí kết nối Backend

  @override
  void dispose() {
    _nameController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  // Hàm xử lý logic chính khi bấm nút
  Future<void> _handleEnterRoom() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên hiển thị!')),
      );
      return;
    }

    if (!isCreatingRoom && _roomController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng nhập mã phòng!')));
      return;
    }

    // Bật hiệu ứng xoay loading
    setState(() => isLoading = true);

    // 1. Tạo Dummy User (Tạm thời do chưa có hệ thống Login)
    final dummyUser = UserModel(
      id: 'UID_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      role: selectedRole == 'leader'
          ? UserRole.leader
          : (selectedRole == 'sweeper' ? UserRole.sweeper : UserRole.member),
    );

    String? finalRoomId;

    try {
      if (isCreatingRoom) {
        // 2A. GỌI BACKEND TẠO PHÒNG
        finalRoomId = await _roomRepo.createRoom(dummyUser);

        if (finalRoomId == null) {
          throw Exception('Lấy mã phòng từ Backend thất bại!');
        }
      } else {
        // 2B. GỌI BACKEND VÀO PHÒNG CÓ SẴN
        finalRoomId = _roomController.text.trim();
        final success = await _roomRepo.joinRoom(finalRoomId, dummyUser);

        if (!success) {
          throw Exception('Phòng không tồn tại hoặc lỗi kết nối!');
        }
      }

      // 3. THÀNH CÔNG -> Chuyển sang màn hình Bản đồ
      if (mounted && finalRoomId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GroupRadarOverlay(
              roomId: finalRoomId!, // Truyền ID thật do Backend quản lý
              currentUser: dummyUser,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      // Tắt loading
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group Radar Lobby')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Tạo phòng'),
                  selected: isCreatingRoom,
                  onSelected: (val) => setState(() {
                    isCreatingRoom = true;
                    _roomController.clear();
                    selectedRole = 'leader'; // Tạo phòng thì auto set là leader
                  }),
                ),
                const SizedBox(width: 16),
                ChoiceChip(
                  label: const Text('Vào phòng'),
                  selected: !isCreatingRoom,
                  onSelected: (val) => setState(() {
                    isCreatingRoom = false;
                    selectedRole = 'member'; // Vào phòng thì auto set là member
                  }),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên hiển thị',
                border: OutlineInputBorder(),
              ),
            ),
            if (!isCreatingRoom) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _roomController,
                decoration: const InputDecoration(
                  labelText: 'Mã phòng (Lấy từ Leader)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedRole,
              decoration: const InputDecoration(
                labelText: 'Vai trò trong đoàn',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'leader',
                  child: Text('Leader (Dẫn đoàn)'),
                ),
                DropdownMenuItem(
                  value: 'member',
                  child: Text('Member (Thành viên)'),
                ),
                DropdownMenuItem(
                  value: 'sweeper',
                  child: Text('Sweeper (Chốt đoàn)'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => selectedRole = val);
              },
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: isLoading
                    ? null
                    : _handleEnterRoom, // Khóa nút khi đang tải
                child: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        isCreatingRoom ? 'Tạo phòng ngay' : 'Vào phòng',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
