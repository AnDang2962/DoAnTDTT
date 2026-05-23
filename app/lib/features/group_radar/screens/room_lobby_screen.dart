import 'package:flutter/material.dart';

import 'group_radar_overlay.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/room_repository.dart';

class RoomLobbyScreen extends StatefulWidget {
  const RoomLobbyScreen({Key? key}) : super(key: key);

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

  // 🔥 2 BIẾN MỚI ĐỂ QUẢN LÝ TRẠNG THÁI TRONG TAB
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
        finalRoomId = _roomController.text.trim();
        // Giả lập join room thành công cho Bypass
        // final success = await _roomRepo.joinRoom(finalRoomId, dummyUser);
        // if (!success) throw Exception('Phòng không tồn tại!');
      }

      // 🔥 THÀNH CÔNG -> Cập nhật State thay vì Navigator.push
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
    // 🔥 NẾU ĐÃ VÀO PHÒNG -> HIỂN THỊ BẢN ĐỒ RADAR (VẪN GIỮ ĐƯỢC 3 TAB Ở DƯỚI)
    if (activeRoomId != null && activeUser != null) {
      return GroupRadarOverlay(
        roomId: activeRoomId!,
        currentUser: activeUser!,
        onLeaveRoom: () {
          // Bấm nút Back -> Xóa state, quay lại Lobby
          setState(() {
            activeRoomId = null;
            activeUser = null;
          });
        },
      );
    }

    // NẾU CHƯA VÀO PHÒNG -> HIỂN THỊ LOBBY
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
