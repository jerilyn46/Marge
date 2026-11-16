import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/pot_win.dart';
import '../../services/sfx_service.dart';
import '../theme/marge_theme.dart';
import '../visuals/pot_of_gems.dart' show GemArt;

/// The pot-win moment: a rounded gold-edged card naming the winner and the
/// pot, with a short reason line. Over ~2.6 s the card pops in, a handful
/// of gems fly from the pot bowl into the winner's bank, the amount counts
/// up, and on landing a small gem burst plays with the pot-win stinger and
/// a haptic (heavy when you won, medium otherwise; both follow Settings).
/// Tap anywhere on the card to skip to the end. Used on the offline results
/// screen and on the online result screen.
class PotWinCard extends StatefulWidget {
  const PotWinCard({super.key, required this.win, this.sfx});

  final PotWin win;

  /// Null = silent (no stinger / haptic).
  final SfxService? sfx;

  /// Whole moment, pop-in to burst.
  static const duration = Duration(milliseconds: 2600);

  /// Fraction of [duration] when the last gem lands (haptic + burst).
  static const landAt = 0.82;

  @override
  State<PotWinCard> createState() => PotWinCardState();
}

class PotWinCardState extends State<PotWinCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: PotWinCard.duration,
  );
  bool _landed = false;

  /// True once the gems have landed (or the moment was skipped).
  bool get landed => _landed;

  static const _gemCount = 8;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_tick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _ctrl.value = 1;
      } else {
        _ctrl.forward();
      }
    });
  }

  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    // Warm the art so the first gem never pops in mid-flight.
    for (final path in [
      for (var i = 0; i < GemArt.colors.length; i++) GemArt.gem(i),
      GemArt.bowlBack,
      GemArt.bowlFront,
      GemArt.pile(3),
    ]) {
      precacheImage(AssetImage(path), context, onError: (_, _) {});
    }
  }

  void _tick() {
    if (!_landed && _ctrl.value >= PotWinCard.landAt) {
      _landed = true;
      final sfx = widget.sfx;
      if (sfx != null) sfx.potWinMoment(mine: widget.win.mine);
    }
  }

  /// Jump to the end of the moment (tap to skip).
  void skip() {
    if (_ctrl.value >= 1) return;
    _ctrl.stop();
    _ctrl.value = 1;
  }

  @override
  void dispose() {
    _ctrl.removeListener(_tick);
    _ctrl.dispose();
    super.dispose();
  }

  static double _seg(double t, double a, double b, [Curve c = Curves.linear]) {
    if (t <= a) return 0;
    if (t >= b) return 1;
    return c.transform((t - a) / (b - a));
  }

  @override
  Widget build(BuildContext context) {
    final win = widget.win;
    return Semantics(
      container: true,
      label: '${win.headline} ${win.gems} gems. ${win.reasonLine}.',
      child: GestureDetector(
        key: const ValueKey('pot-win-card'),
        behavior: HitTestBehavior.opaque,
        onTap: skip,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final pop = _seg(t, 0, 0.14, Curves.easeOutBack);
            final count = _seg(t, 0.14, PotWinCard.landAt, Curves.easeOutCubic);
            final shown = (win.gems * count).round();
            final after = win.bankAfter;
            final bankShown = after == null ? null : after - win.gems + shown;
            return Opacity(
              opacity: _seg(t, 0, 0.08),
              child: Transform.scale(
                scale: 0.86 + 0.14 * pop,
                child: _frame(
                  context,
                  t: t,
                  shown: shown,
                  bankShown: bankShown,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _frame(
    BuildContext context, {
    required double t,
    required int shown,
    required int? bankShown,
  }) {
    final win = widget.win;
    final burst = _seg(t, PotWinCard.landAt, 1);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            MargeColors.felt.withValues(alpha: 0.96),
            MargeColors.velvet.withValues(alpha: 0.96),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: MargeColors.gold, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: MargeColors.gold.withValues(alpha: 0.18 + 0.2 * burst),
            blurRadius: 18 + 10 * burst,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: MargeColors.gold.withValues(alpha: 0.7),
                ),
              ),
              child: Text(
                win.tag,
                key: const ValueKey('pot-win-tag'),
                style: const TextStyle(
                  color: MargeColors.gold,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            win.headline,
            key: const ValueKey('pot-win-headline'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MargeColors.gold,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 84,
            child: LayoutBuilder(
              builder: (context, box) =>
                  _stage(box.maxWidth, t, bankShown, burst),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '+$shown gems',
            key: const ValueKey('pot-win-amount'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MargeColors.cream,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            win.caption,
            key: const ValueKey('pot-win-caption'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MargeColors.cream.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            win.reasonLine,
            key: const ValueKey('pot-win-reason'),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MargeColors.cream,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Bowl (left) → winner's bank (right), gems arcing between.
  Widget _stage(double w, double t, int? bankShown, double burst) {
    const bowlW = 72.0, bowlH = 54.0, gem = 20.0;
    final win = widget.win;
    final from = Offset(bowlW / 2 + 4, 34);
    final to = Offset(w - 58, 42);
    final flying = <Widget>[];
    for (var i = 0; i < _gemCount; i++) {
      final start = 0.14 + i * 0.06;
      final p = _seg(t, start, start + 0.26, Curves.easeInOutCubic);
      if (p <= 0 || p >= 1) continue;
      final x = from.dx + (to.dx - from.dx) * p;
      final y = from.dy + (to.dy - from.dy) * p - 46 * math.sin(math.pi * p);
      // Shrink and fade into the bank so the balance stays readable.
      final sink = p < 0.75 ? 1.0 : (1 - p) / 0.25;
      final size = gem * (0.55 + 0.45 * sink);
      flying.add(
        Positioned(
          left: x - size / 2,
          top: y - size / 2,
          width: size,
          height: size,
          child: Opacity(
            opacity: sink.clamp(0.0, 1.0),
            child: Image.asset(GemArt.gem(i), gaplessPlayback: true),
          ),
        ),
      );
    }
    final drained = _seg(t, 0.14, PotWinCard.landAt);
    final pulse = burst > 0 ? 1 + 0.08 * math.sin(math.pi * burst) : 1.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 4,
          top: 34 - bowlH / 2 + 8,
          width: bowlW,
          height: bowlH,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(GemArt.bowlBack, fit: BoxFit.contain),
              Opacity(
                opacity: 1 - drained,
                child: Image.asset(GemArt.pile(3), fit: BoxFit.contain),
              ),
              Image.asset(GemArt.bowlFront, fit: BoxFit.contain),
            ],
          ),
        ),
        Positioned(
          right: 0,
          top: 18,
          child: Transform.scale(
            scale: pulse,
            child: Container(
              key: const ValueKey('pot-win-bank'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: MargeColors.gold.withValues(alpha: 0.16 + 0.2 * burst),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MargeColors.gold),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    win.mine ? 'You' : win.winnerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MargeColors.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  if (bankShown != null)
                    Text(
                      '$bankShown gems',
                      style: const TextStyle(
                        color: MargeColors.cream,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ...flying,
        if (burst > 0 && burst < 1)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _BurstPainter(center: to, progress: burst),
              ),
            ),
          ),
      ],
    );
  }
}

/// A modest ring of gem-coloured sparks around the bank on landing.
class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.center, required this.progress});
  final Offset center;
  final double progress;

  static const _colors = [
    MargeColors.gold,
    MargeColors.coral,
    MargeColors.sky,
    MargeColors.lilac,
    MargeColors.cream,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const n = 14;
    final r = 14 + 46 * Curves.easeOutCubic.transform(progress);
    for (var i = 0; i < n; i++) {
      final a = (i / n) * 2 * math.pi + 0.3;
      final c = center + Offset(math.cos(a) * r, math.sin(a) * r * 0.7);
      final paint = Paint()
        ..color = _colors[i % _colors.length].withValues(
          alpha: (1 - progress).clamp(0.0, 1.0),
        );
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a + math.pi / 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 6, height: 6),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) =>
      old.progress != progress || old.center != center;
}
