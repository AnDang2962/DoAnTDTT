import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:route_mate_app/core/constants/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  bool _isLogin = true;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _usernameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveUserToFirestore(User user, {bool isGuest = false}) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final docSnap = await docRef.get();

    if (!docSnap.exists) {
      String username = user.displayName ?? 'Guest';
      String displayName = user.displayName ?? 'Người dùng';
      
      if (!isGuest && !_isLogin) {
        // Đăng ký bằng Email/Pass -> Lấy từ input
        username = _usernameController.text.trim();
        displayName = _displayNameController.text.trim();
      } else if (!isGuest && user.email != null) {
        // Đăng nhập Google -> Lấy từ email
        username = user.email!.split('@')[0];
      }

      await docRef.set({
        'id': user.uid,
        'name': displayName,
        'email': user.email,
        'phoneNumber': user.phoneNumber,
        'username': username,
        'avatarUrl': user.photoURL,
        'isGuest': isGuest,
        'role': 'member',
        'totalKm': 0.0,
        'badgeLevel': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('[Google SignIn] Bắt đầu...');
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        debugPrint('[Google SignIn] Người dùng huỷ hoặc bị lỗi cấu hình (null returned)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể đăng nhập Google. Kiểm tra cấu hình Firebase (SHA-1).'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      debugPrint('[Google SignIn] Lấy được account: ${googleUser.email}');
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      if (userCredential.user != null) {
        debugPrint('[Google SignIn] Thành công: ${userCredential.user!.uid}');
        await _saveUserToFirestore(userCredential.user!);
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[Google SignIn] LỖI: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi đăng nhập Google: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInAsGuest() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('[Guest SignIn] Đang đăng nhập ẩn danh...');
      final userCredential = await FirebaseAuth.instance.signInAnonymously();
      if (userCredential.user != null) {
        debugPrint('[Guest SignIn] Thành công: ${userCredential.user!.uid}');
        await _saveUserToFirestore(userCredential.user!, isGuest: true);
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[Guest SignIn] LỖI: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi đăng nhập khách: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitEmailPass() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập đầy đủ email và mật khẩu')));
      return;
    }

    if (!_isLogin) {
      if (_displayNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập họ tên')));
        return;
      }
      if (_usernameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập biệt danh')));
        return;
      }
      if (password != _confirmPasswordController.text.trim()) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu xác nhận không khớp')));
        return;
      }
      if (password.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu phải từ 6 ký tự trở lên')));
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
        if (mounted) Navigator.of(context).pop();
      } else {
        final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
        if (userCredential.user != null) {
          await _saveUserToFirestore(userCredential.user!);
          if (mounted) Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quên mật khẩu?'),
        content: TextField(
          controller: resetEmailController,
          decoration: const InputDecoration(
            labelText: 'Nhập email của bạn',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('HỦY', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (resetEmailController.text.trim().isEmpty) return;
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: resetEmailController.text.trim());
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi email khôi phục mật khẩu!')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                }
              }
            },
            child: const Text('GỬI'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        obscureText: isPassword && _obscurePassword,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: Icon(icon, color: Colors.white70),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white.withOpacity(0.2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image with Blur
          Positioned.fill(
            child: Image.asset(
              'assets/images/login_bg.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: AppColors.primary),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
              child: Container(
                color: Colors.black.withOpacity(0.4),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    const Icon(Icons.two_wheeler, size: 60, color: Colors.white),
                    const SizedBox(height: 10),
                    const Text(
                      'RouteMate',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLogin ? 'Đăng nhập để tiếp tục hành trình' : 'Tạo tài khoản để tham gia nhóm',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 40),

                    // Forms
                    if (!_isLogin) ...[
                      _buildTextField(
                        controller: _displayNameController,
                        label: 'Họ và tên',
                        icon: Icons.person_outline,
                      ),
                      _buildTextField(
                        controller: _usernameController,
                        label: 'Biệt danh (hiển thị trong nhóm)',
                        icon: Icons.badge_outlined,
                      ),
                    ],

                    _buildTextField(
                      controller: _emailController,
                      label: 'Email của bạn',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),

                    _buildTextField(
                      controller: _passwordController,
                      label: 'Mật khẩu',
                      icon: Icons.lock_outline,
                      isPassword: true,
                    ),

                    if (!_isLogin)
                      _buildTextField(
                        controller: _confirmPasswordController,
                        label: 'Xác nhận mật khẩu',
                        icon: Icons.lock_outline,
                        isPassword: true,
                      ),

                    if (_isLogin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPasswordDialog,
                          child: const Text(
                            'Quên mật khẩu?',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    
                    const SizedBox(height: 10),

                    // Submit Button
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator(color: Colors.white))
                    else
                      ElevatedButton(
                        onPressed: _submitEmailPass,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _isLogin ? 'Đăng nhập →' : 'Đăng ký →',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    
                    const SizedBox(height: 24),

                    // Divider
                    const Row(
                      children: [
                        Expanded(child: Divider(color: Colors.white30)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Hoặc', style: TextStyle(color: Colors.white70)),
                        ),
                        Expanded(child: Divider(color: Colors.white30)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Google Button
                    OutlinedButton(
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.g_mobiledata, size: 30, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Đăng nhập bằng Google', style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Guest Button
                    TextButton(
                      onPressed: _isLoading ? null : _signInAsGuest,
                      child: const Text(
                        'Trải nghiệm ngay (Khách)',
                        style: TextStyle(color: Colors.white70, decoration: TextDecoration.underline),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Toggle Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isLogin ? 'Chưa có tài khoản?' : 'Đã có tài khoản?',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isLogin = !_isLogin;
                              _emailController.clear();
                              _passwordController.clear();
                              _confirmPasswordController.clear();
                              _displayNameController.clear();
                              _usernameController.clear();
                            });
                          },
                          child: Text(
                            _isLogin ? 'Đăng ký ngay' : 'Đăng nhập',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
