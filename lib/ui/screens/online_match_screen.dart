import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cosmetics/dice_skin.dart';
import '../../cosmetics/skins_service.dart';
import '../../online/online_errors.dart';
import '../../online/room_models.dart';
import '../../online/room_service.dart';
import '../../online/turn_watch.dart';
import '../../services/settings_service.dart';
import '../../services/sfx_service.dart';
import '../theme/marge_theme.dart';
import '../visuals/dice_3d.dart';
import '../widgets/table_felt_background.dart';
import 'online_lobby_screen.dart';

/// Online table driven entirely by server room state. Same table look as
/// offline play: the player's equipped felt and dice skin, the 3D
/// [DiceTray] tumble (with its haptics/sound hooks) on every server roll —
/// yours, the opponent's, bots' and timeout auto-plays. The local seat can
/// hold dice, roll (server rolls) and bank.
class OnlineMatchScreen extends ConsumerStatefulWidget {
  const OnlineMatchScreen({
    super.key,
    required this.rooms,
    required this.roomId,
    required this.myUid,
    this.displayName = '',
    this.gemClaim = 0,
  });

  final RoomService rooms;
  final String roomId;
  final String myUid;

  /// Passed through to the lobby for "Play again".
  final String displayName;
  final int gemClaim;

  /// Room shown by the open match screen (null when none), so a "Your turn"
  /// notification tap for that same room doesn't stack a second screen.
  static final ValueNotifier<String?> openRoomId = ValueNotifier(null);

  @override
  ConsumerState<OnlineMatchScreen> createState() => _OnlineMatchScreenState();
}

class _OnlineMatchScreenState extends ConsumerState<OnlineMatchScreen> {
  bool _busy = false;
  String? _error;

  // One subscription for the screen's life (not one per rebuild). A stream
  // error never pops or leaves: we show "Reconnecting…" and resubscribe.
  StreamSubscription<Room?>? _sub;
  Room? _room;
  bool _reconnecting = false;
  bool _gone = false;
  Timer? _retry;
  List<int>? _firstBanks; // fallback start banks for older rooms

  /// The room as it was when the match finished. The result screen shows
  /// this frozen copy, so later edits to the room doc (e.g. another player's
  /// "Delete my online data", or the room's retention delete) never relabel
  /// the winner or the message while it is open (GPLLGC).
  Room? _finalRoom;

  @override
  void initState() {
    super.initState();
    OnlineMatchScreen.openRoomId.value = widget.roomId;
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    _sub = widget.rooms
        .watchRoom(widget.roomId)
        .listen(
          (r) {
            if (!mounted) return;
            setState(() {
              _reconnecting = false;
              if (r == null) {
                _gone = true;
                return;
              }
              _room = r;
              final fm = r.match;
              if (_finalRoom == null &&
                  fm != null &&
                  (fm.finished || r.status == RoomStatus.finished)) {
                _finalRoom = r;
              }
              final m = r.match;
              if (_firstBanks == null && m != null && !m.finished) {
                _firstBanks = [for (final s in m.seats) s.bank];
              }
            });
          },
          onError: (Object e) {
            debugPrint('marge-online[room-stream]: $e');
            if (!mounted) return;
            setState(() => _reconnecting = true);
            _retry?.cancel();
            _retry = Timer(const Duration(seconds: 3), () {
              if (mounted) _listen();
            });
          },
        );
  }

