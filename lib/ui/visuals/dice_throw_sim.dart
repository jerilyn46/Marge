import 'dart:math' as math;

/// Real-throw dice physics (DICE_SPEC.md, Designer, approved Oct 12).
///
/// Simulate-first, then playback: the engine has already decided the faces.
/// [DiceThrowSim.simulate] runs a fixed-step (1/120 s) 2.5D rigid-body sim
/// up front, deterministic per seed; the tray plays the frames back on a
/// ticker. After the sim, each die is relabelled ([ThrowResult.relabel]) so
/// whichever body face ended up on top shows the decided value (opposite
/// faces still sum to 7). Numbers borrowed from the Designer's reference sim
/// (_src/sim.py) and scaled to dp.
///
/// Frame: x right, y down the screen (toward the Roll button), z height
/// above the felt. Pure Dart; no Flutter imports so it is unit-testable.

class V3 {
  const V3(this.x, this.y, this.z);
  final double x, y, z;
  static const zero = V3(0, 0, 0);
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  V3 operator -() => V3(-x, -y, -z);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  double get planar => math.sqrt(x * x + y * y);
}

/// Unit quaternion (w, x, y, z).
class Quat {
  const Quat(this.w, this.x, this.y, this.z);
  final double w, x, y, z;
  static const identity = Quat(1, 0, 0, 0);

  Quat operator *(Quat b) => Quat(
    w * b.w - x * b.x - y * b.y - z * b.z,
    w * b.x + x * b.w + y * b.z - z * b.y,
    w * b.y - x * b.z + y * b.w + z * b.x,
    w * b.z + x * b.y - y * b.x + z * b.w,
  );

  Quat normalized() {
    final n = math.sqrt(w * w + x * x + y * y + z * z);
    return Quat(w / n, x / n, y / n, z / n);
  }

  static Quat axisAngle(V3 axis, double ang) {
    final n = axis.length;
    if (n < 1e-9) return identity;
    final s = math.sin(ang / 2) / n;
    return Quat(math.cos(ang / 2), axis.x * s, axis.y * s, axis.z * s);
  }

  /// Rotate a body-frame vector into the world.
  V3 rotate(V3 v) {
    final m = matrix;
    return V3(
      m[0] * v.x + m[1] * v.y + m[2] * v.z,
      m[3] * v.x + m[4] * v.y + m[5] * v.z,
      m[6] * v.x + m[7] * v.y + m[8] * v.z,
    );
  }

  /// Row-major 3x3.
  List<double> get matrix => [
    1 - 2 * (y * y + z * z),
    2 * (x * y - w * z),
    2 * (x * z + w * y),
    2 * (x * y + w * z),
    1 - 2 * (x * x + z * z),
    2 * (y * z - w * x),
    2 * (x * z - w * y),
    2 * (y * z + w * x),
    1 - 2 * (x * x + y * y),
  ];

  static Quat slerp(Quat a, Quat b, double t) {
    var d = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
    var bb = b;
    if (d < 0) {
      bb = Quat(-b.w, -b.x, -b.y, -b.z);
      d = -d;
    }
    if (d > 0.9995) {
      return Quat(
        a.w + t * (bb.w - a.w),
        a.x + t * (bb.x - a.x),
        a.y + t * (bb.y - a.y),
        a.z + t * (bb.z - a.z),
      ).normalized();
    }
    final th = math.acos(d);
    final sa = math.sin((1 - t) * th) / math.sin(th);
    final sb = math.sin(t * th) / math.sin(th);
    return Quat(
      a.w * sa + bb.w * sb,
      a.x * sa + bb.x * sb,
      a.y * sa + bb.y * sb,
      a.z * sa + bb.z * sb,
    );
  }
}

/// One die at one playback frame.
class DieFrame {
  const DieFrame(this.p, this.q, this.speed, {this.settled = false});
  final V3 p;
  final Quat q;
  final double speed;
  final bool settled;
}

enum ThrowEventKind { land, rail, hit }

class ThrowEvent {
  const ThrowEvent(this.kind, this.t, this.die, this.impact, {this.other});
  final ThrowEventKind kind;
  final double t;
  final int die;
  final int? other;
  final double impact;
}

