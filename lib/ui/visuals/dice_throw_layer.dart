part of 'dice_3d.dart';

/// Real-throw playback for [DiceTray] (DICE_SPEC.md). The faces are decided
/// before the throw; [DiceThrowSim] runs once up front and this layer only
/// plays the frames back (time-warped for slow-mo), so every frame is
/// deterministic per (rollSerial, table size).
class _ThrowState {
  bool active = false;
  ThrowResult? result;
  Size table = Size.zero;

  /// Wall ms -> sim seconds, sampled every ms.
  List<double> warp = const [];
  int simEndMs = 0; // wall ms when the sim's last frame plays
  int totalMs = 0; // + 250 ms beat before the readout
  bool big = false, epic = false, triples = false;
  List<bool> moving = const [false, false, false];

  /// Where each die rests (dp in the table), null = its holding slot.
  List<Offset?> rest = [null, null, null];
  List<double> restYaw = [0, 0, 0];

  // Per-throw feedback bookkeeping.
  int eventIdx = 0;
  int haptics = 0;
  int landedMask = 0;
  bool slowMoCued = false, bigCued = false;

  // Perf guard (session-wide): trails + zoom off when frames are slow.
  static bool trailsAndZoomOff = false;
  int lastTickUs = 0, slowTicks = 0;
}

extension _ThrowPlayback on DiceTrayState {
  static const _beatMs = 250;
  static const _reduceMs = 250;
  static const _fadeInS = 0.08;

  Offset _slot(int i, Size t) {
    final n = widget.values.length;
    final s = widget.size;
    final y = widget.fromTop ? s * 0.8 : t.height - s * 0.8;
    return Offset(t.width / 2 + (i - (n - 1) / 2) * s * 1.35, y);
  }

  Size _tableFor(BoxConstraints c) {
    final s = widget.size;
    final w = c.maxWidth.isFinite ? c.maxWidth : s * 5.6;
    final h = c.maxHeight.isFinite ? c.maxHeight : s + 44;
    return Size(w, math.max(h, s + 44));
  }

  /// Simulated time to show at wall time [ms].
  double _simAt(double ms) {
    final w = _th.warp;
    if (w.isEmpty) return 0;
    final k = ms.floor().clamp(0, w.length - 1);
    return w[k];
  }

  void _startThrow(List<bool> moving) {
    final t = _th.table == Size.zero
        ? Size(widget.size * 5.6, widget.size * 4)
        : _th.table;
    _th
      ..active = true
      ..moving = moving
      ..eventIdx = 0
      ..haptics = 0
      ..landedMask = 0
      ..slowMoCued = false
      ..bigCued = false
      ..lastTickUs = 0
      ..slowTicks = 0;
    final v = widget.values;
    _th.triples = v.length == 3 && v[0] == v[1] && v[1] == v[2];
    _th.epic = _th.triples && v[0] == 1 && widget.firstRoll;
    _th.big = _th.triples || widget.highlight;
    if (_reduce) {
      _th.result = null;
      for (var i = 0; i < moving.length; i++) {
        if (moving[i]) {
          _th.rest[i] = null;
          _th.restYaw[i] = 0;
        }
      }
      _c.duration = const Duration(milliseconds: _reduceMs);
      _c.forward(from: 0);
      widget.sfx?.diceThrown();
      return;
    }
    final r = DiceThrowSim.simulate(
      seed: widget.rollSerial * 7349 + 17,
      width: t.width,
      height: t.height,
      dieSize: widget.size,
      moving: moving,
      values: v,
      fromTop: widget.fromTop,
      rest: [
        for (var i = 0; i < moving.length; i++)
          if (moving[i]) null else (_restOf(i, t).dx, _restOf(i, t).dy),
      ],
    );
    _th.result = r;
    _th.warp = _buildWarp(r);
    _th.simEndMs = _th.warp.length;
    _th.totalMs = _th.simEndMs + _beatMs;
    _c.duration = Duration(milliseconds: _th.totalMs);
    _c.forward(from: 0);
    widget.sfx?.diceThrown();
  }

  Offset _restOf(int i, Size t) {
    final kept = i < widget.kept.length && widget.kept[i];
    if (kept) return _slot(i, t);
    return _th.rest[i] ?? _slot(i, t);
  }

