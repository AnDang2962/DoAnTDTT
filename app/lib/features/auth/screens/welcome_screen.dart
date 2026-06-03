import 'package:flutter/material.dart';
import 'package:route_mate_app/core/constants/app_colors.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image (2/3 dưới) và nền xanh (1/3 trên)
          Column(
            children: [
              Expanded(
                flex: 1,
                child: Container(
                  color: AppColors.primary,
                ),
              ),
              Expanded(
                flex: 2,
                child: Image.asset(
                  'assets/images/welcome_bg.png',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[300],
                      child: const Center(
                        child: Icon(Icons.image, size: 100, color: Colors.grey),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          
          // Nền xanh gradient nối giữa phần trên và hình ảnh (tùy chọn để mượt hơn)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.8),
                    Colors.transparent,
                    Colors.black.withOpacity(0.4), // dark overlay at bottom for button
                  ],
                  stops: const [0.0, 0.35, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Logo & Text (Top)
                Padding(
                  padding: const EdgeInsets.only(top: 40.0),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.motorcycle_outlined,
                        size: 80,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 10),
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                          children: [
                            TextSpan(text: 'Route', style: TextStyle(color: Colors.white)),
                            TextSpan(text: 'Mate', style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Button (Bottom)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 40.0),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary, // xanh đậm
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 5,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Bắt đầu',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_ios, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
