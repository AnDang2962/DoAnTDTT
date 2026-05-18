import 'package:flutter/material.dart';

class MapControls extends StatelessWidget {
  final VoidCallback onCompassPressed;
  final VoidCallback onZoomInPressed;
  final VoidCallback onZoomOutPressed;
  final VoidCallback onVoiceCommandPressed;

  const MapControls({
    Key? key,
    required this.onCompassPressed,
    required this.onZoomInPressed,
    required this.onZoomOutPressed,
    required this.onVoiceCommandPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'compass',
          onPressed: onCompassPressed,
          child: const Icon(Icons.explore),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'zoom_in',
          onPressed: onZoomInPressed,
          child: const Icon(Icons.add),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'zoom_out',
          onPressed: onZoomOutPressed,
          child: const Icon(Icons.remove),
        ),
        const SizedBox(height: 16),
        FloatingActionButton(
          heroTag: 'voice',
          backgroundColor: Colors.redAccent,
          onPressed: onVoiceCommandPressed,
          child: const Icon(Icons.mic),
        ),
      ],
    );
  }
}
