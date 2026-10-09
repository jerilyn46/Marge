import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../cosmetics/dice_skin.dart';
import '../../services/sfx_service.dart';
import '../theme/marge_theme.dart';
import '../widgets/die_widget.dart';

/// A six-face die drawn in 3D: Matrix4 perspective (setEntry(3,2,0.0015))
/// plus rotateX/Y/Z, using the equipped skin's face art (DESIGNER_SPEC §1).
/// At rotation (0,0,0) [value] faces the player; the tray adds a small
/// resting tilt so the cube reads as 3D.
class DiceCube extends StatelessWidget {
  const DiceCube({
    super.key,
    required this.value,
    this.size = 72,
    this.rx = restRx,
    this.ry = restRy,
    this.rz = 0,
    this.theme,
    this.kept = false,
  });

  final int value;
  final double size;
  final double rx;
  final double ry;
  final double rz;
  final DiceSkinTheme? theme;
  final bool kept;

  /// Resting tilt: top and right faces just visible.
  static const restRx = 0.30;
  static const restRy = 0.26;
  static const perspective = 0.0015;

  /// Faces as (value, face rotation). Opposite faces sum to 7.
  static List<(int, Matrix4)> facesFor(int value, double half) {
    final v = value.clamp(1, 6);
    final used = {v, 7 - v};
    final top = [1, 2, 3, 4, 5, 6].firstWhere((x) => !used.contains(x));
    used.addAll({top, 7 - top});
    final right = [1, 2, 3, 4, 5, 6].firstWhere((x) => !used.contains(x));
    Matrix4 f(Matrix4 rot) =>
        rot..multiply(Matrix4.translationValues(0, 0, -half));
    return [
      (v, f(Matrix4.identity())),
      (7 - v, f(Matrix4.rotationY(math.pi))),
      (top, f(Matrix4.rotationX(-math.pi / 2))),
      (7 - top, f(Matrix4.rotationX(math.pi / 2))),
      (right, f(Matrix4.rotationY(math.pi / 2))),
      (7 - right, f(Matrix4.rotationY(-math.pi / 2))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final half = size / 2;
    final rot = Matrix4.identity()
      ..rotateX(rx)
      ..rotateY(ry)
      ..rotateZ(rz);
    final faces = <(double, Widget)>[];
    for (final (faceValue, faceM) in facesFor(value, half)) {
      final m = rot.multiplied(faceM);
      // Outward normal is (0,0,-1) in face space; the viewer looks from -z.
      final nz = -m.entry(2, 2);
      if (nz > -0.02) continue; // back-facing
      final depth = m.entry(2, 3);
      final light = (-nz).clamp(0.0, 1.0);
      // Light from above: faces whose normal points up (screen −y) get a lift.
      final ny = -m.entry(1, 2);
      final shade = (0.5 * (1 - light) - (ny < 0 ? -0.3 * ny : 0)).clamp(
        0.0,
        0.6,
      );
      final pm = Matrix4.identity()
        ..setEntry(3, 2, perspective)
        ..multiply(m);
      faces.add((
        depth,
        Transform(
          alignment: Alignment.center,
          transform: pm,
          child: Stack(
            children: [
              DieFace(
                value: faceValue,
                size: size,
                theme: theme,
                radius: size * 0.08,
              ),
              if (shade > 0.01)
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: shade),
                    borderRadius: BorderRadius.circular(size * 0.08),
                  ),
                ),
            ],
          ),
        ),
      ));
    }
    faces.sort((a, b) => b.$1.compareTo(a.$1)); // far first
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (kept)
            Positioned(
              left: -size * 0.14,
              top: -size * 0.14,
              right: -size * 0.14,
              bottom: -size * 0.14,
              child: DecoratedBox(
                key: const ValueKey('kept-outline'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.22),
                  border: Border.all(color: MargeColors.gold, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: MargeColors.gold.withValues(alpha: 0.45),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          for (final f in faces) f.$2,
        ],
      ),
    );
  }
}

