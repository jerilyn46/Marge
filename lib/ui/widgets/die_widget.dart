import 'package:flutter/material.dart';

import '../../cosmetics/dice_skin.dart';
import '../theme/marge_theme.dart';

class DieWidget extends StatelessWidget {
  const DieWidget({
    super.key,
    required this.value,
    required this.kept,
    this.onTap,
    this.size = 72,
    this.enabled = true,
    this.theme,
  });

  final int value;
  final bool kept;
  final VoidCallback? onTap;
  final double size;
  final bool enabled;
  final DiceSkinTheme? theme;

  static const DiceSkinTheme _fallback = DiceSkinTheme(
    face: MargeColors.cream,
    faceKept: MargeColors.gold,
    pip: Color(0xFF222222),
    pipKept: MargeColors.velvet,
    border: Color(0x42000000),
    borderKept: MargeColors.coral,
  );

  @override
  Widget build(BuildContext context) {
    final t = theme ?? _fallback;
    final bg = kept ? t.faceKept : t.face;
    final fg = kept ? t.pipKept : t.pip;
    final border = kept ? t.borderKept : t.border;

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
            color: border,
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
          painter: _DieFacePainter(
            value: value,
            pipColor: fg,
            pattern: t.pattern,
            patternColor: t.patternColor ?? fg.withValues(alpha: 0.2),
          ),
        ),
      ),
    );
  }
}

class _DieFacePainter extends CustomPainter {
  _DieFacePainter({
    required this.value,
    required this.pipColor,
    required this.pattern,
    required this.patternColor,
  });

  final int value;
  final Color pipColor;
  final DiceSkinPattern pattern;
  final Color patternColor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintPattern(canvas, size);
    final paint = Paint()..color = pipColor;
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

  void _paintPattern(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = patternColor
      ..style = PaintingStyle.fill;
    switch (pattern) {
      case DiceSkinPattern.none:
        break;
      case DiceSkinPattern.stripes:
        paint.strokeWidth = size.width * 0.08;
        paint.style = PaintingStyle.stroke;
        for (var i = 0; i < 4; i++) {
          final x = size.width * (0.15 + i * 0.22);
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
      case DiceSkinPattern.sparkle:
        final s = size.shortestSide * 0.06;
        void star(double x, double y) {
          canvas.drawCircle(Offset(size.width * x, size.height * y), s, paint);
        }
        star(0.18, 0.18);
        star(0.82, 0.22);
        star(0.2, 0.8);
        star(0.78, 0.78);
      case DiceSkinPattern.dots:
        final s = size.shortestSide * 0.035;
        for (var row = 0; row < 4; row++) {
          for (var col = 0; col < 4; col++) {
            canvas.drawCircle(
              Offset(
                size.width * (0.2 + col * 0.2),
                size.height * (0.2 + row * 0.2),
              ),
              s,
              paint,
            );
          }
        }
      case DiceSkinPattern.bones:
        final bone = Paint()
          ..color = patternColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.045
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(size.width * 0.22, size.height * 0.22),
          Offset(size.width * 0.78, size.height * 0.78),
          bone,
        );
        canvas.drawLine(
          Offset(size.width * 0.78, size.height * 0.22),
          Offset(size.width * 0.22, size.height * 0.78),
          bone,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _DieFacePainter old) =>
      old.value != value ||
      old.pipColor != pipColor ||
      old.pattern != pattern ||
      old.patternColor != patternColor;
}
