import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/sfx_service.dart';
import 'bank_button.dart';
import 'pot_of_gems.dart' show GemArt, PotOfGems;

/// Pot taken (DESIGNER_SPEC §3): gems lift out of the bowl, fly to the
/// winner's seat, gather there for a beat, then continue into the Bank flow
/// (the gem bank readout in the top bar) on the same curved 500 ms paths as
/// the Bank button's particles. With no [bank] target (a bot or another
/// seat won) they settle into the seat and fade there.
///
/// Positions are global (overlay) coordinates. Purely visual: the engine has
/// already moved the gems; [onGemBanked] lets the readout tick as each one
/// lands so the count catches up with the art.
class PotWinFlight extends StatefulWidget {
  const PotWinFlight({
    super.key,
    required this.from,
    required this.seat,
    required this.gems,
    required this.onDone,
    this.bank,
    this.sfx,
    this.onGemBanked,
  });

  final Offset from;
  final Offset seat;
  final Offset? bank;

  /// Sprites in flight (see [spritesFor]).
  final int gems;
  final VoidCallback onDone;
  final SfxService? sfx;

  /// Called with the sprite index each time one reaches [bank].
  final ValueChanged<int>? onGemBanked;

  static const liftMs = 120;
  static const toSeatMs = 450;
  static const holdMs = 120;
  static const toBankMs = BankButton.particleFlightMs; // same as Bank flow
  static const fadeMs = 200;
  static const staggerMs = 30;
  static const minSprites = 4;
  static const maxTinks = 8;

  /// One sprite per ante unit won, 4..12 so even a small pot reads.
  static int spritesFor(int amount, int ante) {
    if (amount <= 0) return 0;
    final per = ante <= 0 ? 1 : ante;
    return (amount ~/ per).clamp(minSprites, PotOfGems.maxGemsPerDrop);
  }

  /// Total runtime for [gems] sprites.
  static Duration durationFor(int gems, {required bool toBank}) => Duration(
    milliseconds:
        liftMs +
        toSeatMs +
        holdMs +
        (toBank ? toBankMs : fadeMs) +
        staggerMs * math.max(0, gems - 1),
  );

  @override
  State<PotWinFlight> createState() => _PotWinFlightState();
}

class _PotWinFlightState extends State<PotWinFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<Offset> _scatter; // per-gem start jitter inside the bowl
  int _bankedMask = 0;
  int _banked = 0;

  bool get _toBank => widget.bank != null;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(widget.gems * 131 + 7);
    _scatter = [
      for (var i = 0; i < widget.gems; i++)
        Offset((rnd.nextDouble() - 0.5) * 70, (rnd.nextDouble() - 0.5) * 14),
    ];
    _c = AnimationController(
      vsync: this,
      duration: PotWinFlight.durationFor(widget.gems, toBank: _toBank),
    )..addListener(_tick);
    _c.forward().whenComplete(() {
      _tick();
      widget.onDone();
    });
  }

  double get _ms => _c.value * _c.duration!.inMilliseconds;

  static const _seatAt = PotWinFlight.liftMs + PotWinFlight.toSeatMs;
  static const _leaveSeatAt = _seatAt + PotWinFlight.holdMs;

  void _tick() {
    if (!_toBank) return;
    for (var i = 0; i < widget.gems; i++) {
      if ((_bankedMask & (1 << i)) != 0) continue;
      final local = _ms - i * PotWinFlight.staggerMs;
      if (local >= _leaveSeatAt + PotWinFlight.toBankMs || _c.isCompleted) {
        _bankedMask |= 1 << i;
        if (_banked++ < PotWinFlight.maxTinks) widget.sfx?.gemLanded();
        widget.onGemBanked?.call(i);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Offset _bezier(Offset a, Offset m, Offset b, double q) =>
      a * ((1 - q) * (1 - q)) + m * (2 * (1 - q) * q) + b * (q * q);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final kids = <Widget>[];
          for (var i = 0; i < widget.gems; i++) {
            final t = _ms - i * PotWinFlight.staggerMs;
            if (t < 0) continue;
            final start = widget.from + _scatter[i];
            Offset p;
            var size = 24.0;
            var opacity = 1.0;
            if (t < PotWinFlight.liftMs) {
              // Lift out of the pile.
              final q = Curves.easeOut.transform(t / PotWinFlight.liftMs);
              p = start - Offset(0, 18 * q);
            } else if (t < _seatAt) {
              final q = Curves.easeInOut.transform(
                (t - PotWinFlight.liftMs) / PotWinFlight.toSeatMs,
              );
              final a = start - const Offset(0, 18);
              final m = Offset(
                (a.dx + widget.seat.dx) / 2 + (i.isEven ? 1 : -1) * 14.0 * i,
                math.min(a.dy, widget.seat.dy) - 40,
              );
              p = _bezier(a, m, widget.seat, q);
            } else if (t < _leaveSeatAt) {
              // Gather on the winner's seat: a small hop.
              final q = (t - _seatAt) / PotWinFlight.holdMs;
              p = widget.seat - Offset(0, 6 * math.sin(q * math.pi));
            } else if (_toBank) {
              final q0 = ((t - _leaveSeatAt) / PotWinFlight.toBankMs).clamp(
                0.0,
                1.0,
              );
              if (q0 >= 1) continue; // landed in the bank
              final q = Curves.easeInOut.transform(q0);
              final to = widget.bank!;
              final spread = (i - (widget.gems - 1) / 2) * 18.0;
              final m = Offset(
                (widget.seat.dx + to.dx) / 2 + spread,
                math.min(widget.seat.dy, to.dy) +
                    (widget.seat.dy - to.dy).abs() * 0.35,
              );
              p = _bezier(widget.seat, m, to, q);
              size = 24 * (1 - 0.35 * q);
            } else {
              final q = ((t - _leaveSeatAt) / PotWinFlight.fadeMs).clamp(
                0.0,
                1.0,
              );
              if (q >= 1) continue;
              p = widget.seat;
              opacity = 1 - q;
              size = 24 * (1 - 0.4 * q);
            }
            kids.add(
              Positioned(
                left: p.dx - size / 2,
                top: p.dy - size / 2,
                width: size,
                height: size,
                child: Opacity(
                  opacity: opacity,
                  child: Image.asset(GemArt.gem(i), gaplessPlayback: true),
                ),
              ),
            );
          }
          return Stack(children: kids);
        },
      ),
    );
  }
}