/// Footprint on the felt: an oriented box (centre, unit axis u, half extents).
class Footprint {
  const Footprint(this.cx, this.cy, this.ux, this.uy, this.hu, this.hv);
  final double cx, cy, ux, uy, hu, hv;

  List<(double, double)> get corners {
    final vx = -uy, vy = ux;
    return [
      for (final (a, b) in const [(1, 1), (1, -1), (-1, -1), (-1, 1)])
        (cx + ux * hu * a + vx * hv * b, cy + uy * hu * a + vy * hv * b),
    ];
  }

  /// SAT: minimum translation (nx, ny, depth) pushing [this] out of [o],
  /// or null when the boxes are apart.
  (double, double, double)? overlap(Footprint o) {
    final axes = [(ux, uy), (-uy, ux), (o.ux, o.uy), (-o.uy, o.ux)];
    final ca = corners, cb = o.corners;
    var best = double.infinity;
    double bx = 0, by = 0;
    for (final (ax, ay) in axes) {
      double amin = double.infinity, amax = -double.infinity;
      double bmin = double.infinity, bmax = -double.infinity;
      for (final (x, y) in ca) {
        final d = x * ax + y * ay;
        amin = math.min(amin, d);
        amax = math.max(amax, d);
      }
      for (final (x, y) in cb) {
        final d = x * ax + y * ay;
        bmin = math.min(bmin, d);
        bmax = math.max(bmax, d);
      }
      final o1 = amax - bmin, o2 = bmax - amin;
      if (o1 <= 0 || o2 <= 0) return null;
      if (o1 < best) {
        best = o1;
        bx = -ax;
        by = -ay;
      }
      if (o2 < best) {
        best = o2;
        bx = ax;
        by = ay;
      }
    }
    return (bx, by, best);
  }
}

class ThrowResult {
  ThrowResult({
    required this.frames,
    required this.events,
    required this.relabel,
    required this.settleTime,
    required this.dieSize,
    required this.moving,
  });

  /// frames[k][i]: die i at t = (k+1) * dt.
  final List<List<DieFrame>> frames;
  final List<ThrowEvent> events;

  /// Fixed body rotation per die that puts the decided face on top at rest.
  final List<Quat> relabel;
  final double settleTime;
  final double dieSize;
  final List<bool> moving;

  double get duration => frames.length * DiceThrowSim.dt;

  DieFrame at(double t, int die) {
    final k = (t / DiceThrowSim.dt).floor().clamp(0, frames.length - 1);
    return frames[k][die];
  }

  List<DieFrame> get finalFrame => frames.last;

  /// Time of the last real felt bounce (slow-mo trigger).
  double get lastBounce {
    var t = 0.0;
    for (final e in events) {
      if (e.kind == ThrowEventKind.land && e.impact > 260) t = e.t;
    }
    return t;
  }

  Footprint footprint(int die, [double? t]) {
    final f = t == null ? finalFrame[die] : at(t, die);
    return DiceThrowSim.footprintOf(f.p, f.q, dieSize / 2);
  }
}

class _Die {
  _Die(this.p, this.v, this.q, this.w, {this.fixed = false});
  V3 p, v, w;
  Quat q;
  bool fixed;
  int still = 0;
  int? snapK;
  Quat? snapFrom, snapTo;
  bool done = false;
  int bounces = 0;
  bool get frozen => fixed || done || snapK != null;
}

class DiceThrowSim {
  static const dt = 1 / 120;
  static const maxT = 2.2; // force-damp deadline (spec)
  static const feltRestitution = 0.35;
  static const feltFriction = 0.55;
  static const railRestitution = 0.5;
  static const dieRestitution = 0.45;
  static const stillSteps = 10; // 80 ms
  static const snapSteps = 7; // ~60 ms ease-out

  static const _corners = [
    V3(-1, -1, -1),
    V3(-1, -1, 1),
    V3(-1, 1, -1),
    V3(-1, 1, 1),
    V3(1, -1, -1),
    V3(1, -1, 1),
    V3(1, 1, -1),
    V3(1, 1, 1),
  ];

