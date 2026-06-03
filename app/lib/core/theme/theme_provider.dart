import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class ThemeProvider extends ChangeNotifier {
  // Bỏ hoàn toàn tính năng Dark Mode theo yêu cầu của user, chỉ giữ 1 theme (Light Mode)

  ThemeData get currentTheme {
    final colorScheme = const ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.cardWhite,
      error: AppColors.error,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.primary),
        titleTextStyle: TextStyle(
          color: AppColors.primary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 2,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 0,
          minimumSize: const Size.fromHeight(50),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }
}