/// Seeded per-roll, per-die tumble parameters.
class _Tumble {
  _Tumble(math.Random r)
    : turnsX = 2 + r.nextInt(2),
      turnsY = 2 + r.nextInt(2),
      offX = r.nextDouble() * 2 * math.pi,
      offY = r.nextDouble() * 2 * math.pi,
      zSpin = (r.nextDouble() - 0.5) * math.pi,
      drift = (r.nextDouble() * 2 - 1) * 8,
      flicker = [for (var k = 0; k < 8; k++) 1 + r.nextInt(6)];
  final int turnsX;
  final int turnsY;
  final double offX;
  final double offY;
  final double zSpin;
  final double drift; // ±8 dp

  /// Lite path: faces flashed during the tumble (seeded, then the result).
  final List<int> flicker;
}

/// The three dice on the table. Animates only when [rollSerial] changes:
/// the faces are already decided ([values] is the engine result) and the
/// tumble lands exactly on them. Kept dice ([animate] false) never move.
///
/// Timeline per die (60 ms stagger): 0–120 lift (1.0→1.08, −12 dp, shadow
/// shrinks), 120–650 tumble (2–3 turns X/Y, some Z, easeOutCubic, ±8 dp
/// drift), 650–800 land on the result with one bounce (1.0→0.94→1.0,
/// +4 dp), 800–900 settle. [onSettled] fires when the roll has settled so
/// the screen can keep input locked until then. Reduce Motion: 200 ms fade/scale.
///
/// [lite] (Settings → Simple dice; for low-end phones): the same timeline,
/// sounds and haptics, but each moving die is ONE flat face (no 6-face cube,
/// no perspective): it spins in-plane 2–3 turns while flashing seeded faces,
/// then snaps to the result and bounces. Settled dice look the same as the
/// full path. Chosen over a pre-rendered sprite sheet because no per-skin
/// sheets exist and this needs no art. Reduce Motion still wins.
class DiceTray extends StatefulWidget {
  const DiceTray({
    super.key,
    required this.values,
    required this.kept,
    required this.animate,
    required this.rollSerial,
    this.enabled = const [false, false, false],
    this.onTap,
    this.size = 72,
    this.theme,
    this.sfx,
    this.dim = false,
    this.onSettled,
    this.lite = false,
  });

  /// Lighter 2D tumble for low-end devices (see class docs).
  final bool lite;

  final List<int> values;
  final List<bool> kept;
  final List<bool> animate;
  final int rollSerial;
  final List<bool> enabled;
  final ValueChanged<int>? onTap;
  final double size;
  final DiceSkinTheme? theme;
  final SfxService? sfx;
  final bool dim;

  /// Called with [rollSerial] once that roll has fully settled (from a
  /// ticker/post-frame callback, never during build).
  final ValueChanged<int>? onSettled;

  static const dieMs = 900;
  static const staggerMs = 60;
  static const liftEnd = 120;
  static const tumbleEnd = 650;
  static const landEnd = 800;
  static const reduceMotionMs = 200;

  @override
  State<DiceTray> createState() => DiceTrayState();
}

