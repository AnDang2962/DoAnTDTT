import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/solo_room_service.dart';
import '../services/auth_service.dart';
import '../../../features/main_shell/main_shell_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final String initialEmail;
  final String initialPassword;

  const LoginScreen({
    super.key,
    this.initialEmail = '',
    this.initialPassword = '',
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _emailLoading = false;
  bool _googleLoading = false;
  bool _guestLoading = false;

  bool get _anyLoading => _emailLoading || _googleLoading || _guestLoading;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail.isNotEmpty) _emailCtrl.text = widget.initialEmail;
    if (widget.initialPassword.isNotEmpty) _passCtrl.text = widget.initialPassword;
    if (widget.initialEmail.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đăng ký thành công! Nhấn đăng nhập để vào ứng dụng.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ));
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveUserToFirestore(User user, {bool isGuest = false}) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final docSnap = await docRef.get();
    if (docSnap.exists) return;

    await docRef.set({
      'id': user.uid,
      'name': user.displayName ?? (isGuest ? 'Khách' : 'Người dùng'),
      'email': user.email,
      'username': user.email?.split('@').first ?? (isGuest ? 'guest' : 'user'),
      'avatarUrl': user.photoURL,
      'isGuest': isGuest,
      'role': 'member',
      'totalKm': 0.0,
      'badgeLevel': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _goToMain() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShellScreen()),
      (route) => false,
    );
  }

  Future<void> _onLogin() async {
    if (_anyLoading) return;
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      _showError('Vui lòng nhập email và mật khẩu');
      return;
    }
    setState(() => _emailLoading = true);
    try {
      final cred = await AuthService.signInWithEmail(email, pass);
      if (cred.user != null) await _saveUserToFirestore(cred.user!);
      await SoloRoomService.ensureSoloRoom();
      _goToMain();
    } on FirebaseAuthException catch (e) {
      _showError(_authErrorMessage(e.code));
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  Future<void> _onGoogleLogin() async {
    if (_anyLoading) return;
    setState(() => _googleLoading = true);
    try {
      final cred = await AuthService.signInWithGoogle();
      if (cred != null) {
        if (cred.user != null) await _saveUserToFirestore(cred.user!);
        await SoloRoomService.ensureSoloRoom();
        _goToMain();
      } else {
        if (mounted) setState(() => _googleLoading = false);
      }
    } on FirebaseAuthException catch (e) {
      _showError(_authErrorMessage(e.code));
      if (mounted) setState(() => _googleLoading = false);
    } catch (e) {
      _showError('Đăng nhập Google thất bại');
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _onGuestLogin() async {
    if (_anyLoading) return;
    setState(() => _guestLoading = true);
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      if (cred.user != null) {
        await _saveUserToFirestore(cred.user!, isGuest: true);
        await SoloRoomService.ensureSoloRoom();
        _goToMain();
      }
    } catch (e) {
      _showError('Đăng nhập khách thất bại');
      if (mounted) setState(() => _guestLoading = false);
    }
  }

  Future<void> _onForgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _showError('Nhập email để đặt lại mật khẩu');
      return;
    }
    await AuthService.sendPasswordReset(email);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã gửi email đặt lại mật khẩu')),
      );
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password': return 'Email hoặc mật khẩu không đúng';
      case 'invalid-email': return 'Email không hợp lệ';
      case 'user-disabled': return 'Tài khoản đã bị khóa';
      case 'too-many-requests': return 'Quá nhiều lần thử, vui lòng chờ';
      default: return 'Đăng nhập thất bại ($code)';
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
            filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
            child: Container(color: Colors.black.withValues(alpha: 0.40)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 130,
                      ),
                    ),
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
                    const Text(
                      'Đăng nhập để tiếp tục hành trình',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 40),
                    _buildField(
                      controller: _emailCtrl,
                      label: 'Email của bạn',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _passCtrl,
                      label: 'Mật khẩu',
                      icon: Icons.lock_outline,
                      isPassword: true,
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _onForgotPassword,
                        child: const Text(
                          'Quên mật khẩu?',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SubmitButton(
                      label: 'Đăng nhập →',
                      loading: _emailLoading,
                      onTap: _onLogin,
                    ),
                    const SizedBox(height: 24),
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
                    _GoogleButton(loading: _googleLoading, onTap: _onGoogleLogin),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _anyLoading ? null : _onGuestLogin,
                      child: _guestLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
                            )
                          : const Text(
                              'Trải nghiệm ngay (Khách)',
                              style: TextStyle(
                                color: Colors.white70,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white70,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Chưa có tài khoản? ',
                          style: TextStyle(color: Colors.white70),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RegisterScreen()),
                          ),
                          child: const Text(
                            'Đăng ký ngay',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && _obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white70,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _SubmitButton({required this.label, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 0,
      ),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;

  const _GoogleButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: loading ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white70),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GoogleLogo(),
                SizedBox(width: 10),
                Text('Đăng nhập bằng Google', style: TextStyle(fontSize: 16)),
              ],
            ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    const segments = [
      (0.0, 90.0, Color(0xFF4285F4)),
      (90.0, 90.0, Color(0xFF34A853)),
      (180.0, 90.0, Color(0xFFFBBC05)),
      (270.0, 90.0, Color(0xFFEA4335)),
    ];

    for (final (start, sweep, color) in segments) {
      final path = Path()
        ..moveTo(cx, cy)
        ..arcTo(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
          start * 3.14159 / 180,
          sweep * 3.14159 / 180,
          false,
        )
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    canvas.drawCircle(Offset(cx, cy), r * 0.55, Paint()..color = Colors.white);
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - r * 0.18, r * 0.9, r * 0.36),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
