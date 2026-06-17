import 'dart:io';
import 'package:flutter/material.dart';
import 'qr_scanner_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../core/services/room_session_service.dart';
import '../../main_map/providers/map_state_provider.dart';
import '../presentation/providers/members_provider.dart';
import 'group_radar_overlay.dart';

class RoomLobbyScreen extends StatefulWidget {
  final VoidCallback? onGoToProfile;

  const RoomLobbyScreen({super.key, this.onGoToProfile});

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
  void initState() {
    super.initState();
    _tryRestoreSession();
  }

  Future<void> _tryRestoreSession() async {
    final session = await RoomSessionService.load();
    if (session == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final roomId = session['roomId']!;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('rooms')
          .doc(roomId)
          .get();
      if (!doc.exists) {
        await RoomSessionService.clear();
        return;
      }
      final data = doc.data();
      if (data == null || data['isActive'] != true) {
        await RoomSessionService.clear();
        return;
      }
      final memberInfo = data['memberInfo'] as Map?;
      if (memberInfo == null || !memberInfo.containsKey(uid)) {
        await RoomSessionService.clear();
        return;
      }
    } catch (e) {
      // permission-denied = session stale (room closed or user no longer member)
      final msg = e.toString();
      if (msg.contains('permission-denied') || msg.contains('not-found')) {
        await RoomSessionService.clear();
      }
      return;
    }

    final leaderPhone = await _fetchLeaderPhone(roomId);
    if (!mounted) return;
    final user = UserModel(
      id: uid,
      name: session['userName']!,
      role: _stringToRole(session['userRole']!),
    );
    context.read<MapStateProvider>().clearAll();
    context.read<MembersProvider>().updateRoomIdForSOS(roomId);
    context.read<MembersProvider>().updateLeaderPhoneForSOS(leaderPhone);
    context.read<MembersProvider>().updateUserRole(session['userRole']!);

    setState(() {
      _activeRoomId = roomId;
      _activeUser = user;
    });
  }

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700, duration: const Duration(seconds: 3)),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700, duration: const Duration(seconds: 2)),
    );
  }

  void _onLeaveRoom() async {
    if (_activeRoomId == null) return;
    final wasLeader = _activeUser?.role == UserRole.leader;
    if (!wasLeader) await _roomRepo.leaveRoom(_activeRoomId!);
    await RoomSessionService.clear();
    if (!mounted) return;
    context.read<MapStateProvider>().setGroupMode(false);
    context.read<MapStateProvider>().clearAll();
    context.read<MembersProvider>().updateRoomIdForSOS('');
    context.read<MembersProvider>().updateLeaderPhoneForSOS('');
    context.read<MembersProvider>().updateUserRole('');
    setState(() {
      _activeRoomId = null;
      _activeUser = null;
    });
  }

  void _showPhoneRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cần số điện thoại'),
        content: const Text(
          'Leader cần có số điện thoại để các thành viên có thể nhận tin nhắn SOS khi mất kết nối internet.\n\nVui lòng cập nhật số điện thoại trong hồ sơ trước khi tạo phòng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Để sau'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onGoToProfile?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Cập nhật ngay', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction() async {
    if (_isLoading) return;

    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      _showError('Chưa đăng nhập. Khởi động lại app.');
      return;
    }

    final uid = auth.currentUser!.uid;
    String displayName = auth.currentUser!.displayName ?? '';
    String phoneNumber = '';
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      final username = data?['username']?.toString() ?? '';
      if (username.isNotEmpty) displayName = username;
      phoneNumber = data?['phoneNumber']?.toString() ?? '';
    } catch (_) {}
    if (displayName.isEmpty) {
      displayName = auth.currentUser!.email?.split('@').first ?? 'Người dùng';
    }

    if (_isCreatingRoom && _selectedRole == 'leader' && phoneNumber.isEmpty) {
      if (mounted) _showPhoneRequiredDialog();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = UserModel(
        id: auth.currentUser!.uid,
        name: displayName,
        role: _stringToRole(_selectedRole),
      );

      String? roomId;

      if (_isCreatingRoom) {
        roomId = await _roomRepo.createRoom(user);
        if (roomId == null) {
          _showError('Tạo phòng từ Backend thất bại! Kiểm tra Emulator.');
          return;
        }
        _showSuccess('Đã tạo phòng: $roomId');
      } else {
        final inputRoomId = _roomIdController.text.trim().toUpperCase();
        if (inputRoomId.isEmpty) {
          _showError('Vui lòng nhập mã phòng');
          return;
        }
        final ok = await _roomRepo.joinRoom(inputRoomId, user);
        if (!ok) {
          _showError('Mã phòng "$inputRoomId" không tồn tại hoặc bạn đã trong phòng khác');
          return;
        }
        roomId = inputRoomId;
        _showSuccess('Đã vào phòng: $roomId');
      }

      try {
        // Trên iOS, APNS phải sẵn sàng trước khi lấy FCM token.
        // Simulator không có APNS → skip để tránh lỗi.
        String? token;
        if (Platform.isIOS) {
          final apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null) token = await FirebaseMessaging.instance.getToken();
        } else {
          token = await FirebaseMessaging.instance.getToken();
        }
        final photoURL = auth.currentUser!.photoURL;
        await FirebaseFirestore.instance
            .collection('rooms')
            .doc(roomId)
            .set({
              'fcmTokens': {auth.currentUser!.uid: token ?? ''},
              'memberInfo': {
                auth.currentUser!.uid: {
                  'displayName': user.name,
                  'role': _selectedRole,
                  'photoURL': ?photoURL,
                }
              },
            }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Lỗi cập nhật FCM/profile: $e');
      }

      await RoomSessionService.save(
        roomId: roomId,
        userName: user.name,
        userRole: _selectedRole,
      );

      final leaderPhone = await _fetchLeaderPhone(roomId);
      if (!mounted) return;
      context.read<MapStateProvider>().clearAll();
      context.read<MembersProvider>().updateRoomIdForSOS(roomId);
      context.read<MembersProvider>().updateLeaderPhoneForSOS(leaderPhone);
      context.read<MembersProvider>().updateUserRole(_selectedRole);

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


  Future<String> _fetchLeaderPhone(String roomId) async {
    try {
      final roomDoc = await FirebaseFirestore.instance.collection('rooms').doc(roomId).get();
      final leaderId = roomDoc.data()?['leaderId']?.toString();

      if (leaderId == null || leaderId.isEmpty) return "";

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(leaderId).get();
      
      return userDoc.data()?['phoneNumber']?.toString() ?? '';
    } catch (e) {
      return "";
    }
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

    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: NestedScrollView(
        physics: const ClampingScrollPhysics(),
        headerSliverBuilder: (context, _) => [
          SliverPersistentHeader(
            delegate: _HeroBannerDelegate(topPadding: topPad, isCreating: _isCreatingRoom),
            pinned: true,
          ),
        ],
        body: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ModeSelector(
                isCreating: _isCreatingRoom,
                onChanged: (val) => setState(() {
                  _isCreatingRoom = val;
                  _selectedRole = val ? 'leader' : 'member';
                }),
              ),
              const SizedBox(height: 24),
              if (!_isCreatingRoom) ...[
                _SectionLabel('Mã phòng'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _roomIdController,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 6,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 6,
                        ),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          hintText: 'Nhập 6 ký tự',
                          hintStyle: TextStyle(fontSize: 16, letterSpacing: 2, fontWeight: FontWeight.w400),
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () async {
                        final result = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(builder: (_) => const QrScannerScreen()),
                        );
                        if (result != null && result.isNotEmpty) {
                          _roomIdController.text = result;
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue.shade200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.qr_code_scanner, color: Colors.blue.shade700, size: 28),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              _SectionLabel('Chọn vai trò của bạn'),
              const SizedBox(height: 12),
              _RoleSelector(
                selected: _selectedRole,
                onChanged: (role) => setState(() => _selectedRole = role),
              ),
              const SizedBox(height: 32),
              _ActionButton(
                isCreating: _isCreatingRoom,
                loading: _isLoading,
                onTap: _handleAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBannerDelegate extends SliverPersistentHeaderDelegate {
  final double topPadding;
  final bool isCreating;
  const _HeroBannerDelegate({required this.topPadding, required this.isCreating});

  @override
  double get minExtent => topPadding + 58;

  @override
  double get maxExtent => topPadding + (isCreating ? 128 : 148);

  static const _darkBlue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);

    // RouteMate: luôn hiện, càng collapse càng nổi bật (to hơn, xanh đậm hơn)
    final routemateSize = _lerp(14, 19, progress);
    final routemateColor = Color.lerp(Colors.white70, _darkBlue, progress)!;

    // Tiêu đề chính: fade out khi collapse
    final titleOpacity = (1.0 - progress * 1.8).clamp(0.0, 1.0);
    final titleHeight = _lerp(36, 0, progress);

    // Subtitle: fade out nhanh hơn
    final subtitleOpacity = (1.0 - progress * 2.5).clamp(0.0, 1.0);
    final subtitleHeight = _lerp(26, 0, progress);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8650A), Color(0xFFF5A623)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, topPadding + 8, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // RouteMate: luôn hiện — focus khi collapsed
            Text(
              'RouteMate',
              style: TextStyle(
                fontSize: routemateSize,
                fontWeight: FontWeight.w700,
                color: routemateColor,
              ),
            ),
            // Tiêu đề chính: ẩn dần khi collapse
            SizedBox(
              height: titleHeight,
              child: Opacity(
                opacity: titleOpacity,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Cùng nhau chinh phục',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            // Subtitle: ẩn dần
            SizedBox(
              height: subtitleHeight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Opacity(
                  opacity: subtitleOpacity,
                  child: Text(
                    'Không ai bị bỏ lại phía sau.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRebuild(covariant _HeroBannerDelegate old) =>
      old.topPadding != topPadding || old.isCreating != isCreating;
}

class _ModeSelector extends StatelessWidget {
  final bool isCreating;
  final ValueChanged<bool> onChanged;

  const _ModeSelector({required this.isCreating, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeCard(
            icon: Icons.add_circle_outline_rounded,
            label: 'Làm trưởng nhóm',
            selected: isCreating,
            onTap: () => onChanged(true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ModeCard(
            icon: Icons.login_rounded,
            label: 'Nhập mã tham gia',
            selected: !isCreating,
            onTap: () => onChanged(false),
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: selected ? AppTheme.primary : Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _RoleSelector({required this.selected, required this.onChanged});

  static const _roles = [
    ('leader', Icons.shield_rounded, 'Leader (Dẫn đoàn)'),
    ('member', Icons.motorcycle_rounded, 'Member (Thành viên)'),
    ('sweeper', Icons.flag_rounded, 'Sweeper (Chốt đoàn)'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _roles.map((r) {
        final (value, icon, label) = r;
        final isSelected = selected == value;
        return GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.orange.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppTheme.orange : const Color(0xFFE0E0E0),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected ? AppTheme.orange : AppTheme.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                      color: isSelected ? AppTheme.orange : AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: AppTheme.orange, size: 22),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final bool isCreating;
  final bool loading;
  final VoidCallback onTap;

  const _ActionButton({required this.isCreating, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 54,
        decoration: loading
            ? BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(30),
              )
            : AppTheme.primaryButtonDecoration,
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isCreating ? 'Tạo phòng ngay' : 'Vào phòng',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                ],
              ),
      ),
    );
  }
}
