import 'dart:async';

import 'package:flutter/material.dart';

import '../../online/online_errors.dart';
import '../../online/room_models.dart';
import '../../online/room_service.dart';
import '../theme/marge_theme.dart';
import 'online_lobby_screen.dart';

/// Online table driven entirely by server room state. The local seat can
/// hold dice, roll (server rolls) and bank. Offline MatchScreen is untouched.
class OnlineMatchScreen extends StatefulWidget {
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

  @override
  State<OnlineMatchScreen> createState() => _OnlineMatchScreenState();
}

class _OnlineMatchScreenState extends State<OnlineMatchScreen> {
  List<bool> _hold = [false, false, false];
  int _holdForVersion = -1;
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

  @override
  void initState() {
    super.initState();
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
    final room = _room;
    final m = room?.match;
    if (room != null &&
        m != null &&
        (m.finished || room.status == RoomStatus.finished)) {
      return OnlineMatchResult(
        room: room,
        match: m,
        myUid: widget.myUid,
        fallbackStart: _firstBanks,
        onPlayAgain: _playAgain,
        onDone: _done,
      );
    }
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
      body: Column(
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
                : _table(room, m),
          ),
        ],
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

  Widget _table(Room room, MatchView m) {
    final turn = m.turn;
    final mySeat = m.seats.indexWhere((s) => s.uid == widget.myUid);
    final myTurn = turn != null && turn.seat == mySeat && !m.finished;
    if (turn != null && _holdForVersion != room.version) {
      _holdForVersion = room.version;
      _hold = turn.rollNumber == 0 ? [false, false, false] : [...turn.kept];
    }
    String label(int i) => m.seats[i].displayName ?? 'Seat ${i + 1}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Round ${m.round} · Pot ${m.pot} gems',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        for (final s in m.seats)
          if (s.kind != SeatKind.open)
            ListTile(
              dense: true,
              leading: Icon(
                turn?.seat == s.index ? Icons.casino : Icons.person_outline,
              ),
              title: Text(
                '${label(s.index)}${s.index == mySeat ? ' (you)' : ''}',
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
              style: const TextStyle(
                color: MargeColors.cream,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (m.finished)
          Text(
            m.winnerSeat == null
                ? 'Match over.'
                : 'Match over — ${label(m.winnerSeat!)} wins!',
            style: Theme.of(context).textTheme.headlineSmall,
          )
        else if (turn != null) ...[
          Text(
            myTurn
                ? 'Your turn · roll ${turn.rollNumber}/3'
                : "${label(turn.seat)}'s turn · roll ${turn.rollNumber}/3",
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: GestureDetector(
                    key: ValueKey('online-die-$i'),
                    onTap: myTurn && turn.hasRolled && turn.canRoll
                        ? () => setState(() => _hold[i] = !_hold[i])
                        : null,
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _hold[i] ? Colors.amber : Colors.black26,
                          width: _hold[i] ? 4 : 1,
                        ),
                      ),
                      child: Text(
                        turn.hasRolled ? '${turn.dice[i]}' : '–',
                        style: const TextStyle(
                          fontSize: 28,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (myTurn && turn.hasRolled && turn.canRoll)
            const Text('Tap dice to hold.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (myTurn)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _busy || !turn.canRoll
                      ? null
                      : () => _do(
                          () => widget.rooms.submitRoll(
                            room.id,
                            keepIndexes: [
                              for (var i = 0; i < 3; i++)
                                if (_hold[i]) i,
                            ],
                            expectedVersion: room.version,
                          ),
                        ),
                  child: Text(
                    turn.hasRolled ? 'ROLL (${turn.rollsLeft} left)' : 'ROLL',
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _busy || !turn.isScoring
                      ? null
                      : () => _do(
                          () => widget.rooms.bank(
                            room.id,
                            expectedVersion: room.version,
                          ),
                        ),
                  child: const Text('BANK'),
                ),
              ],
            ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
      ],
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [MargeColors.velvet, MargeColors.felt],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
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
