import 'package:flutter/material.dart';

import '../theme/marge_theme.dart';

class DieWidget extends StatelessWidget {
  const DieWidget({
    super.key,
    required this.value,
    required this.kept,
    this.onTap,
    this.size = 72,
    this.enabled = true,
  });

  final int value;
  final bool kept;
  final VoidCallback? onTap;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bg = kept ? MargeColors.gold : MargeColors.cream;
    final fg = kept ? MargeColors.velvet : const Color(0xFF222222);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: kept ? MargeColors.coral : Colors.black26,
            width: kept ? 3 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: CustomPaint(
          painter: _PipPainter(value: value, color: fg),
        ),
      ),
    );
  }
}

class _PipPainter extends CustomPainter {
  _PipPainter({required this.value, required this.color});

  final int value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final r = size.shortestSide * 0.09;
    Offset p(double x, double y) =>
        Offset(size.width * x, size.height * y);

    final map = <int, List<Offset>>{
      1: [p(0.5, 0.5)],
      2: [p(0.28, 0.28), p(0.72, 0.72)],
      3: [p(0.28, 0.28), p(0.5, 0.5), p(0.72, 0.72)],
      4: [p(0.28, 0.28), p(0.72, 0.28), p(0.28, 0.72), p(0.72, 0.72)],
      5: [
        p(0.28, 0.28),
        p(0.72, 0.28),
        p(0.5, 0.5),
        p(0.28, 0.72),
        p(0.72, 0.72),
      ],
      6: [
        p(0.28, 0.22),
        p(0.72, 0.22),
        p(0.28, 0.5),
        p(0.72, 0.5),
        p(0.28, 0.78),
        p(0.72, 0.78),
      ],
    };

    for (final o in map[value] ?? const <Offset>[]) {
      canvas.drawCircle(o, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PipPainter old) =>
      old.value != value || old.color != color;
}
