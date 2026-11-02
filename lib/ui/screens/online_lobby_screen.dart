import 'package:flutter/material.dart';

import '../../online/auth_service.dart';
import '../../online/room_models.dart';
import '../../online/room_service.dart';

/// WIP: create or join an invite room by short code.
/// Hidden behind kOnlineInviteEnabled; gameplay UI for online rooms is the
/// next slice (this screen only shows the seat list once seated).
class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({
    super.key,
    required this.displayName,
    required this.gemClaim,
  });

  final String displayName;
  final int gemClaim;

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  final _code = TextEditingController();
  RoomService? _rooms;
  String? _roomId;
  String? _error;
  bool _busy = true;
  int _bots = 0;

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
        _rooms = RoomService();
      }
    });
  }

  Future<void> _run(Future<String> Function(RoomService r) op) async {
    final r = _rooms;
    if (r == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await op(r);
      if (mounted) setState(() => _roomId = id);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete my online data?'),
        content: const Text(
          'Deletes your online account, display name, online gem balance and room history from our servers. Offline play and your on-device gems are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final done = await OnlineAuthService.instance.deleteOnlineData();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _rooms = null;
      _error = done
          ? 'Online data deleted.'
          : OnlineAuthService.instance.lastError;
    });
  }

  @override
  void dispose() {
    _code.dispose();
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
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
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
          onPressed: _rooms == null || _busy
              ? null
              : () => _run(
                  (r) async => (await r.createRoom(
                    seatCount: 4,
                    botCount: _bots,
                    ante: 10,
                    displayName: widget.displayName,
                    clientGemClaim: widget.gemClaim,
                  )).roomId,
                ),
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
                    displayName: widget.displayName,
                    clientGemClaim: widget.gemClaim,
                  ),
                ),
          child: const Text('JOIN BY CODE'),
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: _busy ? null : _confirmDelete,
          child: const Text('Delete my online data'),
        ),
      ],
    );
  }

  Widget _roomView() {
    return StreamBuilder<Room?>(
      stream: _rooms!.watchRoom(_roomId!),
      builder: (context, snap) {
        final room = snap.data;
        if (room == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          children: [
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
            if (room.status == RoomStatus.lobby)
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
