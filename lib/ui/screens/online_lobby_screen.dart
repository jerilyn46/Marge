import 'dart:async';

import 'package:flutter/material.dart';

import '../../online/auth_service.dart';
import '../../online/delete_online_data.dart';
import '../../online/online_errors.dart';
import '../../online/room_models.dart';
import '../../online/room_service.dart';
import '../../online/turn_push.dart';
import '../widgets/rejoin_banner.dart';
import 'online_match_screen.dart';

/// WIP: create or join an invite room by short code.
/// Hidden behind kOnlineInviteEnabled; gameplay UI for online rooms is the
/// next slice (this screen only shows the seat list once seated).
class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({
    super.key,
    required this.displayName,
    required this.gemClaim,
    this.autoCreate = false,
    this.seatCount = 4,
    this.initialBots = 0,
    this.ante = 10,
    this.resumeRoomId,
  });

  final String displayName;
  final int gemClaim;

  /// "Play again" from a finished match as host: create the next room right
  /// away (same table size, bots and ante) and show its code.
  final bool autoCreate;
  final int seatCount;
  final int initialBots;
  final int ante;

  /// "Rejoin your match": open this room directly (lobby view, or straight
  /// to the match screen if it is already playing).
  final String? resumeRoomId;

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  final _code = TextEditingController();
  late final _nameCtl = TextEditingController(text: widget.displayName);
  String? _uid;
  bool _opened = false;
  RoomService? _rooms;
  String? _roomId;
  String? _error;
  bool _busy = true;
  late int _bots = widget.initialBots.clamp(0, 3);
  Stream<Room?>? _roomStream;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = await OnlineAuthService.instance.signInAnonymously();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (uid == null) {
        _error = OnlineAuthService.instance.lastError;
      } else {
        _uid = uid;
        _rooms = RoomService();
      }
    });
    if (uid == null) return;
    // First time online: ask for notifications once (Android 13+) and
    // register for "Your turn" pushes. Denied → hint below, never re-asked.
    unawaited(TurnPush.instance.enableForOnline());
    if (widget.resumeRoomId != null) {
      _resume(widget.resumeRoomId!);
    } else if (widget.autoCreate) {
      _create();
    }
  }

  void _resume(String roomId) {
    final r = _rooms;
    if (r == null) return;
    setState(() {
      _error = null;
      _opened = false;
      _roomId = roomId;
      _roomStream = r.watchRoom(roomId).handleError((Object e) {
        debugPrint('marge-online[lobby-stream]: $e');
      });
    });
  }

  void _create() => _run(
    (r) async => (await r.createRoom(
      seatCount: widget.seatCount,
      botCount: _bots.clamp(0, widget.seatCount - 1),
      ante: widget.ante,
      displayName: _name,
      clientGemClaim: widget.gemClaim,
    )).roomId,
  );

  Future<void> _run(Future<String> Function(RoomService r) op) async {
    final r = _rooms;
    if (r == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await op(r);
      if (mounted) {
        setState(() {
          if (id != _roomId) {
            _roomStream = r.watchRoom(id).handleError((Object e) {
              debugPrint('marge-online[lobby-stream]: $e');
            });
          }
          _roomId = id;
        });
      }
    } catch (e) {
      final msg = OnlineErrors.friendly(e, where: 'lobby');
      if (mounted) setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final done = await confirmAndDeleteOnlineData(context);
    if (done && mounted) setState(() => _rooms = null);
  }

  String get _name {
    final uid = _uid ?? '';
    final typed = _nameCtl.text.trim();
    return OnlineAuthService.seatLabel(typed.isEmpty ? null : typed, uid);
  }

  /// Back to the entry view (code field) with a friendly note.
  Widget _ended(String text) => ListView(
    children: [
      Text(text, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () => setState(() {
          _roomId = null;
          _roomStream = null;
          _opened = false;
        }),
        child: const Text('BACK'),
      ),
    ],
  );

  @override
  void dispose() {
    _code.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Play online (invite)')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _roomId != null ? _roomView() : _entryView(),
      ),
    );
  }

  Widget _entryView() {
    return ListView(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_rooms != null && _uid != null)
          RejoinPrompt(
            key: ValueKey('lobby-rejoin-$_uid'),
            find: () => _rooms!.findMyActiveRoom(_uid!),
            onRejoin: (room) async => _resume(room.id),
            leave: (room) => _rooms!.leaveRoom(room.id),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        const PushOffHint(),
        TextField(
          key: const ValueKey('online-display-name'),
          controller: _nameCtl,
          maxLength: 20,
          decoration: const InputDecoration(
            labelText: 'Display name (optional)',
            helperText: 'Shown to other players. Blank = Player + ID.',
          ),
        ),
        Text('Bots in leftover seats: $_bots'),
        Slider(
          value: _bots.toDouble(),
          max: 3,
          divisions: 3,
          onChanged: (v) => setState(() => _bots = v.round()),
        ),
        ElevatedButton(
          onPressed: _rooms == null || _busy ? null : _create,
          child: const Text('CREATE ROOM'),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'Room code'),
        ),
        OutlinedButton(
          onPressed: _rooms == null || _busy
              ? null
              : () => _run(
                  (r) => r.joinByCode(
                    _code.text,
                    displayName: _name,
                    clientGemClaim: widget.gemClaim,
                  ),
                ),
          child: const Text('JOIN BY CODE'),
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: _busy ? null : _delete,
          child: const Text('Delete my online data'),
        ),
      ],
    );
  }

  Widget _roomView() {
    return StreamBuilder<Room?>(
      stream: _roomStream,
      builder: (context, snap) {
        final room = snap.data;
        if (snap.connectionState == ConnectionState.done && room == null) {
          return _ended("That room code isn't active.");
        }
        if (room == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (room.status == RoomStatus.abandoned) {
          return _ended('This room was closed.');
        }
        if (room.status != RoomStatus.lobby && room.match != null && !_opened) {
          _opened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => OnlineMatchScreen(
                  rooms: _rooms!,
                  roomId: room.id,
                  myUid: _uid!,
                  displayName: _name,
                  gemClaim: widget.gemClaim,
                ),
              ),
            );
          });
        }
        return ListView(
          children: [
            const PushOffHint(),
            SelectableText(
              'Code: ${room.code}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              'Status: ${room.status.name} · Ante ${room.ante} · Pot ${room.pot}',
            ),
            const SizedBox(height: 12),
            for (final s in room.seats)
              ListTile(
                leading: Text('${s.index + 1}'),
                title: Text(
                  s.isOpen
                      ? 'Waiting for player'
                      : (s.displayName ?? s.kind.name),
                ),
                subtitle: Text(s.kind.name),
              ),
            if (room.status == RoomStatus.lobby && room.hostUid == _uid)
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _run((r) async {
                        await r.startMatch(room.id);
                        return room.id;
                      }),
                child: const Text('START (host)'),
              ),
          ],
        );
      },
    );
  }
}

/// One quiet line when notifications are off for Marge (no dialog, no
/// re-asking): the in-app "Your turn!" banner still works while open.
class PushOffHint extends StatelessWidget {
  const PushOffHint({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool?>(
    valueListenable: TurnPush.instance.permitted,
    builder: (context, ok, _) => ok == false
        ? Padding(
            key: const ValueKey('online-push-off-hint'),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              "Notifications are off, so you'll only see \"Your turn\" while "
              'Marge is open. You can turn them on in Android Settings.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}