  static Footprint footprintOf(V3 p, Quat q, double hs) {
    final m = q.matrix;
    // Yaw from the body axis that is most horizontal-dominant.
    var k = 0;
    var best = -1.0;
    for (var c = 0; c < 3; c++) {
      final h = math.sqrt(m[c] * m[c] + m[3 + c] * m[3 + c]);
      if (h > best) {
        best = h;
        k = c;
      }
    }
    final ux = m[k] / best, uy = m[3 + k] / best;
    double hu = 0, hv = 0;
    for (final c in _corners) {
      final w = q.rotate(c * hs);
      hu = math.max(hu, (w.x * ux + w.y * uy).abs());
      hv = math.max(hv, (-w.x * uy + w.y * ux).abs());
    }
    return Footprint(p.x, p.y, ux, uy, hu, hv);
  }

  /// [table]: felt size in dp (the rail is its inscribed oval).
  /// [slots]: holding spots near the bottom rail, one per die.
  /// [moving]: dice to throw; the rest sit fixed at [rest] (or their slot).
  /// [fromTop]: mirror the throw for the other seat (hotseat / bot turns).
  static ThrowResult simulate({
    required int seed,
    required double width,
    required double height,
    required double dieSize,
    required List<bool> moving,
    required List<int> values,
    List<(double, double)?>? rest,
    bool fromTop = false,
    (double, double, double)? avoid,
  }) {
    final rnd = math.Random(seed);
    final hs = dieSize / 2;
    final inertia = dieSize * dieSize / 6;
    final g = -2600.0 * (dieSize / 50) * 0.5;
    final n = moving.length;
    final cx = width / 2, cy = height / 2;
    final ra = width / 2 - hs * 0.9, rb = height / 2 - hs * 0.9;
    final dir = fromTop ? -1.0 : 1.0; // +1: thrown up from the bottom edge
    final slotY = height - hs * 1.6;
    double slotX(int i) => cx + (i - (n - 1) / 2) * dieSize * 1.35;

    final dice = <_Die>[];
    final wild = rnd.nextInt(n);
    final wdir = rnd.nextBool() ? 1.0 : -1.0;
    final aimX = cx + (rnd.nextDouble() - 0.5) * width * 0.25;
    // Travel 60–75% of the table height before friction wins.
    final travel = height * (0.6 + rnd.nextDouble() * 0.15);
    for (var i = 0; i < n; i++) {
      if (!moving[i]) {
        final r = (rest != null && i < rest.length) ? rest[i] : null;
        final x = r?.$1 ?? slotX(i);
        final y = r?.$2 ?? (fromTop ? height - slotY : slotY);
        dice.add(
          _Die(V3(x, y, hs), V3.zero, Quat.identity, V3.zero, fixed: true)
            ..done = true,
        );
        continue;
      }
      final x0 = cx + (i - 1) * dieSize * 1.05 + (rnd.nextDouble() - .5) * 8;
      final y0 = fromTop ? hs * 1.7 : height - hs * 1.7;
      var vx = (aimX + (i - 1) * hs - x0) * 1.1 + (rnd.nextDouble() - .5) * 90;
      if (i == wild) vx += wdir * (0.25 + rnd.nextDouble() * 0.35) * width;
      final vy = -dir * travel * (1.0 + rnd.nextDouble() * 0.15);
      final vz = 300 + rnd.nextDouble() * 120;
      final q = Quat(
        rnd.nextDouble() - .5,
        rnd.nextDouble() - .5,
        rnd.nextDouble() - .5,
        rnd.nextDouble() - .5,
      ).normalized();
      // 8–16 rad/s on a random axis.
      final ax = V3(
        rnd.nextDouble() - .5,
        rnd.nextDouble() - .5,
        rnd.nextDouble() - .5,
      );
      final w = ax * ((8 + rnd.nextDouble() * 8) / math.max(ax.length, 1e-6));
      dice.add(
        _Die(
          V3(x0, y0, hs * 2.6 + rnd.nextDouble() * hs),
          V3(vx, vy, vz),
          q,
          w,
        ),
      );
    }

    final frames = <List<DieFrame>>[];
    final events = <ThrowEvent>[];

    double applyImpulse(_Die d, V3 r, V3 nrm, double e, double mu) {
      var vrel = d.v + d.w.cross(r);
      final vn = vrel.dot(nrm);
      if (vn >= 0) return 0;
      final rn = r.cross(nrm);
      final kn = 1 + rn.dot(rn) / inertia;
      final j = -(1 + e) * vn / kn;
      d.v = d.v + nrm * j;
      d.w = d.w + r.cross(nrm * j) * (1 / inertia);
      vrel = d.v + d.w.cross(r);
      final vt = vrel - nrm * vrel.dot(nrm);
      final vtl = vt.length;
      if (vtl > 1e-6) {
        final t = vt * (1 / vtl);
        final rt = r.cross(t);
        final kt = 1 + rt.dot(rt) / inertia;
        final jt = math.min(mu * j, vtl / kt);
        d.v = d.v - t * jt;
        d.w = d.w - r.cross(t * jt) * (1 / inertia);
      }
      return -vn;
    }

    var t = 0.0;
    final steps = (maxT / dt).round();
    for (var step = 0; step < steps; step++) {
      final late = t > maxT - 0.35; // force-damp ramp toward 2.2 s
      for (var i = 0; i < n; i++) {
        final d = dice[i];
        if (d.done) continue;
        if (d.snapK != null) {
          final k = d.snapK! + 1;
          final e = 1 - math.pow(1 - k / snapSteps, 3).toDouble();
          d.q = Quat.slerp(d.snapFrom!, d.snapTo!, e.clamp(0, 1));
          d.p = V3(d.p.x, d.p.y, d.p.z + (hs - d.p.z) * 0.5);
          d.snapK = k;
          if (k >= snapSteps) {
            d.p = V3(d.p.x, d.p.y, hs);
            d.q = d.snapTo!;
            d.done = true;
          }
          continue;
        }
        d.v = V3(d.v.x, d.v.y, d.v.z + g * dt);
        d.p = d.p + d.v * dt;
        final wl = d.w.length;
        if (wl > 1e-9) d.q = (Quat.axisAngle(d.w, wl * dt) * d.q).normalized();
        // Felt.
        final cw = [for (final c in _corners) d.q.rotate(c * hs)];
        var minZ = double.infinity;
        for (final c in cw) {
          minZ = math.min(minZ, d.p.z + c.z);
        }
        final contact = minZ < 0.5;
        if (minZ < 0) {
          d.p = V3(d.p.x, d.p.y, d.p.z - minZ);
          var vimp = 0.0;
          for (var it = 0; it < 3; it++) {
            for (final c in cw) {
              if (d.p.z + c.z < 0.5) {
                final vi = applyImpulse(
                  d,
                  c,
                  const V3(0, 0, 1),
                  it == 0 ? feltRestitution : 0,
                  feltFriction,
                );
                vimp = math.max(vimp, vi);
              }
            }
          }
          if (vimp > 220) {
            d.bounces++;
            events.add(ThrowEvent(ThrowEventKind.land, t, i, vimp));
          }
          d.w = d.w * 0.985; // spin damped per contact
          d.v = V3(d.v.x * 0.992, d.v.y * 0.992, d.v.z);
        }
        // Rail: the felt's inner oval.
        final dx = d.p.x - cx, dy = d.p.y - cy;
        final f = (dx / ra) * (dx / ra) + (dy / rb) * (dy / rb);
        if (f > 1) {
          final s = 1 / math.sqrt(f);
          d.p = V3(cx + dx * s, cy + dy * s, d.p.z);
          final gx = dx / (ra * ra), gy = dy / (rb * rb);
          final gl = math.sqrt(gx * gx + gy * gy);
          final nout = V3(gx / gl, gy / gl, 0);
          final vi = applyImpulse(
            d,
            nout * (hs * 1.1),
            -nout,
            railRestitution,
            0.3,
          );
          if (vi > 60) {
            // Rails kick in a little extra spin.
            d.w = d.w + V3(-nout.y, nout.x, 0.6) * (vi / dieSize * 0.15);
            events.add(ThrowEvent(ThrowEventKind.rail, t, i, vi));
          }
        }
        // Soft obstacle: pot bowl.
        if (avoid != null) {
          final (bx, by, br) = avoid;
          final ox = d.p.x - bx, oy = d.p.y - by;
          final ol = math.sqrt(ox * ox + oy * oy);
          if (ol < br + hs * 1.4 && ol > 1e-6) {
            final push = (br + hs * 1.4 - ol) * 6;
            d.v = V3(d.v.x + ox / ol * push, d.v.y + oy / ol * push, d.v.z);
          }
        }
        // Settle test.
        final m = d.q.matrix;
        final upal = math.max(m[6].abs(), math.max(m[7].abs(), m[8].abs()));
        final sp = d.v.length, sw = d.w.length;
        if (contact && sp < 22 && sw < 1.4 && upal > 0.985) {
          d.still++;
        } else {
          d.still = 0;
        }
        if (contact && upal > 0.9 && sp < 60 && sw < 4) {
          d.w = d.w * 0.93;
          d.v = V3(d.v.x * 0.95, d.v.y * 0.95, d.v.z);
        }
        if (late) {
          final k = 0.80 + 0.15 * (maxT - t) / 0.35;
          d.w = d.w * k;
          d.v = V3(d.v.x * k, d.v.y * k, d.v.z);
        }
        if (d.still >= stillSteps || (contact && t >= maxT - 0.12)) {
          _beginSnap(d);
        }
      }
      _dieDie(dice, hs, events, t);
      t += dt;
      frames.add([
        for (final d in dice) DieFrame(d.p, d.q, d.v.length, settled: d.done),
      ]);
      if (dice.every((d) => d.done)) break;
    }
    // Deadline: anything still airborne snaps flat where it is.
    if (!dice.every((d) => d.done)) {
      for (final d in dice) {
        if (!d.done) {
          _beginSnap(d);
          d.q = d.snapTo!;
          d.p = V3(d.p.x, d.p.y, hs);
          d.done = true;
        }
      }
      _separate(dice, hs, cx, cy, ra, rb);
      frames.add([for (final d in dice) DieFrame(d.p, d.q, 0, settled: true)]);
    } else {
      final moved = _separate(dice, hs, cx, cy, ra, rb);
      if (moved) {
        frames.add([
          for (final d in dice) DieFrame(d.p, d.q, 0, settled: true),
        ]);
      }
    }

    final relabel = <Quat>[];
    for (var i = 0; i < n; i++) {
      relabel.add(moving[i] ? _upRelabel(dice[i].q) : Quat.identity);
    }
    return ThrowResult(
      frames: frames,
      events: events,
      relabel: relabel,
      settleTime: frames.length * dt,
      dieSize: dieSize,
      moving: List.of(moving),
    );
  }

