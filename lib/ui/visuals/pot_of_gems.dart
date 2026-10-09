import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/sfx_service.dart';
import '../theme/marge_theme.dart';

/// Designer asset paths (1x; Flutter resolves the 2.0x/3.0x variants).
abstract final class GemArt {
  static const colors = [
    'ruby',
    'sapphire',
    'emerald',
    'amethyst',
    'topaz',
    'aquamarine',
  ];
  static String gem(int i) =>
      'assets/visuals/gems/gem_${colors[i % colors.length]}.png';
  static String sparkle(int frame) =>
      'assets/visuals/sparkle/sparkle_${frame % 2}.png';
  static const bowlShadow = 'assets/visuals/bowl/bowl_shadow.png';
  static const bowlBack = 'assets/visuals/bowl/bowl_back.png';
  static const bowlFront = 'assets/visuals/bowl/bowl_front.png';
  static String pile(int tier) => 'assets/visuals/bowl/pile_tier$tier.png';

  /// Every image the pot can show (for precache / golden tests).
  static List<String> get potAssets => [
    bowlShadow,
    bowlBack,
    bowlFront,
    for (var t = 1; t <= 5; t++) pile(t),
    for (var i = 0; i < colors.length; i++) gem(i),
    sparkle(0),
    sparkle(1),
  ];
}

/// The pot drawn as a wooden bowl of gems (DESIGNER_SPEC §3).
///
/// Layers (README): shadow, back, pile tier N, live gems, front, sparkles.
/// Every increase drops gems in from the top (1 per ante, max 12, 450–600 ms
/// easeIn, 40 ms stagger, small bounce) and the plate number ticks up as they
/// land. A decrease (pot taken) lifts gems out and drains over ~500 ms.
/// Reduce Motion: values and tiers change instantly, nothing flies.
class PotOfGems extends StatefulWidget {
  const PotOfGems({
    super.key,
    required this.potGems,
    required this.anteGems,
    required this.seats,
    this.width = 220,
    this.sfx,
  });

  final int potGems;
  final int anteGems;
  final int seats;
  final double width;
  final SfxService? sfx;

  /// Native 1x canvas of the bowl art.
  static const canvas = Size(320, 200);

  /// Recommended landing ellipse for live gem centres (README geometry).
  static const landingCenter = Offset(160, 87);
  static const landingRx = 112.0;
  static const landingRy = 24.0;

  static const fallMs = 520; // inside the 450–600 ms window
  static const staggerMs = 40;
  static const maxGemsPerDrop = 12;
  static const maxTinksPerDrop = 8;
  static const sparkleMs = 160; // two 80 ms frames
  static const drainMs = 500;

  /// tier = clamp(pot / (ante × seats), 0..5). Any gems at all show at least
  /// tier 1 so a live pot is never drawn as an empty bowl.
  static int tierFor(int pot, int ante, int seats) {
    if (pot <= 0) return 0;
    final unit = ante * seats;
    if (unit <= 0) return 1;
    return (pot ~/ unit).clamp(1, 5);
  }

  /// Gems that fly for an increase of [delta]: one per ante unit, 1..12.
  static int gemsForDelta(int delta, int ante) {
    if (delta <= 0) return 0;
    final per = ante <= 0 ? 1 : ante;
    return (delta ~/ per).clamp(1, maxGemsPerDrop);
  }

  @override
  State<PotOfGems> createState() => _PotOfGemsState();
}

enum _Mode { idle, drop, drain }

class _Flyer {
  _Flyer({
    required this.start,
    required this.end,
    required this.color,
    required this.spin,
    required this.delayMs,
  });
  final Offset start; // canvas coords (1x)
  final Offset end;
  final int color;
  final double spin; // radians over the flight
  final int delayMs;
}

