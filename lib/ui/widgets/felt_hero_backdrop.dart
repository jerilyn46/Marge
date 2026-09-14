import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/marge_theme.dart';

/// Soft felt oval with wood edge and gentle lamp vignette for the lobby hero.
class FeltHeroBackdrop extends StatelessWidget {
  const FeltHeroBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _FeltTablePainter(),
      child: child,
    );
  }
}

class _FeltTablePainter extends CustomPainter {
  const _FeltTablePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF2A2118),
          MargeColors.velvet,
          Color(0xFF14100C),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    final table = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.42),
        width: size.width * 0.92,
        height: math.min(size.height * 0.55, 320),
      ),
      const Radius.circular(160),
    );

    final wood = Paint()
      ..color = MargeColors.wood
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18;
    canvas.drawRRect(table, wood);

    final woodHighlight = Paint()
      ..color = MargeColors.woodEdge.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRRect(table.deflate(6), woodHighlight);

    final felt = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.2),
        radius: 0.95,
        colors: [
          MargeColors.feltLight.withValues(alpha: 0.95),
          MargeColors.felt,
          const Color(0xFF163628),
        ],
      ).createShader(table.outerRect);
    canvas.drawRRect(table.deflate(10), felt);

    final lamp = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.55),
        radius: 0.75,
        colors: [
          MargeColors.lamp.withValues(alpha: 0.22),
          MargeColors.lamp.withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, lamp);

    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.05,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.35),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Tiny painted gem chip accent (playful chip, not cash).
class GemChipAccent extends StatelessWidget {
  const GemChipAccent({super.key, this.size = 18, this.color = MargeColors.gold});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GemChipPainter(color),
    );
  }
}

class _GemChipPainter extends CustomPainter {
  _GemChipPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = color);
    canvas.drawCircle(
      c,
      r * 0.72,
      Paint()
        ..color = MargeColors.cream.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      Offset(c.dx - r * 0.25, c.dy - r * 0.25),
      r * 0.18,
      Paint()..color = MargeColors.cream.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _GemChipPainter oldDelegate) =>
      oldDelegate.color != color;
}
