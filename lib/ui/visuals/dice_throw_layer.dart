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

  /// Kept-die slide start (null = not sliding).
  List<Offset?> slideFrom = [null, null, null];

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
    final y = t.height - s * 0.8;
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
      edge: widget.throwEdge,
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

  List<double> _buildWarp(ThrowResult r) =>
      DiceThrowSim.warp(r, big: _th.big, epic: _th.epic);

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
    // No setState: the painter listens to the controller and repaints.
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
        _th.restYaw[i] = DiceThrowSim.restYaw(f.q * r.relabel[i]);
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

  /// Kept-die slide to its holding spot (200 ms, painter-driven).
  Offset _restAnimated(int i, Size t) {
    final to = _restOf(i, t);
    final from = _th.slideFrom[i];
    if (from == null) return to;
    final k = Curves.easeOut.transform(_slide.value);
    if (_slide.value >= 1) _th.slideFrom[i] = null;
    return Offset.lerp(from, to, k)!;
  }

  /// One frame of the table: everything the painter needs, computed from
  /// the controllers (no widget rebuild per frame).
  _TableFrame _frame(Size t) {
    final s = widget.size;
    final throwing = _th.active && _c.isAnimating;
    final r = throwing ? _th.result : null;
    final ms = _ms;
    final ts = r == null ? 0.0 : _simAt(ms);
    final fx = !_ThrowState.trailsAndZoomOff;
    final dice = <_DieDraw>[];
    final ghosts = <_DieDraw>[];

    var shake = Offset.zero;
    if (r != null) {
      final lands = r.events.where((e) => e.kind == ThrowEventKind.land);
      if (lands.isNotEmpty) {
        double amp(double since, double a) => since < 0 || since > 0.18
            ? 0
            : a * math.exp(-since * 18) * math.sin(since * 2 * math.pi / 0.045);
        final a1 = amp(ts - lands.first.t, 4);
        final a2 = _th.big ? amp(ts - lands.last.t, 6) : 0.0;
        shake = Offset(a1 + a2, (a1 + a2) * 0.6);
      }
    }

    for (var i = 0; i < widget.values.length; i++) {
      final kept = i < widget.kept.length && widget.kept[i];
      final mover = throwing && i < _th.moving.length && _th.moving[i];
      var pos = Offset.zero;
      double z = s / 2, opacity = 1, squash = 1;
      Matrix4 rot;
      if (mover && r != null) {
        final f = r.at(ts, i);
        pos = Offset(f.p.x, f.p.y);
        z = f.p.z;
        rot = _cubeMatrix(f.q * r.relabel[i]);
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
              _DieDraw(
                i,
                Offset(g.p.x, g.p.y),
                g.p.z,
                _cubeMatrix(g.q * r.relabel[i]),
                alphas[k],
                1,
                false,
              ),
            );
          }
        }
      } else if (mover && _reduce) {
        pos = _restOf(i, t);
        final q = (ms / _reduceMs).clamp(0.0, 1.0);
        opacity = (q / 0.5).clamp(0.0, 1.0);
        final drop = q < 0.7
            ? 14 * (1 - q / 0.7) * (1 - q / 0.7)
            : 3 * math.sin((q - 0.7) / 0.3 * math.pi);
        z = s / 2 + drop;
        rot = _restMatrix(0);
      } else {
        pos = _restAnimated(i, t);
        rot = _restMatrix(kept ? 0 : _th.restYaw[i]);
      }
      dice.add(_DieDraw(i, pos, z, rot, opacity, squash, kept && !mover));
    }

    var zoom = 1.0, glow = 0.0;
    if (_th.big && throwing) {
      if (r != null && ms >= _th.simEndMs) {
        glow = 1;
        zoom = fx ? (_th.epic ? 1.12 : 1.08) : 1;
      } else if (r != null && fx) {
        final k = (1 - (_th.simEndMs - ms) / 500).clamp(0.0, 1.0);
        zoom = 1 + (_th.epic ? 0.12 : 0.08) * Curves.easeOut.transform(k);
        glow = k;
      }
    }
    var centroid = Offset(t.width / 2, t.height / 2);
    if (r != null) {
      var sx = 0.0, sy = 0.0;
      for (final d in r.finalFrame) {
        sx += d.p.x;
        sy += d.p.y;
      }
      centroid = Offset(sx / r.finalFrame.length, sy / r.finalFrame.length);
    }
    return _TableFrame(
      dice: dice,
      ghosts: ghosts,
      shake: shake,
      zoom: zoom,
      glow: glow,
      vignette: fx ? glow : 0,
      centroid: centroid,
    );
  }

  static Matrix4 _restMatrix(double yaw) => Matrix4.identity()
    ..rotateX(DiceCube.restRx)
    ..rotateY(DiceCube.restRy)
    ..rotateZ(yaw);

  Widget _buildTable(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final t = _tableFor(c);
        _th.table = t;
        final s = widget.size;
        final taps = <Widget>[];
        for (var i = 0; i < widget.values.length; i++) {
          final pos = _restOf(i, t);
          final canTap =
              !settling &&
              i < widget.enabled.length &&
              widget.enabled[i] &&
              widget.onTap != null;
          taps.add(
            Positioned(
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
        final showSparkle = _th.big && _th.triples && _th.active;
        return Opacity(
          opacity: widget.dim ? 0.35 : 1,
          child: SizedBox(
            width: t.width,
            height: t.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The whole dice layer: one CustomPainter, repainted by the
                // throw/slide controllers, never rebuilt per frame.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('dice-table-painter'),
                      painter: _DiceTablePainter(
                        repaint: Listenable.merge([_c, _slide]),
                        frame: () => _frame(t),
                        size: s,
                        values: widget.values,
                        theme: widget.theme,
                      ),
                    ),
                  ),
                ),
                if (showSparkle) ..._sparkles(t),
                ...taps,
              ],
            ),
          ),
        );
      },
    );
  }

  /// Triples sparkle burst after the dice settle (sprite frames).
  List<Widget> _sparkles(Size t) {
    final s = widget.size;
    final r = _th.result;
    return [
      for (var i = 0; i < widget.values.length; i++)
        Positioned(
          left: _restOrFinal(i, t, r).dx - s * 0.6,
          top: _restOrFinal(i, t, r).dy - s * 0.9,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final ms = _ms;
                if (ms < _th.simEndMs) return const SizedBox.shrink();
                return Image.asset(
                  'assets/visuals/sparkle/sparkle_${((ms - _th.simEndMs) ~/ 80) % 2}.png',
                  key: ValueKey('triple-sparkle-$i'),
                  width: s * 1.2,
                  height: s * 1.2,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
    ];
  }

  Offset _restOrFinal(int i, Size t, ThrowResult? r) {
    if (r != null && i < _th.moving.length && _th.moving[i]) {
      final f = r.finalFrame[i];
      return Offset(f.p.x, f.p.y);
    }
    return _restOf(i, t);
  }
}

class _DieDraw {
  const _DieDraw(
    this.index,
    this.pos,
    this.z,
    this.rot,
    this.opacity,
    this.squash,
    this.kept,
  );
  final int index;
  final Offset pos;
  final double z;
  final Matrix4 rot;
  final double opacity;
  final double squash;
  final bool kept;
}

class _TableFrame {
  const _TableFrame({
    required this.dice,
    required this.ghosts,
    required this.shake,
    required this.zoom,
    required this.glow,
    required this.vignette,
    required this.centroid,
  });
  final List<_DieDraw> dice;
  final List<_DieDraw> ghosts;
  final Offset shake;
  final double zoom;
  final double glow;
  final double vignette;
  final Offset centroid;
}

/// Screen geometry for one die (shared by the painter and test hooks).
class _DieGeometry {
  _DieGeometry(_DieDraw d, double s) {
    final h = ((d.z - s / 2) / (s * 1.6)).clamp(0.0, 1.5);
    lift = (d.z - s / 2) * 0.55; // height reads as up-screen
    scale = 1 + 0.18 * h;
    center = Offset(d.pos.dx, d.pos.dy - lift);
    shadowH = ((d.z - s / 2) / (s * 1.6)).clamp(0.0, 1.0);
  }
  late final double lift, scale, shadowH;
  late final Offset center;

  /// Face transforms (value, matrix in die-centred coords), far first.
  static List<(int, Matrix4, double)> faces(int value, Matrix4 rot, double s) {
    final out = <(int, Matrix4, double, double)>[];
    for (final (faceValue, faceM) in DiceCube.facesFor(value, s / 2)) {
      final m = rot.multiplied(faceM);
      final nz = -m.entry(2, 2);
      if (nz > -0.02) continue; // back-facing
      final light = (-nz).clamp(0.0, 1.0);
      final ny = -m.entry(1, 2);
      final shade = (0.5 * (1 - light) - (ny < 0 ? -0.3 * ny : 0)).clamp(
        0.0,
        0.6,
      );
      final pm = Matrix4.identity()
        ..setEntry(3, 2, DiceCube.perspective)
        ..multiply(m)
        ..translateByDouble(-s / 2, -s / 2, 0, 1);
      out.add((faceValue, pm, shade, m.entry(2, 3)));
    }
    out.sort((a, b) => b.$4.compareTo(a.$4));
    return [for (final f in out) (f.$1, f.$2, f.$3)];
  }
}

class _DiceTablePainter extends CustomPainter {
  _DiceTablePainter({
    required Listenable repaint,
    required this.frame,
    required this.size,
    required this.values,
    required this.theme,
  }) : super(repaint: repaint);

  final _TableFrame Function() frame;
  final double size;
  final List<int> values;
  final DiceSkinTheme? theme;

  @override
  void paint(Canvas canvas, Size area) {
    final f = frame();
    final s = size;
    canvas.save();
    canvas.translate(f.shake.dx, f.shake.dy);
    if (f.zoom != 1) {
      canvas.translate(f.centroid.dx, f.centroid.dy);
      canvas.scale(f.zoom);
      canvas.translate(-f.centroid.dx, -f.centroid.dy);
    }
    if (f.glow > 0) {
      final rect = Rect.fromCenter(
        center: f.centroid,
        width: s * 5.2,
        height: s * 3.6,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              MargeColors.gold.withValues(alpha: 0.35 * f.glow),
              MargeColors.gold.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    // Shadows: ellipse scale 1.0 -> 0.6, opacity 0.45 -> 0.15 with height,
    // offset bottom-right.
    for (final d in f.dice) {
      final g = _DieGeometry(d, s);
      final h = g.shadowH;
      final sc = 0.4 + 0.6 * (1 - h);
      canvas.drawOval(
        Rect.fromCenter(
          center: d.pos + Offset(4 + 10 * h, s * 0.32 + 6 + 8 * h),
          width: s * 0.96 * sc,
          height: s * 0.22 * sc,
        ),
        Paint()
          ..color = Colors.black.withValues(
            alpha: (0.45 - 0.30 * h) * d.opacity,
          ),
      );
    }
    for (final d in f.ghosts) {
      _paintDie(canvas, d);
    }
    final order = [...f.dice]..sort((a, b) => a.pos.dy.compareTo(b.pos.dy));
    for (final d in order) {
      _paintDie(canvas, d);
    }
    canvas.restore();
    if (f.vignette > 0) {
      final rect = Offset.zero & area;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: 0.9,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.22 * f.vignette),
            ],
          ).createShader(rect),
      );
    }
  }

  void _paintDie(Canvas canvas, _DieDraw d) {
    final s = size;
    final g = _DieGeometry(d, s);
    final layer = d.opacity < 0.999;
    canvas.save();
    canvas.translate(g.center.dx, g.center.dy);
    canvas.scale(g.scale, g.scale * d.squash);
    if (layer) {
      canvas.saveLayer(
        Rect.fromCircle(center: Offset.zero, radius: s),
        Paint()..color = Colors.white.withValues(alpha: d.opacity),
      );
    }
    if (d.kept) {
      final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: s * 1.28, height: s * 1.28),
        Radius.circular(s * 0.22),
      );
      canvas.drawRRect(
        rr.inflate(3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = MargeColors.gold.withValues(alpha: 0.3),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = MargeColors.gold,
      );
    }
    final value = d.index < values.length ? values[d.index] : 1;
    for (final (fv, pm, shade) in _DieGeometry.faces(value, d.rot, s)) {
      canvas.save();
      canvas.transform(pm.storage);
      paintDieFace(canvas, s, fv, theme, radius: s * 0.08, shade: shade);
      canvas.restore();
    }
    if (layer) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiceTablePainter old) =>
      old.size != size || old.values != values || old.theme != theme;
}