class _PotOfGemsState extends State<PotOfGems>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this)
    ..addListener(_tick)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });

  _Mode _mode = _Mode.idle;
  late int _shown = widget.potGems;
  int _from = 0;
  int _to = 0;
  List<_Flyer> _flyers = const [];
  int _landed = 0;
  int _dropSerial = 0;
  int _fromTier = 0;

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  int _tierOf(int pot) =>
      PotOfGems.tierFor(pot, widget.anteGems, widget.seats);

  @override
  void didUpdateWidget(PotOfGems old) {
    super.didUpdateWidget(old);
    if (widget.potGems == old.potGems) return;
    final from = _shown;
    final to = widget.potGems;
    final tierBefore = _tierOf(from);
    if (_reduceMotion || from == to) {
      _c.stop();
      setState(() {
        _mode = _Mode.idle;
        _flyers = const [];
        _shown = to;
      });
      if (_tierOf(to) > tierBefore) widget.sfx?.potTierUp();
      return;
    }
    _from = from;
    _to = to;
    _fromTier = tierBefore;
    _landed = 0;
    _dropSerial++;
    final rnd = math.Random(7919 * _dropSerial + to);
    if (to > from) {
      final n = PotOfGems.gemsForDelta(to - from, widget.anteGems);
      _flyers = [
        for (var i = 0; i < n; i++) _newFlyer(rnd, i, falling: true),
      ];
      _mode = _Mode.drop;
      _c.duration = Duration(
        milliseconds: PotOfGems.fallMs +
            PotOfGems.staggerMs * (n - 1) +
            PotOfGems.sparkleMs,
      );
      widget.sfx?.potDropStarted();
    } else {
      final n = (2 + 2 * tierBefore).clamp(2, PotOfGems.maxGemsPerDrop);
      _flyers = [
        for (var i = 0; i < n; i++) _newFlyer(rnd, i, falling: false),
      ];
      _mode = _Mode.drain;
      _c.duration = const Duration(milliseconds: PotOfGems.drainMs);
    }
    _c.forward(from: 0);
    setState(() {});
  }

  _Flyer _newFlyer(math.Random rnd, int i, {required bool falling}) {
    // Uniform point in the landing ellipse.
    final a = rnd.nextDouble() * 2 * math.pi;
    final r = math.sqrt(rnd.nextDouble());
    final land = PotOfGems.landingCenter +
        Offset(
          math.cos(a) * r * PotOfGems.landingRx,
          math.sin(a) * r * PotOfGems.landingRy,
        );
    final sky = Offset(land.dx + (rnd.nextDouble() - 0.5) * 60, -28);
    return _Flyer(
      start: falling ? sky : land,
      end: falling ? land : Offset(land.dx + (rnd.nextDouble() - 0.5) * 40, -40),
      color: rnd.nextInt(GemArt.colors.length),
      spin: (rnd.nextDouble() - 0.5) * math.pi,
      delayMs: falling ? i * PotOfGems.staggerMs : i * 20,
    );
  }

  double get _elapsedMs =>
      _c.value * (_c.duration?.inMilliseconds ?? 0).toDouble();

  double _progress(_Flyer f, int flightMs) =>
      ((_elapsedMs - f.delayMs) / flightMs).clamp(0.0, 1.0);

  void _tick() {
    if (_mode == _Mode.drop) {
      var landed = 0;
      for (final f in _flyers) {
        if (_progress(f, PotOfGems.fallMs) >= 1) landed++;
      }
      if (landed != _landed) {
        for (var k = _landed; k < landed; k++) {
          if (k < PotOfGems.maxTinksPerDrop) widget.sfx?.gemLanded();
        }
        final before = _tierOf(_shown);
        _landed = landed;
        final next = landed >= _flyers.length
            ? _to
            : _from + ((_to - _from) * landed / _flyers.length).round();
        _shown = next;
        if (_tierOf(next) > before) widget.sfx?.potTierUp();
      }
    } else if (_mode == _Mode.drain) {
      _shown = (_from + (_to - _from) * _c.value).round();
    }
    setState(() {});
  }

  void _finish() {
    final before = _tierOf(_shown);
    setState(() {
      _mode = _Mode.idle;
      _flyers = const [];
      _shown = _to;
    });
    if (_tierOf(_to) > before && _tierOf(_to) > _fromTier) {
      widget.sfx?.potTierUp();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.width / PotOfGems.canvas.width;
    final h = PotOfGems.canvas.height * s;
    final tier = _tierOf(_shown);
    final drainT = _mode == _Mode.drain ? _c.value : 1.0;
    final oldTier = _mode == _Mode.drain ? _tierOf(_from) : tier;
    final gemPx = 24 * s;

    Widget layer(String asset, {double opacity = 1}) => Positioned.fill(
      child: Opacity(
        opacity: opacity,
        child: Image.asset(asset, fit: BoxFit.fill, gaplessPlayback: true),
      ),
    );

    final flyers = <Widget>[];
    final sparkles = <Widget>[];
    for (final f in _flyers) {
      final flight = _mode == _Mode.drop ? PotOfGems.fallMs : 360;
      final p = _progress(f, flight);
      if (_elapsedMs < f.delayMs) continue;
      Offset pos;
      double scaleY = 1;
      double opacity = 1;
      if (_mode == _Mode.drop) {
        // 85 % fall (easeIn on y), 15 % one small bounce.
        const fallPart = 0.85;
        if (p < fallPart) {
          final q = p / fallPart;
          pos = Offset(
            f.start.dx + (f.end.dx - f.start.dx) * q,
            f.start.dy + (f.end.dy - f.start.dy) * Curves.easeIn.transform(q),
          );
        } else {
          final q = (p - fallPart) / (1 - fallPart);
          pos = f.end - Offset(0, 4 * math.sin(q * math.pi));
          scaleY = 1 - 0.2 * q; // settle into the pile squash
        }
        final sinceLand =
            _elapsedMs - f.delayMs - PotOfGems.fallMs.toDouble();
        if (sinceLand >= 0 && sinceLand < PotOfGems.sparkleMs) {
          final frame = (sinceLand ~/ 80);
          sparkles.add(
            Positioned(
              left: (f.end.dx - 16) * s,
              top: (f.end.dy - 22) * s,
              width: 32 * s,
              height: 32 * s,
              child: Image.asset(GemArt.sparkle(frame), gaplessPlayback: true),
            ),
          );
        }
      } else {
        final q = Curves.easeOut.transform(p);
        pos = Offset.lerp(f.start, f.end, q)!;
        opacity = 1 - p;
      }
      flyers.add(
        Positioned(
          left: pos.dx * s - gemPx / 2,
          top: pos.dy * s - gemPx / 2,
          width: gemPx,
          height: gemPx,
          child: Opacity(
            opacity: opacity,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(1, scaleY, 1)
                ..rotateZ(f.spin * p),
              child: Image.asset(GemArt.gem(f.color), gaplessPlayback: true),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Pot, $_shown gems',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.width,
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                layer(GemArt.bowlShadow),
                layer(GemArt.bowlBack),
                if (_mode == _Mode.drain && oldTier > 0 && oldTier != tier)
                  layer(GemArt.pile(oldTier), opacity: 1 - drainT),
                if (tier > 0)
                  layer(
                    GemArt.pile(tier),
                    opacity: _mode == _Mode.drain && oldTier != tier
                        ? drainT
                        : 1,
                  ),
                ...flyers,
                layer(GemArt.bowlFront),
                ...sparkles,
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            key: const ValueKey('pot-plate'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF3A2412).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE8C27A), width: 1.5),
            ),
            child: Text(
              'Pot · $_shown',
              style: const TextStyle(
                color: MargeColors.cream,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
