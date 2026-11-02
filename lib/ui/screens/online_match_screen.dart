import 'package:flutter/material.dart';

import '../../online/room_models.dart';
import '../../online/room_service.dart';
import '../theme/marge_theme.dart';

/// Online table driven entirely by server room state. The local seat can
/// hold dice, roll (server rolls) and bank. Offline MatchScreen is untouched.
class OnlineMatchScreen extends StatefulWidget {
  const OnlineMatchScreen({
    super.key,
    required this.rooms,
    required this.roomId,
    required this.myUid,
  });

  final RoomService rooms;
  final String roomId;
  final String myUid;

  @override
  State<OnlineMatchScreen> createState() => _OnlineMatchScreenState();
}

class _OnlineMatchScreenState extends State<OnlineMatchScreen> {
  List<bool> _hold = [false, false, false];
  int _holdForVersion = -1;
  bool _busy = false;
  String? _error;

  Future<void> _do(Future<void> Function() op) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await op();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Room?>(
      stream: widget.rooms.watchRoom(widget.roomId),
      builder: (context, snap) {
        final room = snap.data;
        final m = room?.match;
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
          body: room == null || m == null
              ? const Center(child: CircularProgressIndicator())
              : _table(room, m),
        );
      },
    );
  }

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
