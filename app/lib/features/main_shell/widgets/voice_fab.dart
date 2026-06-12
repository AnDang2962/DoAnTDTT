import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/wake_word_service.dart';

class VoiceFab extends StatefulWidget {
  final bool isListening;
  final VoiceMode mode;
  final WakeWordState wakeState;
  final VoidCallback onTap;
  final VoidCallback onSwitchToWake;
  final VoidCallback onSwitchToTap;

  const VoiceFab({
    super.key,
    required this.isListening,
    required this.mode,
    required this.wakeState,
    required this.onTap,
    required this.onSwitchToWake,
    required this.onSwitchToTap,
  });

  @override
  State<VoiceFab> createState() => _VoiceFabState();
}

class _VoiceFabState extends State<VoiceFab> with SingleTickerProviderStateMixin {
  bool _longPressing = false;
  double _dragX = 0;
  static const _switchThreshold = 72.0;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  bool get _isWakeActive => widget.wakeState == WakeWordState.listening;

  void _onLongPressStart(LongPressStartDetails _) {
    setState(() { _longPressing = true; _dragX = 0; });
    HapticFeedback.mediumImpact();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    if (!_longPressing) return;
    setState(() => _dragX = d.localOffsetFromOrigin.dx.clamp(0, _switchThreshold + 20));
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (!_longPressing) return;
    final switched = _dragX >= _switchThreshold;
    setState(() { _longPressing = false; _dragX = 0; });
    if (switched) {
      HapticFeedback.heavyImpact();
      if (widget.mode == VoiceMode.tap) {
        widget.onSwitchToWake();
      } else {
        widget.onSwitchToTap();
      }
    }
  }

  Color get _baseColor {
    if (widget.isListening) return Colors.red.shade600;
    if (widget.mode == VoiceMode.wakeWord) {
      if (_isWakeActive) return Colors.green.shade600;
      return Colors.green.shade400;
    }
    return const Color(0xFFE53935);
  }

  IconData get _icon {
    if (widget.mode == VoiceMode.wakeWord) {
      if (_isWakeActive || widget.isListening) return Icons.graphic_eq;
      return Icons.hearing;
    }
    return widget.isListening ? Icons.mic : Icons.mic_none;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _longPressing ? null : widget.onTap,
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: () => setState(() { _longPressing = false; _dragX = 0; }),
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) {
          final scale = (_isWakeActive && !_longPressing)
              ? _pulseAnim.value
              : 1.0;
          return Transform.scale(scale: scale, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: _longPressing ? 160 : 56,
          height: 56,
          decoration: BoxDecoration(
            color: _baseColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: _baseColor.withValues(alpha: 0.45),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (_, constraints) => ClipRect(
              child: _longPressing && constraints.maxWidth > 80
                  ? _buildSlideContent()
                  : _buildIdleContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdleContent() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(_icon, color: Colors.white, size: 28),
        if (widget.mode == VoiceMode.wakeWord)
          Positioned(
            top: 6, right: 8,
            child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: _isWakeActive ? Colors.greenAccent : Colors.white54,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSlideContent() {
    final progress = (_dragX / _switchThreshold).clamp(0.0, 1.0);
    final targetMode = widget.mode == VoiceMode.tap ? VoiceMode.wakeWord : VoiceMode.tap;
    final label = targetMode == VoiceMode.wakeWord ? 'Wake word' : 'Nhấn mic';
    final icon = targetMode == VoiceMode.wakeWord ? Icons.hearing : Icons.mic_none;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            widget.mode == VoiceMode.tap ? Icons.mic_none : Icons.hearing,
            color: Colors.white70,
            size: 22,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2 + 0.6 * progress),
              shape: BoxShape.circle,
            ),
            child: Icon(
              progress >= 1.0 ? Icons.check : icon,
              color: Colors.white,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}
