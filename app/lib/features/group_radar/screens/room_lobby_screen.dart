import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/room_repository.dart';
import 'group_radar_overlay.dart';
import '../../../core/constants/app_colors.dart';

import 'package:provider/provider.dart';
import '../presentation/providers/members_provider.dart';
import '../../main_map/providers/map_state_provider.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RoomLobbyScreen extends StatefulWidget {
  const RoomLobbyScreen({super.key});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  final RoomRepository _roomRepo = RoomRepository();
  final TextEditingController _roomIdController = TextEditingController();

  bool _isCreatingRoom = true;
  String _selectedRole = 'leader';
  bool _isLoading = false;

  String? _activeRoomId;
  UserModel? _activeUser;

  @override
  void dispose() {
    _roomIdController.dispose();
    super.dispose();
  }

  UserRole _stringToRole(String s) {
    switch (s) {
      case 'leader': return UserRole.leader;
      case 'sweeper': return UserRole.sweeper;
      default: return UserRole.member;
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _switchMode(bool toCreating) {
    setState(() {
      _isCreatingRoom = toCreating;
      _selectedRole = toCreating ? 'leader' : 'member';
    });
  }

  void _onLeaveRoom() async {
    if (_activeRoomId == null) return;
    final wasLeader = _activeUser?.role == UserRole.leader;
    if (!wasLeader) await _roomRepo.leaveRoom(_activeRoomId!);

    if (!mounted) return;
    context.read<MapStateProvider>().setGroupMode(false);
    context.read<MapStateProvider>().clearAll();
    context.read<MembersProvider>().updateRoomIdForSOS('');
    setState(() {
      _activeRoomId = null;
      _activeUser = null;
    });
  }

  Future<void> _handleAction() async {
    if (_isLoading) return;

    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      _showError('Chưa đăng nhập Firebase. Khởi động lại app.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Đọc username từ Firestore thay vì bắt nhập
      final docSnap = await FirebaseFirestore.instance.collection('users').doc(auth.currentUser!.uid).get();
      String username = docSnap.data()?['username'] ?? '';
      
      if (username.isEmpty) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Thiếu Biệt danh'),
            content: const Text('Vui lòng vào tab Hồ sơ để đặt biệt danh hiển thị trước khi tham gia đội nhóm!'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu')),
            ],
          ),
        );
        return;
      }

      final user = UserModel(
        id: auth.currentUser!.uid,
        name: username,
        role: _stringToRole(_selectedRole),
      );

      String? roomId;

      if (_isCreatingRoom) {
        roomId = await _roomRepo.createRoom(user);
        if (roomId == null) {
          _showError('Tạo phòng từ Backend thất bại!');
          return;
        }
      } else {
        final inputRoomId = _roomIdController.text.trim().toUpperCase();
        if (inputRoomId.isEmpty) {
          _showError('Vui lòng nhập mã phòng');
          return;
        }
        final ok = await _roomRepo.joinRoom(inputRoomId, user);
        if (!ok) {
          _showError('Mã phòng không tồn tại hoặc bạn đã trong phòng khác');
          return;
        }
        roomId = inputRoomId;
      }

      if (roomId != null) {
        try {
          String? token = await FirebaseMessaging.instance.getToken();
          if (token != null) {
            await FirebaseFirestore.instance.collection('rooms').doc(roomId).set(
              {'fcmTokens': {auth.currentUser!.uid: token}}, SetOptions(merge: true)
            );
          }
        } catch (e) {
          debugPrint('Lỗi cập nhật FCM token: $e');
        }
      }

      if (!mounted) return;
      context.read<MapStateProvider>().clearAll();
      context.read<MembersProvider>().updateRoomIdForSOS(roomId!);
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

  Widget _buildRoleChip(String roleId, String label, IconData icon, Color color) {
    final isSelected = _selectedRole == roleId;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = roleId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          border: Border.all(color: isSelected ? color : Colors.grey.shade300, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(
              fontSize: 16, 
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? color : Colors.black87
            )),
            const Spacer(),
            if (isSelected) Icon(Icons.check_circle, color: color),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_activeRoomId != null && _activeUser != null) {
      return GroupRadarOverlay(
        roomId: _activeRoomId!,
        currentUser: _activeUser!,
        onLeaveRoom: _onLeaveRoom,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('RouteMate', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- HEADER GRADIENT ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accent, Color(0xFF8B4513)], // Cam sang nâu
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cùng nhau\nchinh phục',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Không ai bị bỏ lại phía sau.',
                    style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.white70),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            // --- 2 MODE CARDS ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _switchMode(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: _isCreatingRoom ? AppColors.primary.withOpacity(0.1) : Colors.white,
                          border: Border.all(color: _isCreatingRoom ? AppColors.primary : Colors.grey.shade300, width: 2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.add_circle, size: 40, color: _isCreatingRoom ? AppColors.primary : Colors.grey),
                            const SizedBox(height: 8),
                            Text('Làm trưởng nhóm', style: TextStyle(fontWeight: FontWeight.bold, color: _isCreatingRoom ? AppColors.primary : Colors.grey.shade700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _switchMode(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: !_isCreatingRoom ? AppColors.primary.withOpacity(0.1) : Colors.white,
                          border: Border.all(color: !_isCreatingRoom ? AppColors.primary : Colors.grey.shade300, width: 2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.login, size: 40, color: !_isCreatingRoom ? AppColors.primary : Colors.grey),
                            const SizedBox(height: 8),
                            Text('Nhập mã tham gia', style: TextStyle(fontWeight: FontWeight.bold, color: !_isCreatingRoom ? AppColors.primary : Colors.grey.shade700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // --- FORM CARD ---
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isCreatingRoom) ...[
                    const Text('Mã phòng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _roomIdController,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      decoration: InputDecoration(
                        hintText: 'Nhập 6 ký tự',
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        counterText: "",
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  const Text('Chọn vai trò của bạn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  
                  _buildRoleChip('leader', 'Leader (Dẫn đoàn)', Icons.shield, const Color(0xFFFFD700)),
                  _buildRoleChip('member', 'Member (Thành viên)', Icons.two_wheeler, Colors.blue),
                  _buildRoleChip('sweeper', 'Sweeper (Chốt đoàn)', Icons.flag, Colors.redAccent),
                  
                  const SizedBox(height: 16),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(
                              _isCreatingRoom ? 'Tạo phòng ngay →' : 'Vào phòng →',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
