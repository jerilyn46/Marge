import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/sfx_service.dart';
import '../theme/marge_theme.dart';
import 'pot_of_gems.dart' show GemArt;

/// The only action after a winning roll (DESIGNER_SPEC §2).
///
/// Full-width ~64 dp gold pill: 'Bank' with '+N gems' under it. Enters
/// ~150 ms after it mounts (scale 0.85 → 1.05 → 1.0 over 350 ms, fade in),
/// idles with a 600 ms sheen every 2.2 s and a 1.2 s 1.0 → 1.03 pulse.
/// Press 0.96. One tap only: it disables at once, bursts 10 gems toward
/// [particleTargetKey] (500 ms each, curved, 30 ms stagger), then calls
/// [onBank]. Reduce Motion: no enter/pulse, static sheen, banks at once.
class BankButton extends StatefulWidget {
  const BankButton({
    super.key,
    required this.amountGems,
    required this.onBank,
    this.enabled = true,
    this.sfx,
    this.particleTargetKey,
  });

  final int amountGems;
  final VoidCallback onBank;
  final bool enabled;
  final SfxService? sfx;
  final GlobalKey? particleTargetKey;

  static const height = 64.0;
  static const enterDelay = Duration(milliseconds: 150);
  static const enterDuration = Duration(milliseconds: 350);
  static const sheenPeriod = Duration(milliseconds: 2200);
  static const sheenSweepMs = 600;
  static const pulsePeriod = Duration(milliseconds: 1200);
  static const particleCount = 10; // spec: 8–12
  static const particleFlightMs = 500;
  static const particleStaggerMs = 30;

  static Duration get burstDuration => Duration(
    milliseconds:
        particleFlightMs + particleStaggerMs * (particleCount - 1),
  );

  @override
  State<BankButton> createState() => _BankButtonState();
}

