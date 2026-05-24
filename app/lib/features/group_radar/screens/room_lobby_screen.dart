import 'package:flutter/material.dart';

import 'group_radar_overlay.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/room_repository.dart';

class RoomLobbyScreen extends StatefulWidget {
  const RoomLobbyScreen({super.key});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  bool isCreatingRoom = true;
  String selectedRole = 'member';
  bool isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();
  final RoomRepository _roomRepo = RoomRepository();

  String? activeRoomId;
  UserModel? activeUser;

  @override
  void dispose() {
    _nameController.dispose();
    _roomController.dispose();
    super.dispose();
  }

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

    setState(() => isLoading = true);

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
        finalRoomId = await _roomRepo.createRoom(dummyUser);
        if (finalRoomId == null) throw Exception('Tạo phòng thất bại!');
      } else {
        // 🔥 M3 XỬ LÝ: Mở khóa hàm joinRoom và bắt buộc viết hoa mã phòng
        finalRoomId = _roomController.text.trim().toUpperCase();
        final success = await _roomRepo.joinRoom(finalRoomId, dummyUser);
        if (!success) throw Exception('Phòng không tồn tại hoặc lỗi kết nối!');
      }

      if (mounted && finalRoomId != null) {
        setState(() {
          activeRoomId = finalRoomId;
          activeUser = dummyUser;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (activeRoomId != null && activeUser != null) {
      return GroupRadarOverlay(
        roomId: activeRoomId!,
        currentUser: activeUser!,
        onLeaveRoom: () {
          setState(() {
            activeRoomId = null;
            activeUser = null;
          });
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.white, // THÊM DÒNG NÀY ĐỂ CHE KÍN BẢN ĐỒ
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
                    selectedRole = 'leader';
                  }),
                ),
                const SizedBox(width: 16),
                ChoiceChip(
                  label: const Text('Vào phòng'),
                  selected: !isCreatingRoom,
                  onSelected: (val) => setState(() {
                    isCreatingRoom = false;
                    selectedRole = 'member';
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
                textCapitalization:
                    TextCapitalization.characters, // Tự động viết hoa bàn phím
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
                onPressed: isLoading ? null : _handleEnterRoom,
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