  static void _beginSnap(_Die d) {
    final m = d.q.matrix;
    var k = 0;
    for (var c = 1; c < 3; c++) {
      if (m[6 + c].abs() > m[6 + k].abs()) k = c;
    }
    final sgn = m[6 + k] >= 0 ? 1.0 : -1.0;
    final up = V3(m[k] * sgn, m[3 + k] * sgn, m[6 + k] * sgn);
    final axis = up.cross(const V3(0, 0, 1));
    final ang = math.asin(math.min(1.0, axis.length));
    d.snapFrom = d.q;
    d.snapTo = (Quat.axisAngle(axis, ang) * d.q).normalized();
    d.snapK = 0;
    d.v = V3.zero;
    d.w = V3.zero;
  }

  /// Body rotation C with q·C·ẑ = ẑ: the body axis that ended on top
  /// becomes the "value" face (opposites sum to 7 by construction).
  static Quat _upRelabel(Quat q) {
    final m = q.matrix;
    var k = 0;
    for (var c = 1; c < 3; c++) {
      if (m[6 + c].abs() > m[6 + k].abs()) k = c;
    }
    final s = m[6 + k] >= 0 ? 1.0 : -1.0;
    const h = math.pi / 2;
    switch ((k, s > 0)) {
      case (2, true):
        return Quat.identity;
      case (2, false):
        return Quat.axisAngle(const V3(1, 0, 0), math.pi);
      case (0, true): // ẑ -> +x̂
        return Quat.axisAngle(const V3(0, 1, 0), h);
      case (0, false):
        return Quat.axisAngle(const V3(0, 1, 0), -h);
      case (1, true): // ẑ -> +ŷ
        return Quat.axisAngle(const V3(1, 0, 0), -h);
      default:
        return Quat.axisAngle(const V3(1, 0, 0), h);
    }
  }