  @override
  void dispose() {
    if (OnlineMatchScreen.openRoomId.value == widget.roomId) {
      OnlineMatchScreen.openRoomId.value = null;
    }
    _retry?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _do(Future<void> Function() op) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await op();
    } catch (e) {
      final msg = OnlineErrors.friendly(e, where: 'match-action');
      if (mounted) setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _finalRoom;
    if (done != null) {
      return OnlineMatchResult(
        key: const ValueKey('online-result-frozen'),
        room: done,
        match: done.match!,
        myUid: widget.myUid,
        fallbackStart: _firstBanks,
        onPlayAgain: _playAgain,
        onDone: _done,
      );
    }
    final room = _room;
    final m = room?.match;
    final settings = ref.watch(settingsProvider);
    final skin = ref.watch(cosmeticsProvider).equippedTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(room == null ? 'Online' : 'Room ${room.code}'),
        actions: [
          if (room != null &&
              room.hostUid == widget.myUid &&
              m != null &&
              !m.finished)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _do(() => widget.rooms.endMatch(room.id)),
              child: const Text('End match'),
            ),
        ],
      ),
      body: TableFeltBackground(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_reconnecting)
                const MaterialBanner(
                  key: ValueKey('online-reconnecting'),
                  content: Text('Reconnecting…'),
                  leading: Icon(Icons.wifi_off),
                  actions: [SizedBox.shrink()],
                ),
              Expanded(
                child: _gone
                    ? _message('This match is no longer available.')
                    : room == null || m == null
                    ? const Center(child: CircularProgressIndicator())
                    : OnlineTable(
                        room: room,
                        myUid: widget.myUid,
                        busy: _busy,
                        error: _error,
                        skinTheme: skin,
                        sfxEnabled: settings.sfxEnabled,
                        hapticsEnabled: settings.hapticsEnabled,
                        onRoll: (keep) => _do(
                          () => widget.rooms.submitRoll(
                            room.id,
                            keepIndexes: keep,
                            expectedVersion: room.version,
                          ),
                        ),
                        onBank: () => _do(
                          () => widget.rooms.bank(
                            room.id,
                            expectedVersion: room.version,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _done, child: const Text('DONE')),
        ],
      ),
    ),
  );

  /// Host: straight to a new room (same table size, bots and ante) with its
  /// code shown. Joiner: back to the lobby to enter the next code.
  void _playAgain() {
    final room = _room;
    final isHost = room != null && room.hostUid == widget.myUid;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OnlineLobbyScreen(
          displayName: widget.displayName,
          gemClaim: widget.gemClaim,
          autoCreate: isHost,
          seatCount: room?.seats.length ?? 4,
          initialBots:
              room?.seats.where((s) => s.kind == SeatKind.bot).length ?? 0,
          ante: room?.ante ?? 10,
        ),
      ),
    );
  }

  /// Back to the home / setup screen.
  void _done() => Navigator.of(context).popUntil((r) => r.isFirst);
}

/// The live online table for one room snapshot. Pure UI over [room]: no
/// Firebase, so widget tests drive it with plain [Room] values.
///
/// Every new server roll (tracked by [OnlineRollTracker]) bumps the
/// [DiceTray] roll serial once, so the tumble + throw haptic + die-landed
/// clicks play for every seat's roll, and never on the first snapshot,
/// a rebuild, or a reconnect that re-delivers the same roll. When the turn
/// passes to you ([YourTurnDetector]) a "Your turn!" banner shows with a
/// heavy haptic and the system sound.
class OnlineTable extends StatefulWidget {
  const OnlineTable({
    super.key,
    required this.room,
    required this.myUid,
    required this.onRoll,
    required this.onBank,
    this.busy = false,
    this.error,
    this.skinTheme,
    this.sfxEnabled = true,
    this.hapticsEnabled = true,
    this.sfx,
  });

  final Room room;
  final String myUid;
  final void Function(List<int> keepIndexes) onRoll;
  final VoidCallback onBank;
  final bool busy;
  final String? error;
  final DiceSkinTheme? skinTheme;
  final bool sfxEnabled;
  final bool hapticsEnabled;

  /// Injected in tests (observe cues via [SfxService.debugOnCue]).
  final SfxService? sfx;

  static const bannerDuration = Duration(seconds: 3);

  @override
  State<OnlineTable> createState() => OnlineTableState();
}

class OnlineTableState extends State<OnlineTable> {
  final _rolls = OnlineRollTracker();
  final _turns = YourTurnDetector();
  late final SfxService _sfx =
      widget.sfx ??
      SfxService(
        sfxEnabled: widget.sfxEnabled,
        hapticsEnabled: widget.hapticsEnabled,
      );
  List<bool> _hold = [false, false, false];
  int _holdForVersion = -1;
  int _settledSerial = 0;
  bool _banner = false;
  Timer? _bannerTimer;
  Timer? _settleGuard;

  /// Local roll serial fed to the [DiceTray] (one bump per server roll).
  int get rollSerial => _rolls.serial;

  /// True while the "Your turn!" banner is up.
  bool get showingYourTurn => _banner;

