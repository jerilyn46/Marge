import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/settings_service.dart';
import '../theme/marge_theme.dart';

class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key, this.fromOnboarding = false});

  final bool fromOnboarding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('How to play Marge'),
        actions: [
          if (fromOnboarding)
            TextButton(
              onPressed: () async {
                await ref.read(settingsProvider.notifier).setSeenRules(true);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Got it'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _RuleCard(
            emoji: '🏦',
            title: 'Banks & ante',
            body:
                '2–8 seats. You and local hotseat humans sit first, then named friends (waiting if they are not here), then reserved online chairs, then bots in leftover seats. '
                'The gem bank is uncommitted play money. A new game sits you with up to 100 gems from that bank. '
                'Each unfinished game keeps its own pot and table gems. Bots on a saved table keep those gems until that game ends. '
                'Each round, every playing seat antes 10 gems into the pot.',
          ),
          _RuleCard(
            emoji: '🎲',
            title: 'Your turn',
            body:
                'Roll 3 dice, up to 3 times. Tap dice to keep them between rolls. '
                'A winning hand banks the payout and resets you to 3 new rolls. '
                'The turn ends only after 3 rolls with no winning hand: bust 2 gems into the pot.',
          ),
          _RuleCard(
            emoji: '👑',
            title: 'Triple ones — first roll',
            body:
                'Three 1s on the first roll of a set takes the entire pot and ends the round. '
                'Everyone antes again, and it is still your turn for 3 new rolls.',
          ),
          _RuleCard(
            emoji: '💰',
            title: 'Other scores',
            body:
                'Triple ones on roll 2/3: each other player pays you 10 gems.\n'
                'Three 2s-6s on the first roll: each other pays 2x the face. Later three-of-a-kind pays the face value.\n'
                'Straight (123/234/345/456): each other pays 5 gems.\n'
                'No score after 3 rolls: put 2 gems in the pot.',
          ),
          _RuleCard(
            emoji: '🏠',
            title: 'House stake',
            body:
                'Soft bankrupt: once per match the House tops you up 50 gems. '
                'After that, running dry can knock you out. Endless rounds until you End match.',
          ),
          _RuleCard(
            emoji: '🤖',
            title: 'Bots',
            body:
                'Choose 0–4 other local players, 0–4 online seats, and 0–4 bots '
                '(at least one bot or local player; max 8 seats including you). '
                'Online seats are reserved before bots. There is no live match yet, so they show as Waiting for player and are not filled by bots. '
                'Bots cycle Aggressive / Cautious / Chaotic. '
                'On a hotseat human turn, pass the device.',
          ),
        ],
      ),
      bottomNavigationBar: fromOnboarding
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () async {
                    await ref
                        .read(settingsProvider.notifier)
                        .setSeenRules(true);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Let\'s roll'),
                ),
              ),
            )
          : null,
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.emoji,
    required this.title,
    required this.body,
  });

  final String emoji;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: MargeColors.gold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(body, style: const TextStyle(height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