  static void _dieDie(
    List<_Die> dice,
    double hs,
    List<ThrowEvent> events,
    double t,
  ) {
    for (var i = 0; i < dice.length; i++) {
      for (var j = i + 1; j < dice.length; j++) {
        final a = dice[i], b = dice[j];
        final wa = a.frozen ? 0.0 : 1.0, wb = b.frozen ? 0.0 : 1.0;
        if (wa + wb == 0) continue;
        if ((a.p - b.p).planar > hs * 3.6) continue;
        // Airborne over the other die: no footprint contact.
        if ((a.p.z - b.p.z).abs() > hs * 2) continue;
        final o = footprintOf(a.p, a.q, hs).overlap(footprintOf(b.p, b.q, hs));
        if (o == null) continue;
        final (nx, ny, depth) = o;
        final sa = wa / (wa + wb), sb = wb / (wa + wb);
        a.p = V3(a.p.x + nx * depth * sa, a.p.y + ny * depth * sa, a.p.z);
        b.p = V3(b.p.x - nx * depth * sb, b.p.y - ny * depth * sb, b.p.z);
        final nrm = V3(nx, ny, 0);
        final vn = (a.v - b.v).dot(nrm);
        if (vn >= 0) continue;
        // Equal and opposite impulse (fixed dice: infinite mass).
        final imp = -(1 + dieRestitution) * vn / (wa + wb);
        a.v = a.v + nrm * (imp * wa);
        b.v = b.v - nrm * (imp * wb);
        final spin = V3(0, 0, (nx - ny) * imp / hs * 0.5);
        a.w = a.w + spin * wa;
        b.w = b.w - spin * wb;
        if (-vn > 60) {
          events.add(ThrowEvent(ThrowEventKind.hit, t, i, -vn, other: j));
        }
      }
    }
  }

