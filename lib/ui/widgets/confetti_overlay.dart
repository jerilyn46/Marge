import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/marge_theme.dart';

/// Simple confetti / stinger placeholder for pot wins.
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key, required this.active});

  final bool active;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final _rng = Random(42);
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _particles = List.generate(28, (_) {
      return _Particle(
        dx: _rng.nextDouble(),
        speed: 0.4 + _rng.nextDouble() * 0.8,
        size: 6 + _rng.nextDouble() * 10,
        color: [
          MargeColors.gold,
          MargeColors.coral,
          MargeColors.sky,
          MargeColors.lilac,
          Colors.white,
        ][_rng.nextInt(5)],
      );
    });
  }

  @override
  void didUpdateWidget(covariant ConfettiOverlay old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && !_ctrl.isAnimating) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            painter: _ConfettiPainter(
              progress: _ctrl.value,
              particles: _particles,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.dx,
    required this.speed,
    required this.size,
    required this.color,
  });
  final double dx;
  final double speed;
  final double size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.particles});
  final double progress;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final y = -20 + (size.height + 40) * (progress * p.speed);
      final x = p.dx * size.width + sin(progress * 8 + p.dx * 10) * 18;
      final paint = Paint()..color = p.color.withValues(alpha: 1 - progress);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: p.size, height: p.size * 0.6),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.progress != progress;
}
