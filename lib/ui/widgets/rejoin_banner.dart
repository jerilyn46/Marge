import 'package:flutter/material.dart';

import '../../online/online_errors.dart';
import '../../online/room_models.dart';
import '../theme/marge_theme.dart';

/// "Rejoin your match" card shown on Set the table / the online lobby when
/// this device's online player is still seated in a live room.
class RejoinBanner extends StatelessWidget {
  const RejoinBanner({
    super.key,
    required this.room,
    required this.onRejoin,
    required this.onLeave,
    this.busy = false,
  });

  final Room room;
  final VoidCallback onRejoin;
  final VoidCallback onLeave;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final playing = room.status == RoomStatus.playing;
    return Card(
      key: const ValueKey('rejoin-banner'),
      color: MargeColors.felt,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Rejoin your match',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              playing
                  ? 'Your online match${room.code.isEmpty ? '' : ' (room ${room.code})'} is still going.'
                  : 'You are still in online room ${room.code}.',
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('rejoin-leave'),
                  onPressed: busy ? null : onLeave,
                  child: const Text('LEAVE'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const ValueKey('rejoin-go'),
                  onPressed: busy ? null : onRejoin,
                  child: const Text('REJOIN'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Leave confirmation; a running match keeps your current table bank.
Future<bool> confirmLeaveRoom(BuildContext context, Room room) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Leave this match?'),
      content: Text(
        room.status == RoomStatus.playing
            ? "You'll be out of this match and keep the gems you have at the table."
            : "You'll give up your seat in room ${room.code}.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Leave'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Looks up this device's live online room and, if there is one, shows a
/// [RejoinBanner]. Renders nothing when invite play is off, this device never
/// played online, or there is no live room. Re-checks after Rejoin/Leave.
class RejoinPrompt extends StatefulWidget {
  const RejoinPrompt({
    super.key,
    required this.find,
    required this.onRejoin,
    required this.leave,
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  /// Returns the live room for the persisted uid, or null.
  final Future<Room?> Function() find;

  /// Opens the room; when the returned future completes we look again.
  final Future<void> Function(Room room) onRejoin;

  /// Leaves the room via the existing leaveRoom flow.
  final Future<void> Function(Room room) leave;
  final EdgeInsets padding;

  @override
  State<RejoinPrompt> createState() => RejoinPromptState();
}

class RejoinPromptState extends State<RejoinPrompt> {
  Room? _room;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    Room? r;
    try {
      r = await widget.find();
    } catch (e) {
      debugPrint('marge-online[active-room]: $e');
    }
    if (mounted) setState(() => _room = r);
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    if (room == null) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: RejoinBanner(
        room: room,
        busy: _busy,
        onRejoin: () async {
          setState(() => _room = null);
          await widget.onRejoin(room);
          await refresh();
        },
        onLeave: () async {
          if (!await confirmLeaveRoom(context, room)) return;
          if (!mounted) return;
          setState(() => _busy = true);
          String? err;
          try {
            await widget.leave(room);
          } catch (e) {
            err = OnlineErrors.friendly(e, where: 'rejoin-leave');
          }
          if (!mounted) return;
          setState(() => _busy = false);
          if (err != null) {
            ScaffoldMessenger.maybeOf(this.context)
                ?.showSnackBar(SnackBar(content: Text(err)));
          }
          await refresh();
        },
      ),
    );
  }
}
