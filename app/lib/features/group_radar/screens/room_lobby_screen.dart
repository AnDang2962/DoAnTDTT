import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/room_repository.dart';
import 'group_radar_overlay.dart';

/// Group Radar Lobby — màn hình tạo/vào phòng nhóm.
///
/// Logic flow:
///   1. User nhập tên + vai trò + bấm Tạo/Vào phòng
///   2. Gọi backend createRoom/joinRoom
///   3. Sau khi thành công, switch UI sang GroupRadarOverlay
///      (KHÔNG Navigator.push để giữ Provider scope của MainShellScreen)
class RoomLobbyScreen extends StatefulWidget {
  const RoomLobbyScreen({Key? key}) : super(key: key);

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  final RoomRepository _roomRepo = RoomRepository();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _roomIdController = TextEditingController();

  bool _isCreatingRoom = true;
  String _selectedRole = 'leader';
  bool _isLoading = false;

  // === State để switch sang GroupRadarOverlay ===
  String? _activeRoomId;
  UserModel? _activeUser;

  @override
  void dispose() {
    _nameController.dispose();
    _roomIdController.dispose();
    super.dispose();
  }

  UserRole _stringToRole(String s) {
    switch (s) {
      case 'leader':
        return UserRole.leader;
      case 'sweeper':
        return UserRole.sweeper;
      default:
        return UserRole.member;
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _switchMode(bool toCreating) {
    setState(() {
      _isCreatingRoom = toCreating;
      _selectedRole = toCreating ? 'leader' : 'member';
    });
  }

  /// Khi user rời phòng, quay lại lobby form
  void _onLeaveRoom() async {
    if (_activeRoomId == null) return;

    final wasLeader = _activeUser?.role == UserRole.leader;

    // Member: gọi backend leaveRoom
    if (!wasLeader) {
      await _roomRepo.leaveRoom(_activeRoomId!);
    }

    if (!mounted) return;
    setState(() {
      _activeRoomId = null;
      _activeUser = null;
    });
  }

  /// Xử lý logic Tạo phòng hoặc Vào phòng
  Future<void> _handleAction() async {
    if (_isLoading) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Vui lòng nhập tên hiển thị');
      return;
    }

    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      _showError('Chưa đăng nhập Firebase. Khởi động lại app.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = UserModel(
        id: auth.currentUser!.uid,
        name: name,
        role: _stringToRole(_selectedRole),
      );

      String? roomId;

      if (_isCreatingRoom) {
        roomId = await _roomRepo.createRoom(user);

        if (roomId == null) {
          _showError('Tạo phòng từ Backend thất bại! Kiểm tra Emulator.');
          return;
        }
        _showSuccess('✓ Đã tạo phòng: $roomId');
      } else {
        final inputRoomId = _roomIdController.text.trim().toUpperCase();
        if (inputRoomId.isEmpty) {
          _showError('Vui lòng nhập mã phòng');
          return;
        }

        final ok = await _roomRepo.joinRoom(inputRoomId, user);
        if (!ok) {
          _showError(
              'Mã phòng "$inputRoomId" không tồn tại hoặc bạn đã trong phòng khác');
          return;
        }
        roomId = inputRoomId;
        _showSuccess('✓ Đã vào phòng: $roomId');
      }

      // Switch UI sang GroupRadarOverlay (cùng context, giữ Provider scope)
      if (!mounted) return;
      setState(() {
        _activeRoomId = roomId;
        _activeUser = user;
      });
    } catch (e) {
      _showError('Lỗi không xác định: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Đã vào phòng → hiện GroupRadarOverlay (cùng Provider scope với MainShellScreen)
    if (_activeRoomId != null && _activeUser != null) {
      return GroupRadarOverlay(
        roomId: _activeRoomId!,
        currentUser: _activeUser!,
        onLeaveRoom: _onLeaveRoom,
      );
    }

    // Chưa vào phòng → hiện lobby form
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Group Radar Lobby'),
        backgroundColor: Colors.white.withOpacity(0.95),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Tạo phòng'),
                  selected: _isCreatingRoom,
                  onSelected: (val) {
                    if (val) _switchMode(true);
                  },
                ),
                const SizedBox(width: 16),
                ChoiceChip(
                  label: const Text('Vào phòng'),
                  selected: !_isCreatingRoom,
                  onSelected: (val) {
                    if (val) _switchMode(false);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên hiển thị',
                hintText: 'VD: Khang',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
            ),
            if (!_isCreatingRoom) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _roomIdController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Mã phòng (Room ID)',
                  hintText: 'VD: ABC234',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Vai trò trong đoàn',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'leader', child: Text('Leader (Dẫn đoàn)')),
                DropdownMenuItem(
                    value: 'member', child: Text('Member (Thành viên)')),
                DropdownMenuItem(
                    value: 'sweeper', child: Text('Sweeper (Chốt đoàn)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedRole = val);
              },
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleAction,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor:
                      _isCreatingRoom ? Colors.blue : Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isCreatingRoom ? 'Tạo phòng ngay' : 'Vào phòng',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
