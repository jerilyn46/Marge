import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/marge_theme.dart';
import 'pot_of_gems.dart' show GemArt;

/// Splits [total] gems across [parts] particles so the shares add up exactly.
List<int> gemShares(int total, int parts) {
  if (parts <= 0) return const [];
  final each = total ~/ parts;
  final extra = total % parts;
  return [for (var i = 0; i < parts; i++) each + (i < extra ? 1 : 0)];
}

/// The table's gem bank in the top bar: a ruby and the seat's gem count.
///
/// Normally shows [gems]. While gems are in flight toward it (Bank particles
/// or a pot win), [beginIncoming] holds the number where it is and [land]
/// ticks it up as each particle arrives (with a small pop), so the count
/// moves with the art instead of jumping before the gems get there. Once
/// every particle has landed and the engine's credit has arrived, it
/// returns to [gems]. Reduce Motion: no pop.
class GemBankReadout extends StatefulWidget {
  const GemBankReadout({
    super.key,
    required this.gems,
    required this.ownerId,
    this.targetKey,
    this.onTap,
  });

  /// The owning seat's table gems (null: no seat to show).
  final int? gems;

  /// Seat identity; a different owner cancels any tick in progress.
  final String ownerId;

  /// Put on the ruby so particles fly into it.
  final GlobalKey? targetKey;
  final VoidCallback? onTap;

  static const popMs = 160;

  @override
  State<GemBankReadout> createState() => GemBankReadoutState();
}

class GemBankReadoutState extends State<GemBankReadout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: GemBankReadout.popMs),
  );

  int? _base;
  int _total = 0;
  int _landed = 0;
  bool _credited = false;
  int? _gemsAtStart;

  /// True while the number is held for gems still in the air.
  bool get ticking => _base != null;

  /// The number on screen right now.
  int get shown => _base != null ? _base! + _landed : (widget.gems ?? 0);

  /// [total] gems are on their way. [credited]: the engine has already
  /// added them to [GemBankReadout.gems] (pot win); otherwise the readout
  /// waits for that credit before letting go (Bank).
  void beginIncoming(int total, {int? from, bool credited = false}) {
    if (total <= 0 || widget.gems == null) return;
    setState(() {
      _base = from ?? shown;
      _total = total;
      _landed = 0;
      _credited = credited;
      _gemsAtStart = widget.gems;
    });
  }

  /// One particle with [gems] in it reached the readout.
  void land(int gems) {
    if (_base == null || gems <= 0) return;
    setState(() => _landed = math.min(_total, _landed + gems));
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _pop.forward(from: 0);
    }
    _maybeRelease();
  }

  /// Stop holding (flight cancelled); show the real value.
  void cancel() {
    if (_base == null) return;
    setState(() => _base = null);
  }

  void _maybeRelease() {
    if (_base != null && _landed >= _total && _credited) {
      setState(() => _base = null);
    }
  }

  @override
  void didUpdateWidget(GemBankReadout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ownerId != oldWidget.ownerId || widget.gems == null) {
      _base = null;
      return;
    }
    if (_base != null && widget.gems != _gemsAtStart) {
      _credited = true;
      if (_landed >= _total) _base = null;
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.gems == null ? null : shown;
    return Tooltip(
      message: 'Table gems',
      child: Semantics(
        button: true,
        label: value == null ? 'Table gems' : 'Table gems, $value',
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('gem-bank-readout'),
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: MargeColors.velvet.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: MargeColors.gold.withValues(alpha: 0.65),
                ),
              ),
              child: AnimatedBuilder(
                animation: _pop,
                builder: (context, child) => Transform.scale(
                  scale: 1 + 0.15 * math.sin(_pop.value * math.pi),
                  child: child,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      GemArt.gem(0), // ruby, same as the Home gem bank
                      key: widget.targetKey,
                      width: 18,
                      height: 18,
                      gaplessPlayback: true,
                    ),
                    if (value != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$value',
                        key: const ValueKey('gem-bank-count'),
                        style: const TextStyle(
                          color: MargeColors.gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
