import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/badge_helper.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }
    
    final docRef = FirebaseFirestore.instance.collection('users').doc(currentUser!.uid);
    final docSnap = await docRef.get();
    
    if (docSnap.exists) {
      setState(() {
        userData = docSnap.data();
        _isLoading = false;
      });
    } else {
      // Tài liệu chưa được tạo → tự tạo mới từ dữ liệu Firebase Auth
      final String username = currentUser!.email?.split('@')[0] 
          ?? currentUser!.displayName 
          ?? 'Người dùng';
      final newData = {
        'id': currentUser!.uid,
        'name': currentUser!.displayName ?? 'Người dùng',
        'email': currentUser!.email,
        'phoneNumber': currentUser!.phoneNumber,
        'username': username,
        'avatarUrl': currentUser!.photoURL,
        'isGuest': currentUser!.isAnonymous,
        'role': 'member',
        'totalKm': 0.0,
        'badgeLevel': 0,
        'totalTrips': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await docRef.set(newData);
      setState(() {
        userData = newData;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateProfileInfo(String newName, String newUsername) async {
    if (currentUser == null || newUsername.isEmpty || newName.isEmpty) return;
    
    setState(() => _isLoading = true);
    await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({
      'name': newName,
      'username': newUsername,
    });
    await _loadUserData();
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: userData?['name'] ?? '');
    final userController = TextEditingController(text: userData?['username'] ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thông tin cá nhân', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Họ và tên'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: userController,
              decoration: const InputDecoration(labelText: 'Biệt danh (hiển thị trên Radar)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textGrey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateProfileInfo(nameController.text.trim(), userController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
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
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final totalKm = (userData?['totalKm'] as num?)?.toDouble() ?? 0.0;
    final badgeLevel = (userData?['badgeLevel'] as num?)?.toInt() ?? BadgeHelper.getBadgeLevel(totalKm);
    final badgeName = BadgeHelper.getBadgeName(badgeLevel);
    final badgeColor = BadgeHelper.getBadgeColor(badgeLevel);
    
    final totalTrips = (userData?['totalTrips'] as num?)?.toInt() ?? 0;
    final friendsCount = 0; // Placeholder
    
    double nextBadgeKm = 50.0;
    String nextBadgeName = "Hạng Đồng";
    if (badgeLevel == 1) { nextBadgeKm = 200.0; nextBadgeName = "Hạng Bạc"; }
    else if (badgeLevel == 2) { nextBadgeKm = 500.0; nextBadgeName = "Hạng Vàng"; }
    else if (badgeLevel == 3) { nextBadgeKm = 1000.0; nextBadgeName = "Huyền thoại"; }
    else if (badgeLevel == 4) { nextBadgeKm = totalKm; nextBadgeName = "Max"; }

    final progress = badgeLevel == 4 ? 1.0 : (totalKm / nextBadgeKm).clamp(0.0, 1.0);
    final progressPercent = (progress * 100).toInt();

    final avatarUrl = userData?['avatarUrl'];
    final username = userData?['username'] ?? 'Chưa có';
    final name = userData?['name'] ?? 'Người dùng';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('RouteMate', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 24)),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[300],
              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: avatarUrl == null ? const Icon(Icons.person, size: 24, color: Colors.grey) : null,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- AVATAR SECTION ---
            const SizedBox(height: 10),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: badgeColor, width: 4),
                    ),
                  ),
                  CircleAvatar(
                    radius: 54,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?', style: const TextStyle(fontSize: 40, color: Colors.white)) : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('@$username', style: const TextStyle(fontSize: 16, color: AppColors.textGrey, fontWeight: FontWeight.w500)),
            const SizedBox(height: 24),

            // --- BADGE CARD (Cam Gradient) ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [AppColors.accent, Color(0xFFFFA040)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: AppColors.accent.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stars, color: Colors.white, size: 28),
                      const SizedBox(width: 8),
                      Text('Huy hiệu $badgeName', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${totalKm.toStringAsFixed(1)} km',
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    badgeLevel < 4 ? '$badgeName → $progressPercent% đến $nextBadgeName' : 'Bạn đã đạt cấp bậc cao nhất!',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // --- STATS ROW ---
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: AppColors.cardWhite,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.two_wheeler, color: AppColors.primary, size: 30),
                        const SizedBox(height: 8),
                        Text('$totalTrips', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        const Text('Chuyến đi', style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: AppColors.cardWhite,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.group, color: AppColors.accent, size: 30),
                        const SizedBox(height: 8),
                        Text('$friendsCount', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        const Text('Bạn bè', style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // --- MENU LIST ---
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardWhite,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  _buildMenuItem(
                    icon: Icons.history,
                    title: 'Lịch sử hành trình',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tính năng sắp ra mắt')));
                    },
                  ),
                  const Divider(height: 1, indent: 50),
                  _buildMenuItem(
                    icon: Icons.person_outline,
                    title: 'Thông tin cá nhân',
                    onTap: _showEditProfileDialog,
                  ),
                  const Divider(height: 1, indent: 50),
                  _buildMenuItem(
                    icon: Icons.help_outline,
                    title: 'Trợ giúp & Hỗ trợ',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tính năng sắp ra mắt')));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- LOGOUT BUTTON ---
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.sosLight,
                  foregroundColor: AppColors.sos,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text('Đăng xuất', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({required IconData icon, required String title, required VoidCallback onTap}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textGrey),
      onTap: onTap,
    );
  }
}
