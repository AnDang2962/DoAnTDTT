import 'package:flutter/material.dart';

class SosButton extends StatelessWidget {
  final VoidCallback onSosTriggered;

  const SosButton({Key? key, required this.onSosTriggered}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onSosTriggered,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.5),
              spreadRadius: 5,
              blurRadius: 15,
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'SOS\n(Nhấn giữ)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