class DiceTrayState extends State<DiceTray>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this)
    ..addListener(_tick)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _settled();
    });

  List<_Tumble> _tumbles = const [];
  List<bool> _moving = const [false, false, false];
  int _landedMask = 0;
  bool _reduce = false;

  /// True from the throw until every die has settled.
  bool get settling => _c.isAnimating;

  @override
  void didUpdateWidget(DiceTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rollSerial != oldWidget.rollSerial) _start();
  }

  void _start() {
    final moving = [
      for (var i = 0; i < widget.values.length; i++)
        i < widget.animate.length && widget.animate[i],
    ];
    if (!moving.contains(true)) {
      final serial = widget.rollSerial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSettled?.call(serial);
      });
      return;
    }
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final rnd = math.Random(widget.rollSerial * 7349 + 17);
    _tumbles = [for (var i = 0; i < widget.values.length; i++) _Tumble(rnd)];
    _moving = moving;
    _landedMask = 0;
    final movers = moving.where((m) => m).length;
    _c.duration = Duration(
      milliseconds: _reduce
          ? DiceTray.reduceMotionMs
          : DiceTray.dieMs + DiceTray.staggerMs * (movers - 1),
    );
    _c.forward(from: 0);
    widget.sfx?.diceThrown();
  }

  int _order(int i) {
    var k = 0;
    for (var j = 0; j < i; j++) {
      if (_moving[j]) k++;
    }
    return k;
  }

  double get _ms => _c.value * (_c.duration?.inMilliseconds ?? 0);

  double _localMs(int i) => _ms - _order(i) * DiceTray.staggerMs;

  void _tick() {
    for (var i = 0; i < _moving.length; i++) {
      if (!_moving[i] || (_landedMask & (1 << i)) != 0) continue;
      final landAt = _reduce ? DiceTray.reduceMotionMs : DiceTray.tumbleEnd;
      if (_localMs(i) >= landAt) {
        _landedMask |= 1 << i;
        widget.sfx?.dieLanded(); // ≤ 3 per roll (one per moving die)
      }
    }
    setState(() {});
  }

  void _settled() {
    for (var i = 0; i < _moving.length; i++) {
      if (_moving[i] && (_landedMask & (1 << i)) == 0) {
        _landedMask |= 1 << i;
        widget.sfx?.dieLanded();
      }
    }
    setState(() => _moving = const [false, false, false]);
    widget.onSettled?.call(widget.rollSerial);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _die(int i) {
    final value = widget.values[i];
    final kept = i < widget.kept.length && widget.kept[i];
    var rx = DiceCube.restRx, ry = DiceCube.restRy, rz = 0.0;
    var dy = 0.0, dx = 0.0, scale = 1.0, shadow = 1.0, opacity = 1.0;
    final moving = _c.isAnimating && i < _moving.length && _moving[i];
    if (moving && !_reduce && widget.lite) return _liteDie(i, value);
    if (moving && _reduce) {
      final t = (_ms / DiceTray.reduceMotionMs).clamp(0.0, 1.0);
      opacity = t;
      scale = 0.9 + 0.1 * t;
    } else if (moving) {
      final t = _localMs(i);
      final tb = _tumbles[i];
      if (t <= 0) {
        // Waiting on the stagger: hold the tumble's start pose.
        rx += 2 * math.pi * tb.turnsX + tb.offX;
        ry += 2 * math.pi * tb.turnsY + tb.offY;
        rz = tb.zSpin;
      } else if (t < DiceTray.liftEnd) {
        final q = Curves.easeOut.transform(t / DiceTray.liftEnd);
        scale = 1 + 0.08 * q;
        dy = -12 * q;
        shadow = 1 - 0.4 * q;
        rx += 2 * math.pi * tb.turnsX + tb.offX;
        ry += 2 * math.pi * tb.turnsY + tb.offY;
        rz = tb.zSpin;
      } else if (t < DiceTray.tumbleEnd) {
        final q =
            (t - DiceTray.liftEnd) / (DiceTray.tumbleEnd - DiceTray.liftEnd);
        final rem = 1 - Curves.easeOutCubic.transform(q);
        rx += (2 * math.pi * tb.turnsX + tb.offX) * rem;
        ry += (2 * math.pi * tb.turnsY + tb.offY) * rem;
        rz = tb.zSpin * rem;
        scale = 1.08 - 0.08 * q;
        dy = -12 * (1 - q);
        dx = tb.drift * math.sin(q * math.pi);
        shadow = 0.6 + 0.2 * q;
      } else if (t < DiceTray.landEnd) {
        // Snapped to the result; one bounce.
        final q =
            (t - DiceTray.tumbleEnd) / (DiceTray.landEnd - DiceTray.tumbleEnd);
        final b = math.sin(q * math.pi);
        scale = 1 - 0.06 * b;
        dy = 4 * b;
        shadow = 0.8 + 0.1 * q;
      } else {
        final q = ((t - DiceTray.landEnd) / (DiceTray.dieMs - DiceTray.landEnd))
            .clamp(0.0, 1.0);
        shadow = 0.9 + 0.1 * q;
      }
    }
    final s = widget.size;
    final canTap =
        !settling &&
        i < widget.enabled.length &&
        widget.enabled[i] &&
        widget.onTap != null;
    return GestureDetector(
      key: ValueKey('die-$i'),
      behavior: HitTestBehavior.opaque,
      onTap: canTap ? () => widget.onTap!(i) : null,
      child: SizedBox(
        width: s + 20,
        height: s + 44,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              bottom: 0,
              child: Transform.translate(
                offset: Offset(dx, 0),
                child: Container(
                  width: s * 0.95 * shadow,
                  height: s * 0.22 * shadow,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(
                      Radius.elliptical(s * 0.5, s * 0.11),
                    ),
                    color: Colors.black.withValues(alpha: 0.32 * shadow),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(dx, dy - 6),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: DiceCube(
                    value: value,
                    size: s,
                    rx: rx,
                    ry: ry,
                    rz: rz,
                    theme: widget.theme,
                    kept: kept && !moving,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Lite tumble: one flat face, in-plane spin, seeded face flashes.
  Widget _liteDie(int i, int value) {
    final s = widget.size;
    final t = _localMs(i);
    final tb = _tumbles[i];
    final spin = 2 * math.pi * tb.turnsX + tb.zSpin;
    var face = value;
    var angle = 0.0, dy = 0.0, dx = 0.0, scale = 1.0, shadow = 1.0;
    if (t < DiceTray.liftEnd) {
      final q = Curves.easeOut.transform((t / DiceTray.liftEnd).clamp(0, 1));
      scale = 1 + 0.08 * q;
      dy = -12 * q;
      shadow = 1 - 0.4 * q;
      angle = spin;
      face = tb.flicker[0];
    } else if (t < DiceTray.tumbleEnd) {
      final q =
          (t - DiceTray.liftEnd) / (DiceTray.tumbleEnd - DiceTray.liftEnd);
      angle = spin * (1 - Curves.easeOutCubic.transform(q));
      scale = 1.08 - 0.08 * q;
      dy = -12 * (1 - q);
      dx = tb.drift * math.sin(q * math.pi);
      shadow = 0.6 + 0.2 * q;
      face =
          tb.flicker[(q * tb.flicker.length).floor().clamp(
            0,
            tb.flicker.length - 1,
          )];
    } else if (t < DiceTray.landEnd) {
      final q =
          (t - DiceTray.tumbleEnd) / (DiceTray.landEnd - DiceTray.tumbleEnd);
      final b = math.sin(q * math.pi);
      scale = 1 - 0.06 * b;
      dy = 4 * b;
      shadow = 0.8 + 0.1 * q;
    } else {
      shadow =
          0.9 +
          0.1 *
              ((t - DiceTray.landEnd) / (DiceTray.dieMs - DiceTray.landEnd))
                  .clamp(0.0, 1.0);
    }
    return SizedBox(
      key: ValueKey('die-$i'),
      width: s + 20,
      height: s + 44,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 0,
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: Container(
                width: s * 0.95 * shadow,
                height: s * 0.22 * shadow,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(
                    Radius.elliptical(s * 0.5, s * 0.11),
                  ),
                  color: Colors.black.withValues(alpha: 0.32 * shadow),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(dx, dy - 6),
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(
                scale: scale,
                child: DieFace(
                  key: ValueKey('lite-face-$i'),
                  value: face,
                  size: s,
                  theme: widget.theme,
                  radius: s * 0.08,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.dim ? 0.35 : 1,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _die(i),
          ],
        ],
      ),
    );
  }
}