  /// Slow-mo: 0.35x from the last real bounce (~0.25 s added, eased back).
  /// Big results: 0.2x over the final 500 ms wall; first-roll triple 1s 0.15x.
  List<double> _buildWarp(ThrowResult r) {
    final end = r.duration;
    final tb = r.lastBounce;
    final low = _th.epic ? 0.15 : (_th.big ? 0.2 : 0.35);
    // Normal: slow window [tb, tb + 0.135] (+0.1 ramp back).
    // Big: the last 100 ms of sim (120 for epic) stretched over ~500+ ms.
    final bigFrom = end - (_th.epic ? 0.12 : 0.1);
    double rate(double ts) {
      if (_th.big && ts >= bigFrom) return low;
      if (tb > 0 && ts >= tb && ts < tb + 0.135) return 0.35;
      if (tb > 0 && ts >= tb + 0.135 && ts < tb + 0.235) {
        return 0.35 + 0.65 * (ts - tb - 0.135) / 0.1;
      }
      return 1;
    }

    final out = <double>[];
    var ts = 0.0;
    while (ts < end && out.length < 4000) {
      out.add(ts);
      ts += 0.001 * rate(ts);
    }
    out.add(end);
    return out;
  }

  void _throwTick() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final ms = _ms;
    if (_th.lastTickUs != 0 && ms < 300) {
      if (now - _th.lastTickUs > 25000) _th.slowTicks++;
      if (_th.slowTicks >= 4) _ThrowState.trailsAndZoomOff = true;
    }
    _th.lastTickUs = now;
    final r = _th.result;
    if (r != null) _fireEvents(r, _simAt(ms));
    _rebuild();
  }

  bool _takeHaptic() {
    if (_th.haptics >= 6) return false;
    _th.haptics++;
    return true;
  }

  void _fireEvents(ThrowResult r, double ts) {
    final sfx = widget.sfx;
    while (_th.eventIdx < r.events.length && r.events[_th.eventIdx].t <= ts) {
      final e = r.events[_th.eventIdx++];
      switch (e.kind) {
        case ThrowEventKind.land:
          if ((_th.landedMask & (1 << e.die)) == 0) {
            _th.landedMask |= 1 << e.die;
            // First felt hit per die: clack + selectionClick.
            if (_takeHaptic()) {
              sfx?.dieLanded();
            } else {
              sfx?.play(SfxCue.dieClack);
            }
          } else {
            sfx?.feltThud(e.impact);
          }
        case ThrowEventKind.rail:
          sfx?.railKnock(haptic: _takeHaptic());
        case ThrowEventKind.hit:
          sfx?.diceHit(haptic: _takeHaptic());
      }
    }
    if (!_th.slowMoCued && r.lastBounce > 0 && ts >= r.lastBounce) {
      _th.slowMoCued = true;
      sfx?.slowMo();
    }
  }

  void _throwSettled() {
    final r = _th.result;
    if (r != null) {
      _fireEvents(r, double.infinity);
      for (var i = 0; i < _th.moving.length; i++) {
        if (!_th.moving[i]) continue;
        if ((_th.landedMask & (1 << i)) == 0) {
          _th.landedMask |= 1 << i;
          widget.sfx?.dieLanded();
        }
        final f = r.finalFrame[i];
        _th.rest[i] = Offset(f.p.x, f.p.y);
        _th.restYaw[i] = _yawOf(f.q * r.relabel[i]);
      }
    } else {
      for (var i = 0; i < _th.moving.length; i++) {
        if (_th.moving[i] && (_th.landedMask & (1 << i)) == 0) {
          _th.landedMask |= 1 << i;
          widget.sfx?.dieLanded();
        }
      }
    }
    if (_th.big && !_th.bigCued) {
      _th.bigCued = true;
      widget.sfx?.bigResult(triples: _th.triples, haptic: _takeHaptic());
    }
    _th.result = null;
    _th.active = false;
    _moving = const [false, false, false];
    _rebuild();
    widget.onSettled?.call(widget.rollSerial);
  }

  static double _yawOf(Quat q) {
    final m = q.matrix; // value face up: rotation about z
    return math.atan2(m[3], m[0]);
  }

  /// Sim body rotation -> DiceCube matrix (screen space: z toward viewer is
  /// -z, so conjugate by diag(1,1,-1)), then the resting camera tilt.
  static Matrix4 _cubeMatrix(Quat q) {
    final m = q.matrix;
    final r = Matrix4.identity();
    const flip = [1.0, 1.0, -1.0];
    for (var a = 0; a < 3; a++) {
      for (var b = 0; b < 3; b++) {
        r.setEntry(a, b, m[a * 3 + b] * flip[a] * flip[b]);
      }
    }
    return Matrix4.identity()
      ..rotateX(DiceCube.restRx)
      ..rotateY(DiceCube.restRy)
      ..multiply(r);
  }

  Widget _buildTable(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final t = _tableFor(c);
        _th.table = t;
        return Opacity(
          opacity: widget.dim ? 0.35 : 1,
          child: SizedBox(
            width: t.width,
            height: t.height,
            child: RepaintBoundary(child: _layer(t)),
          ),
        );
      },
    );
  }

  Widget _layer(Size t) {
    final s = widget.size;
    final throwing = _th.active && _c.isAnimating;
    final r = throwing ? _th.result : null;
    final ms = _ms;
    final ts = r == null ? 0.0 : _simAt(ms);
    final fx = !_ThrowState.trailsAndZoomOff;

    // Table shake (layer only, never UI).
    var shake = Offset.zero;
    if (r != null) {
      final lands = r.events.where((e) => e.kind == ThrowEventKind.land);
      if (lands.isNotEmpty) {
        final first = lands.first.t;
        final last = lands.last.t;
        double amp(double since, double a) => since < 0 || since > 0.18
            ? 0
            : a * math.exp(-since * 18) * math.sin(since * 2 * math.pi / 0.045);
        final a1 = amp(ts - first, 4);
        final a2 = _th.big ? amp(ts - last, 6) : 0.0;
        shake = Offset(a1 + a2, (a1 + a2) * 0.6);
      }
    }

    final children = <Widget>[];
    final shadows = <Widget>[];
    final ghosts = <Widget>[];
    final dice = <Widget>[];
    final taps = <Widget>[];
    for (var i = 0; i < widget.values.length; i++) {
      final kept = i < widget.kept.length && widget.kept[i];
      final mover = throwing && i < _th.moving.length && _th.moving[i];
      Offset pos;
      double z = s / 2, opacity = 1, squash = 1;
      Matrix4? orient;
      double yaw = 0;
      if (mover && r != null) {
        final f = r.at(ts, i);
        pos = Offset(f.p.x, f.p.y);
        z = f.p.z;
        orient = _cubeMatrix(f.q * r.relabel[i]);
        opacity = (ts / _fadeInS).clamp(0.0, 1.0);
        for (final e in r.events) {
          if (e.kind == ThrowEventKind.land &&
              e.die == i &&
              ts >= e.t &&
              ts - e.t < 0.04) {
            squash = 0.94;
          }
        }
        if (fx && f.speed > 520) {
          const alphas = [0.25, 0.15, 0.08, 0.05];
          for (var k = 0; k < alphas.length; k++) {
            final g = r.at(math.max(0, ts - 0.022 * (k + 1)), i);
            ghosts.add(
              _cubeAt(
                i,
                Offset(g.p.x, g.p.y),
                g.p.z,
                _cubeMatrix(g.q * r.relabel[i]),
                0,
                alphas[k],
                1,
                false,
                key: ValueKey('ghost-$i-$k'),
              ),
            );
          }
        }
      } else if (mover && _reduce) {
        // Reduce Motion: fade + drop into the final spot, one soft bounce.
        pos = _restOf(i, t);
        final q = (ms / _reduceMs).clamp(0.0, 1.0);
        opacity = (q / 0.5).clamp(0.0, 1.0);
        final drop = q < 0.7
            ? 14 * (1 - q / 0.7) * (1 - q / 0.7)
            : 3 * math.sin((q - 0.7) / 0.3 * math.pi);
        z = s / 2 + drop;
      } else {
        pos = _restOf(i, t);
        yaw = kept ? 0 : _th.restYaw[i];
      }
      final h = ((z - s / 2) / (s * 1.6)).clamp(0.0, 1.0);
      final sc = 0.4 + 0.6 * (1 - h); // 1.0 -> 0.6
      shadows.add(
        Positioned(
          left: pos.dx - s * 0.48 * sc + 4 + 10 * h,
          top: pos.dy + s * 0.32 - s * 0.11 * sc + 6 + 8 * h,
          child: IgnorePointer(
            child: Container(
              width: s * 0.96 * sc,
              height: s * 0.22 * sc,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(
                  Radius.elliptical(s * 0.48 * sc, s * 0.11 * sc),
                ),
                color: Colors.black.withValues(
                  alpha: (0.45 - 0.30 * h) * opacity,
                ),
              ),
            ),
          ),
        ),
      );
      final still = !mover;
      dice.add(
        _cubeAt(
          i,
          pos,
          z,
          orient,
          yaw,
          opacity,
          squash,
          kept && still,
          key: ValueKey('die-cube-$i'),
          animated: still && !throwing,
        ),
      );
      final canTap =
          !settling &&
          i < widget.enabled.length &&
          widget.enabled[i] &&
          widget.onTap != null;
      taps.add(
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          left: pos.dx - (s + 20) / 2,
          top: pos.dy - (s + 20) / 2,
          child: GestureDetector(
            key: ValueKey('die-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: canTap ? () => widget.onTap!(i) : null,
            child: SizedBox(width: s + 20, height: s + 20),
          ),
        ),
      );
    }

    // Big results: zoom on the dice, light vignette, gold glow (no blur).
    var zoom = 1.0;
    var glow = 0.0;
    if (_th.big && r != null && fx) {
      final left = _th.simEndMs - ms;
      final k = (1 - left / 500).clamp(0.0, 1.0);
      zoom = 1 + (_th.epic ? 0.12 : 0.08) * Curves.easeOut.transform(k);
      glow = k;
    } else if (_th.big && throwing && r == null) {
      glow = 0;
    } else if (_th.big && _th.active) {
      glow = 1;
    }
    final settledBig = _th.big && throwing && ms >= _th.simEndMs;
    if (settledBig) glow = 1;

    Offset centroid = Offset(t.width / 2, t.height / 2);
    if (r != null) {
      var sx = 0.0, sy = 0.0;
      for (final d in r.finalFrame) {
        sx += d.p.x;
        sy += d.p.y;
      }
      centroid = Offset(sx / r.finalFrame.length, sy / r.finalFrame.length);
    }

    children.add(
      Positioned.fill(
        child: Transform.translate(
          offset: shake,
          child: Transform(
            transform: Matrix4.identity()
              ..translateByDouble(centroid.dx, centroid.dy, 0, 1)
              ..scaleByDouble(zoom, zoom, 1, 1)
              ..translateByDouble(-centroid.dx, -centroid.dy, 0, 1),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (glow > 0)
                  Positioned(
                    key: const ValueKey('big-glow'),
                    left: centroid.dx - s * 2.6,
                    top: centroid.dy - s * 1.8,
                    child: IgnorePointer(
                      child: Container(
                        width: s * 5.2,
                        height: s * 3.6,
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              MargeColors.gold.withValues(alpha: 0.35 * glow),
                              MargeColors.gold.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ...shadows,
                ...ghosts,
                ...dice,
                if (settledBig && _th.triples)
                  for (var i = 0; i < 3; i++)
                    Positioned(
                      left: _restOrFinal(i, t, r).dx - s * 0.6,
                      top: _restOrFinal(i, t, r).dy - s * 0.9,
                      child: IgnorePointer(
                        child: Image.asset(
                          'assets/visuals/sparkle/sparkle_${((ms - _th.simEndMs) ~/ 80) % 2}.png',
                          key: ValueKey('triple-sparkle-$i'),
                          width: s * 1.2,
                          height: s * 1.2,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
    if (glow > 0 && fx) {
      children.add(
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('big-vignette'),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.9,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.22 * glow),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    children.addAll(taps);
    return Stack(clipBehavior: Clip.none, children: children);
  }

  Offset _restOrFinal(int i, Size t, ThrowResult? r) {
    if (r != null && i < _th.moving.length && _th.moving[i]) {
      final f = r.finalFrame[i];
      return Offset(f.p.x, f.p.y);
    }
    return _restOf(i, t);
  }

  Widget _cubeAt(
    int i,
    Offset pos,
    double z,
    Matrix4? orient,
    double yaw,
    double opacity,
    double squash,
    bool kept, {
    required Key key,
    bool animated = false,
  }) {
    final s = widget.size;
    final h = ((z - s / 2) / (s * 1.6)).clamp(0.0, 1.5);
    final lift = (z - s / 2) * 0.55; // height reads as up-screen
    final scale = 1 + 0.18 * h;
    final cube = Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(scale, scale * squash, 1),
        child: DiceCube(
          value: widget.values[i],
          size: s,
          theme: widget.theme,
          kept: kept,
          orientation: orient,
          rz: orient == null ? yaw : 0,
        ),
      ),
    );
    final left = pos.dx - s / 2, top = pos.dy - s / 2 - lift;
    if (animated) {
      return AnimatedPositioned(
        key: key,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        left: left,
        top: top,
        child: IgnorePointer(child: cube),
      );
    }
    return Positioned(
      key: key,
      left: left,
      top: top,
      child: IgnorePointer(child: cube),
    );
  }
}