  @override
  void initState() {
    super.initState();
    _observe(); // primes both detectors: no replay on first load
  }

  @override
  void didUpdateWidget(OnlineTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sfx == null) {
      _sfx
        ..sfxEnabled = widget.sfxEnabled
        ..hapticsEnabled = widget.hapticsEnabled;
    }
    if (!identical(oldWidget.room, widget.room)) _observe();
  }

  void _observe() {
    final m = widget.room.match;
    if (_rolls.observe(m)) {
      unawaited(_sfx.roll()); // throw tap; the tray adds rattle + landings
      _settleGuard?.cancel();
      final serial = _rolls.serial;
      // Never leave the buttons locked if a settle report is lost.
      _settleGuard = Timer(
        const Duration(milliseconds: DiceTray.dieMs + 1100),
        () {
          if (mounted && _settledSerial < serial) {
            setState(() => _settledSerial = serial);
          }
        },
      );
    }
    if (_turns.observe(m, widget.myUid)) {
      unawaited(_sfx.yourTurn());
      _banner = true;
      _bannerTimer?.cancel();
      _bannerTimer = Timer(OnlineTable.bannerDuration, () {
        if (mounted) setState(() => _banner = false);
      });
    } else if (!YourTurnDetector.isMyTurn(m, widget.myUid)) {
      _banner = false;
    }
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _settleGuard?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final m = room.match!;
    final turn = m.turn;
    final mySeat = m.seats.indexWhere((s) => s.uid == widget.myUid);
    final myTurn = turn != null && turn.seat == mySeat && !m.finished;
    if (turn != null && _holdForVersion != room.version) {
      _holdForVersion = room.version;
      _hold = turn.rollNumber == 0 ? [false, false, false] : [...turn.kept];
    }
    String label(int i) => m.seats[i].displayName ?? 'Seat ${i + 1}';
    final settling = _rolls.serial != _settledSerial;

    // Faces on the table: the turn in progress, else the last server roll
    // (e.g. the opponent's third-roll miss that already passed the turn).
    final last = m.lastRoll;
    final List<int>? faces = turn != null && turn.hasRolled
        ? turn.dice
        : last?.dice;
    final List<bool> held = turn != null && turn.hasRolled
        ? (myTurn ? _hold : turn.kept)
        : (last?.held ?? const [false, false, false]);
    final List<bool> rolledHeld =
        last?.held ??
        (turn != null && turn.hasRolled
            ? turn.kept
            : const [false, false, false]);
    final canHold = myTurn && turn.hasRolled && turn.canRoll && !settling;

    return LayoutBuilder(
      builder: (context, box) {
        final dieSize = ((box.maxWidth - 64) / 3.6).clamp(48.0, 72.0);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Round ${m.round} · Pot ${m.pot} gems',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: MargeColors.gold,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final s in m.seats)
              if (s.kind != SeatKind.open)
                ListTile(
                  dense: true,
                  leading: Icon(
                    turn?.seat == s.index ? Icons.casino : Icons.person_outline,
                    color: turn?.seat == s.index ? MargeColors.gold : null,
                  ),
                  title: Text(
                    '${label(s.index)}${s.index == mySeat ? ' (you)' : ''}',
                    style: TextStyle(
                      fontWeight: turn?.seat == s.index
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(s.eliminated ? 'Out' : s.kind.name),
                  trailing: Text('${s.bank} gems'),
                ),
            const Divider(),
            if (m.lastPayoutMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  m.lastPayoutMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MargeColors.cream,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _banner
                  ? Container(
                      key: const ValueKey('online-your-turn-banner'),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: MargeColors.gold.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: MargeColors.gold),
                      ),
                      child: const Text(
                        '🎲 Your turn!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: MargeColors.gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (turn != null) ...[
              Text(
                myTurn
                    ? 'Your turn · roll ${turn.rollNumber}/3'
                    : "${label(turn.seat)}'s turn · roll ${turn.rollNumber}/3",
                key: const ValueKey('online-turn-label'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: DiceTray(
                  // Keyed so banner rows coming and going never re-create
                  // the tray mid-throw (same reason as offline).
                  key: const ValueKey('online-dice-tray'),
                  values: faces ?? const [1, 1, 1],
                  dim: faces == null,
                  rollSerial: _rolls.serial,
                  kept: [
                    for (var i = 0; i < 3; i++)
                      faces != null && i < held.length && held[i],
                  ],
                  animate: [
                    for (var i = 0; i < 3; i++)
                      !(i < rolledHeld.length && rolledHeld[i]),
                  ],
                  enabled: [for (var i = 0; i < 3; i++) canHold],
                  onTap: (i) => setState(() => _hold[i] = !_hold[i]),
                  size: dieSize,
                  theme: widget.skinTheme,
                  sfx: _sfx,
                  onSettled: (serial) {
                    if (mounted && serial > _settledSerial) {
                      setState(() => _settledSerial = serial);
                    }
                  },
                ),
              ),
              if (canHold)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Tap dice to hold.', textAlign: TextAlign.center),
                ),
              const SizedBox(height: 12),
              if (myTurn)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      key: const ValueKey('online-roll'),
                      onPressed: widget.busy || settling || !turn.canRoll
                          ? null
                          : () => widget.onRoll([
                              for (var i = 0; i < 3; i++)
                                if (_hold[i]) i,
                            ]),
                      child: Text(
                        turn.hasRolled
                            ? 'ROLL (${turn.rollsLeft} left)'
                            : 'ROLL',
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      key: const ValueKey('online-bank'),
                      onPressed: widget.busy || settling || !turn.isScoring
                          ? null
                          : widget.onBank,
                      child: const Text('BANK'),
                    ),
                  ],
                ),
            ],
            if (widget.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  widget.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// End-of-match result for an online room, styled like the local match-end
/// screen: winner, each seat's gem change, the pot outcome, and
/// "play another game?" with Play again / Done.
class OnlineMatchResult extends StatelessWidget {
  const OnlineMatchResult({
    super.key,
    required this.room,
    required this.match,
    required this.myUid,
    required this.onPlayAgain,
    required this.onDone,
    this.fallbackStart,
  });

  final Room room;
  final MatchView match;
  final String myUid;
  final List<int>? fallbackStart;
  final VoidCallback onPlayAgain;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final rows = match.results(fallbackStart: fallbackStart);
    final winner = rows.where((r) => r.winner).firstOrNull;
    final me = rows.where((r) => r.uid == myUid).firstOrNull;
    final headline = winner == null
        ? 'Match over — no winner.'
        : winner.uid == myUid
        ? 'You win with ${winner.end} gems!'
        : '${winner.name} wins with ${winner.end} gems';
    return Scaffold(
      body: TableFeltBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('online-result-scroll'),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '🏆 Match over',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: MargeColors.gold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        headline,
                        key: const ValueKey('online-result-winner'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (match.lastPayoutMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          match.lastPayoutMessage!,
                          key: const ValueKey('online-result-pot'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: MargeColors.cream.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      for (final r in rows)
                        Card(
                          key: ValueKey('online-result-seat-${r.seat}'),
                          child: ListTile(
                            leading: Icon(
                              r.winner
                                  ? Icons.emoji_events
                                  : Icons.person_outline,
                              color: r.winner ? MargeColors.gold : null,
                            ),
                            title: Text(
                              '${r.name}${r.uid == myUid ? ' (you)' : ''}',
                            ),
                            subtitle: Text(
                              r.start == null
                                  ? '${r.end} gems${r.out ? ' · out' : ''}'
                                  : '${r.start} → ${r.end} gems${r.out ? ' · out' : ''}',
                            ),
                            trailing: r.changeLabel == null
                                ? null
                                : Text(
                                    r.changeLabel!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: (r.change ?? 0) > 0
                                          ? Colors.greenAccent
                                          : (r.change ?? 0) < 0
                                          ? Colors.redAccent
                                          : null,
                                    ),
                                  ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        '${me != null ? 'Your online gems are now ${me.end}. ' : ''}'
                        'Final pot ${match.pot} · virtual gems (not real money)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: MargeColors.cream.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Play another game?',
                      key: const ValueKey('online-play-again-prompt'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MargeColors.cream.withValues(alpha: 0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      key: const ValueKey('online-play-again'),
                      onPressed: onPlayAgain,
                      child: const Text('PLAY AGAIN'),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      key: const ValueKey('online-done'),
                      onPressed: onDone,
                      child: const Text('DONE'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
