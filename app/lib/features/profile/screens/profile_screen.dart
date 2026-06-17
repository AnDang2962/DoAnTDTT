import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/badge_helper.dart';
import '../../../core/services/room_session_service.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/screens/welcome_screen.dart';
import 'trip_history_screen.dart';
import 'help_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? userData;
  bool _isLoading = true;
  StreamSubscription<DocumentSnapshot>? _userSub;

  @override
  void initState() {
    super.initState();
    _subscribeUserData();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  void _subscribeUserData() {
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }
    final docRef = FirebaseFirestore.instance.collection('users').doc(currentUser!.uid);
    _userSub = docRef.snapshots().listen((snap) async {
      if (!snap.exists) {
        final username = currentUser!.email?.split('@')[0] ?? currentUser!.displayName ?? 'Người dùng';
        await docRef.set({
          'id': currentUser!.uid,
          'name': currentUser!.displayName ?? 'Người dùng',
          'email': currentUser!.email,
          'username': username,
          'avatarUrl': currentUser!.photoURL,
          'isGuest': currentUser!.isAnonymous,
          'role': 'member',
          'totalKm': 0.0,
          'totalTrips': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        if (mounted) setState(() { userData = snap.data(); _isLoading = false; });
      }
    });
  }

  Future<void> _uploadAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppTheme.primary),
              title: const Text('Chọn từ thư viện'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.primary),
              title: const Text('Chụp ảnh mới'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || currentUser == null) return;

    final picked = await ImagePicker().pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (picked == null) return;

    setState(() => _isLoading = true);
    try {
      final ref = FirebaseStorage.instance.ref('users/${currentUser!.uid}/avatar.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({'avatarUrl': url}),
        currentUser!.updatePhotoURL(url),
      ]);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể tải ảnh lên. Vui lòng thử lại.')));
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _updateProfileInfo(String newName, String newUsername, String phone, String emergencyContact) async {
    if (currentUser == null || newUsername.isEmpty || newName.isEmpty) return;

    await Future.wait([
      FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({
        'name': newName,
        'username': newUsername,
        'phoneNumber': phone,
        'emergencyContacts': emergencyContact.isNotEmpty ? [emergencyContact] : [],
      }),
      currentUser!.updateDisplayName(newName),
    ]);

    final session = await RoomSessionService.load();
    if (session != null) {
      try {
        await FirebaseFirestore.instance
            .collection('rooms')
            .doc(session['roomId'])
            .update({'memberInfo.${currentUser!.uid}.displayName': newUsername});
      } catch (_) {}
    }
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: userData?['name'] ?? '');
    final userController = TextEditingController(text: userData?['username'] ?? '');
    final phoneController = TextEditingController(text: userData?['phoneNumber'] ?? '');
    final contacts = userData?['emergencyContacts'];
    final emergencyController = TextEditingController(
      text: (contacts is List && contacts.isNotEmpty) ? contacts.first.toString() : '',
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Thông tin cá nhân', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Họ và tên')),
              const SizedBox(height: 12),
              TextField(controller: userController, decoration: const InputDecoration(labelText: 'Biệt danh (hiển thị trên Radar)')),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Số điện thoại'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emergencyController,
                decoration: const InputDecoration(
                  labelText: 'Số liên hệ khẩn cấp (SOS)',
                  hintText: 'Người thân, bạn bè...',
                  prefixIcon: Icon(Icons.emergency_rounded, color: Colors.red),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateProfileInfo(
                nameController.text.trim(),
                userController.text.trim(),
                phoneController.text.trim(),
                emergencyController.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              minimumSize: const Size(80, 40),
            ),
            child: const Text('Lưu', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    final totalKm = (userData?['totalKm'] as num?)?.toDouble() ?? 0.0;
    final totalTrips = (userData?['totalTrips'] as num?)?.toInt() ?? 0;
    final badgeColor = BadgeHelper.ringColor(totalKm);
    final badgeName = BadgeHelper.tierName(totalKm);

    final double nextBadgeKm;
    final String nextBadgeName;
    if (totalKm < 100) { nextBadgeKm = 100.0; nextBadgeName = 'Hạng Bạc'; }
    else if (totalKm < 500) { nextBadgeKm = 500.0; nextBadgeName = 'Hạng Vàng'; }
    else if (totalKm < 2000) { nextBadgeKm = 2000.0; nextBadgeName = 'Kim Cương'; }
    else { nextBadgeKm = totalKm; nextBadgeName = 'Max'; }

    final baseKm = totalKm < 100 ? 0.0 : totalKm < 500 ? 100.0 : totalKm < 2000 ? 500.0 : 2000.0;
    final progress = totalKm >= 2000 ? 1.0 : ((totalKm - baseKm) / (nextBadgeKm - baseKm)).clamp(0.0, 1.0);
    final progressPercent = (progress * 100).toInt();
    final isMax = totalKm >= 2000;

    final avatarUrl = userData?['avatarUrl'] as String?;
    final username = (userData?['username'] as String?) ?? 'Chưa có';
    final name = (userData?['name'] as String?) ?? 'Người dùng';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),
              _Header(name: name),
              const SizedBox(height: 24),
              _Avatar(
                avatarUrl: avatarUrl,
                ringColor: badgeColor,
                onTap: _uploadAvatar,
              ),
              const SizedBox(height: 12),
              Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text('@$username', style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              const SizedBox(height: 20),
              _AchievementCard(
                totalKm: totalKm,
                badgeName: badgeName,
                nextBadgeName: nextBadgeName,
                progress: progress,
                progressPercent: progressPercent,
                isMax: isMax,
              ),
              const SizedBox(height: 14),
              _StatsRow(totalTrips: totalTrips),
              const SizedBox(height: 20),
              _MenuSection(onEditProfile: _showEditProfileDialog),
              const SizedBox(height: 20),
              _SignOutButton(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  const _Header({required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'RouteMate',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
        ),
        const Spacer(),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_rounded, color: AppTheme.primary, size: 22),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final Color ringColor;
  final VoidCallback? onTap;
  const _Avatar({required this.avatarUrl, required this.ringColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ringColor, width: 3),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: ClipOval(
          child: avatarUrl != null
              ? Image.network(avatarUrl!, fit: BoxFit.cover)
              : Container(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  child: const Icon(Icons.person_rounded, size: 48, color: AppTheme.primary),
                ),
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final double totalKm;
  final String badgeName;
  final String nextBadgeName;
  final double progress;
  final int progressPercent;
  final bool isMax;

  const _AchievementCard({
    required this.totalKm,
    required this.badgeName,
    required this.nextBadgeName,
    required this.progress,
    required this.progressPercent,
    required this.isMax,
  });

  List<Color> get _gradientColors {
    if (totalKm < 100) return [const Color(0xFF8B4513), const Color(0xFFCD7F32)];
    if (totalKm < 500) return [const Color(0xFF607D8B), const Color(0xFFB0C4DE)];
    if (totalKm < 2000) return [const Color(0xFFE8650A), const Color(0xFFF5A623)];
    return [const Color(0xFF0277BD), const Color(0xFF00E5FF)];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _gradientColors.first.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: Icon(Icons.emoji_events_outlined, size: 64, color: Colors.white.withValues(alpha: 0.20)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.star_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Huy hiệu & Thành tích',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                totalKm.toStringAsFixed(1),
                style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900, height: 1.0),
              ),
              const Text('km đã đi', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Hạng $badgeName', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const Spacer(),
                  Text(
                    isMax ? 'Cấp bậc tối đa!' : '$progressPercent% đến $nextBadgeName',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 7,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int totalTrips;
  const _StatsRow({required this.totalTrips});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(value: totalTrips.toString(), label: 'Chuyến đi', icon: Icons.route_rounded)),
        const SizedBox(width: 12),
        const Expanded(child: _StatCard(value: '—', label: 'Bạn bè', icon: Icons.people_rounded)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _StatCard({required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primary, size: 26),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  final VoidCallback onEditProfile;
  const _MenuSection({required this.onEditProfile});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.history_rounded, color: AppTheme.primary, size: 22),
            title: const Text('Lịch sử hành trình', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TripHistoryScreen())),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF0F0F0)),
          ListTile(
            leading: const Icon(Icons.person_outline_rounded, color: AppTheme.primary, size: 22),
            title: const Text('Thông tin cá nhân', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
            onTap: onEditProfile,
          ),
          const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF0F0F0)),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded, color: AppTheme.primary, size: 22),
            title: const Text('Trợ giúp', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen())),
          ),
        ],
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Đăng xuất'),
            content: const Text('Bạn có chắc muốn đăng xuất không?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Đăng xuất', style: TextStyle(color: AppTheme.red)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await AuthService.signOut();
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const WelcomeScreen()),
              (route) => false,
            );
          }
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.red.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: AppTheme.red, size: 20),
            SizedBox(width: 8),
            Text('Đăng xuất', style: TextStyle(color: AppTheme.red, fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
