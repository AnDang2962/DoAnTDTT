import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/solo_room_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRegister() async {
    if (_loading) return;
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      _showError('Vui lòng điền đầy đủ thông tin');
      return;
    }
    if (pass != confirm) {
      _showError('Mật khẩu xác nhận không khớp');
      return;
    }
    if (pass.length < 6) {
      _showError('Mật khẩu phải có ít nhất 6 ký tự');
      return;
    }

    setState(() => _loading = true);
    try {
      final cred = await AuthService.registerWithEmail(
        email: email,
        password: pass,
        displayName: name,
      );
      await _saveUserToFirestore(cred.user, name, email);
      await SoloRoomService.ensureSoloRoom();
      // Sign out sau khi setup xong — tránh auto-redirect vào app
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginScreen(initialEmail: email, initialPassword: pass),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      _showError(_authError(e.code));
      debugPrint('RegisterScreen FirebaseAuthException: ${e.code} — ${e.message}');
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('RegisterScreen unexpected error: $e');
      _showError('Đăng ký thất bại, thử lại');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveUserToFirestore(User? user, String name, String email) async {
    if (user == null) return;
    final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await doc.get();
    if (!snap.exists) {
      await doc.set({
        'id': user.uid,
        'name': name,
        'email': email,
        'username': email.split('@').first,
        'avatarUrl': user.photoURL,
        'isGuest': false,
        'role': 'member',
        'totalKm': 0.0,
        'totalTrips': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  String _authError(String code) {
    switch (code) {
      case 'email-already-in-use': return 'Email này đã được sử dụng';
      case 'invalid-email': return 'Email không hợp lệ';
      case 'weak-password': return 'Mật khẩu quá yếu';
      default: return 'Đăng ký thất bại, thử lại';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/login_bg.jpg', fit: BoxFit.cover),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(color: Colors.white.withValues(alpha: 0.55)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tạo tài khoản',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tham gia cộng đồng phượt thủ RouteMate',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 32),
                  _field(_nameCtrl, 'Tên hiển thị', Icons.person_outline, false),
                  const SizedBox(height: 14),
                  _field(_emailCtrl, 'Email', Icons.email_outlined, false,
                      type: TextInputType.emailAddress),
                  const SizedBox(height: 14),
                  _passwordField(_passCtrl, 'Mật khẩu', _obscurePass, () {
                    setState(() => _obscurePass = !_obscurePass);
                  }),
                  const SizedBox(height: 14),
                  _passwordField(_confirmCtrl, 'Xác nhận mật khẩu', _obscureConfirm, () {
                    setState(() => _obscureConfirm = !_obscureConfirm);
                  }),
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: _loading ? null : _onRegister,
                    child: Container(
                      height: 52,
                      decoration: _loading
                          ? BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(30),
                            )
                          : AppTheme.primaryButtonDecoration,
                      alignment: Alignment.center,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Đăng ký ngay',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Đã có tài khoản? ', style: TextStyle(color: AppTheme.textSecondary)),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text(
                          'Đăng nhập',
                          style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon,
    bool obscure, {
    TextInputType type = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _passwordField(
    TextEditingController ctrl,
    String hint,
    bool obscure,
    VoidCallback toggle,
  ) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textSecondary),
        suffixIcon: GestureDetector(
          onTap: toggle,
          child: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
