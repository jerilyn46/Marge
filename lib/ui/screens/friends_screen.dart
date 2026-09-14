import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/friends_service.dart';
import '../theme/marge_theme.dart';

/// Full friends list — dense controls off the home lobby.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _friendName = TextEditingController();
  String? _friendError;

  @override
  void dispose() {
    _friendName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        backgroundColor: MargeColors.velvet,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [MargeColors.velvet, Color(0xFF243528)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'People you know. They sit before bots as named waiting chairs — no live connection.',
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.75),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _friendName,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              hintText: 'Add a friend by name',
                              isDense: true,
                            ),
                            onSubmitted: (_) => _add(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(onPressed: _add, child: const Text('Add')),
                      ],
                    ),
                    if (_friendError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _friendError!,
                        style: const TextStyle(
                          color: MargeColors.coral,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (friends.friends.isEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'No friends yet.',
                        style: TextStyle(
                          color: MargeColors.cream.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    for (final friend in friends.friends)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Checkbox(
                          value: friend.seated,
                          onChanged: (v) => ref
                              .read(friendsProvider.notifier)
                              .setSeated(friend.name, v ?? false),
                        ),
                        title: Text(
                          friend.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          FriendsLogic.statusLabel(friend),
                          style: TextStyle(
                            color: MargeColors.cream.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove ${friend.name}',
                          onPressed: () => ref
                              .read(friendsProvider.notifier)
                              .remove(friend.name),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    final err =
        await ref.read(friendsProvider.notifier).add(_friendName.text);
    if (!mounted) return;
    setState(() => _friendError = err);
    if (err == null) _friendName.clear();
  }
}