  /// Guarantee zero footprint overlap at rest and stay inside the rail.
  static bool _separate(
    List<_Die> dice,
    double hs,
    double cx,
    double cy,
    double ra,
    double rb,
  ) {
    var moved = false;
    for (var iter = 0; iter < 40; iter++) {
      var any = false;
      for (var i = 0; i < dice.length; i++) {
        for (var j = i + 1; j < dice.length; j++) {
          final a = dice[i], b = dice[j];
          final fa = footprintOf(a.p, a.q, hs), fb = footprintOf(b.p, b.q, hs);
          final o = fa.overlap(fb);
          if (o == null) continue;
          any = true;
          final (nx, ny, depth) = o;
          final wa = a.fixed ? 0.0 : 1.0, wb = b.fixed ? 0.0 : 1.0;
          final tot = math.max(wa + wb, 1e-9);
          final d = depth + 0.5;
          a.p = V3(a.p.x + nx * d * wa / tot, a.p.y + ny * d * wa / tot, a.p.z);
          b.p = V3(b.p.x - nx * d * wb / tot, b.p.y - ny * d * wb / tot, b.p.z);
        }
      }
      for (final d in dice) {
        if (d.fixed) continue;
        final dx = d.p.x - cx, dy = d.p.y - cy;
        final f = (dx / ra) * (dx / ra) + (dy / rb) * (dy / rb);
        if (f > 1) {
          final s = 1 / math.sqrt(f);
          d.p = V3(cx + dx * s, cy + dy * s, d.p.z);
        }
      }
      if (!any) break;
      moved = true;
    }
    return moved;
  }
}