class _BankButtonState extends State<BankButton> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: BankButton.enterDelay + BankButton.enterDuration,
  );
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: BankButton.sheenPeriod,
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: BankButton.pulsePeriod,
  );

  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: BankButton.burstDuration,
  );

  bool _pressed = false;
  bool _chimed = false;
  bool _tapped = false;
  bool _started = false;

  static final _enterScale = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0.85), weight: 150),
    TweenSequenceItem(
      tween: Tween(begin: 0.85, end: 1.05).chain(CurveTween(curve: Curves.easeOut)),
      weight: 230,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.05, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 120,
    ),
  ]);

  static final _enterOpacity = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 150),
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 200),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 150),
  ]);

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_reduceMotion) {
      _enter.value = 1;
      widget.sfx?.bankEntered();
      return;
    }
    const delayFrac = 150 / 500;
    _enter.addListener(() {
      if (!_chimed && _enter.value >= delayFrac) {
        _chimed = true;
        widget.sfx?.bankEntered();
      }
    });
    _enter.forward().whenComplete(() {
      if (!mounted || _reduceMotion) return;
      _sheen.repeat();
      _pulse.repeat();
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _burst.dispose();
    _sheen.dispose();
    _pulse.dispose();
    super.dispose();
  }

  bool get _canTap => widget.enabled && !_tapped && _enter.isCompleted;

  void _onTap() {
    if (!_canTap) return;
    setState(() {
      _tapped = true; // one tap only, effective immediately
      _pressed = false;
    });
    _sheen.stop();
    _pulse.stop();
    widget.sfx?.bankTapped();
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    if (_reduceMotion || overlay == null || box == null || !box.hasSize) {
      widget.onBank();
      return;
    }
    final from = box.localToGlobal(box.size.center(Offset.zero));
    final targetBox =
        widget.particleTargetKey?.currentContext?.findRenderObject()
            as RenderBox?;
    final to = targetBox != null && targetBox.hasSize
        ? targetBox.localToGlobal(targetBox.size.center(Offset.zero))
        : Offset(MediaQuery.sizeOf(context).width / 2, 24);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => GemBurst(
        from: from,
        to: to,
        onDone: () {
          entry.remove();
        },
      ),
    );
    overlay.insert(entry);
    // Bank lands as the gems arrive; the turn then resets per the rule.
    _burst.forward().whenComplete(() {
      if (mounted) widget.onBank();
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduce = _reduceMotion;
    final active = widget.enabled && !_tapped;
    return AnimatedBuilder(
      animation: Listenable.merge([_enter, _sheen, _pulse]),
      builder: (context, _) {
        final e = _enter.value;
        var scale = reduce ? 1.0 : _enterScale.transform(e);
        if (!reduce && _pulse.isAnimating) {
          scale *= 1 + 0.03 * math.sin(_pulse.value * math.pi);
        }
        if (_pressed) scale *= 0.96;
        // Sheen: sweeps during the first 600 ms of each 2.2 s period.
        // Reduce Motion: parked at 30 % across, never moves.
        final double? sheenX;
        if (reduce) {
          sheenX = 0.3;
        } else if (_sheen.isAnimating) {
          final ms = _sheen.value * BankButton.sheenPeriod.inMilliseconds;
          sheenX = ms < BankButton.sheenSweepMs
              ? ms / BankButton.sheenSweepMs
              : null;
        } else {
          sheenX = null;
        }
        return Opacity(
          opacity: reduce ? 1 : _enterOpacity.transform(e),
          child: Transform.scale(scale: scale, child: _pill(active, sheenX)),
        );
      },
    );
  }

  Widget _pill(bool active, double? sheenX) {
    return Semantics(
      button: true,
      enabled: active,
      label: 'Bank, plus ${widget.amountGems} gems',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _canTap ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: _canTap ? (_) => setState(() => _pressed = false) : null,
        onTap: _canTap ? _onTap : null,
        child: Container(
          height: BankButton.height,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BankButton.height / 2),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: active
                  ? const [Color(0xFFFFE08A), Color(0xFFF2B632), Color(0xFFC98A12)]
                  : const [Color(0xFFBFAE84), Color(0xFF9C8A5E), Color(0xFF7A6A44)],
            ),
            border: Border.all(color: const Color(0xFF8A5A0E), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD36A).withValues(alpha: active ? 0.45 : 0),
                blurRadius: 18,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(BankButton.height / 2),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (sheenX != null)
                  FractionallySizedBox(
                    alignment: Alignment(-1.6 + 3.2 * sheenX, 0),
                    widthFactor: 0.28,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.7),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Bank',
                      style: TextStyle(
                        color: MargeColors.velvet,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      '+${widget.amountGems} gems',
                      style: const TextStyle(
                        color: MargeColors.velvet,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 10 gem sprites flying on curved paths from [from] to [to] (global coords).
class GemBurst extends StatefulWidget {
  const GemBurst({
    super.key,
    required this.from,
    required this.to,
    required this.onDone,
  });

  final Offset from;
  final Offset to;
  final VoidCallback onDone;

  @override
  State<GemBurst> createState() => _GemBurstState();
}

class _GemBurstState extends State<GemBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: BankButton.burstDuration,
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final ms = _c.value * BankButton.burstDuration.inMilliseconds;
          final kids = <Widget>[];
          for (var i = 0; i < BankButton.particleCount; i++) {
            final t = ((ms - i * BankButton.particleStaggerMs) /
                    BankButton.particleFlightMs)
                .clamp(0.0, 1.0);
            if (t <= 0 || t >= 1) continue;
            // Quadratic bezier with a sideways bulge that fans the gems out.
            final spread = (i - (BankButton.particleCount - 1) / 2) * 22.0;
            final mid = Offset(
              (widget.from.dx + widget.to.dx) / 2 + spread,
              math.min(widget.from.dy, widget.to.dy) +
                  (widget.from.dy - widget.to.dy).abs() * 0.35,
            );
            final q = Curves.easeInOut.transform(t);
            final p = widget.from * ((1 - q) * (1 - q)) +
                mid * (2 * (1 - q) * q) +
                widget.to * (q * q);
            final size = 22.0 * (1 - 0.35 * q);
            kids.add(
              Positioned(
                left: p.dx - size / 2,
                top: p.dy - size / 2,
                width: size,
                height: size,
                child: Image.asset(GemArt.gem(i), gaplessPlayback: true),
              ),
            );
          }
          return Stack(children: kids);
        },
      ),
    );
  }
}
