import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:route_mate_app/features/main_shell/main_shell_screen.dart';
import 'package:route_mate_app/core/constants/app_colors.dart';
import 'welcome_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.primary,
            body: Center(
              child: Icon(Icons.motorcycle, size: 60, color: Colors.white),
            ),
          );
        }
        
        if (snapshot.hasData && snapshot.data != null) {
          // Đã đăng nhập
          return const MainShellScreen();
        } else {
          // Chưa đăng nhập -> vào Welcome Screen
          return const WelcomeScreen();
        }
      },
    );
  }
}

