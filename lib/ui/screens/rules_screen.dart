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
                '2–8 seats (you plus bots and/or hotseat humans). '
                'Everyone starts with 100¢ (virtual chips). '
                'Each round, every seated player antes 10¢ into the pot.',
          ),
          _RuleCard(
            emoji: '🎲',
            title: 'Your turn',
            body:
                'Roll 3 dice, up to 3 times. Tap dice to keep them between rolls. '
                'A non-scoring roll is still your turn — keep rolling. '
                'Bank only when you have a scoring hand. '
                'No score after 3 rolls: bust 2¢ into the pot.',
          ),
          _RuleCard(
            emoji: '👑',
            title: 'Triple ones — first roll',
            body:
                'Three 1s on your FIRST roll wins the ENTIRE pot. '
                'New round starts with a fresh ante. Confetti time.',
          ),
          _RuleCard(
            emoji: '💰',
            title: 'Other scores',
            body:
                'Triple ones on roll 2/3: each other player pays you 10¢.\n'
                'Other three-of-a-kind: each other pays the face value in ¢.\n'
                'Straight (123/234/345/456): each other pays 5¢.\n'
                'No score after 3 rolls: put 2¢ in the pot.',
          ),
          _RuleCard(
            emoji: '🏠',
            title: 'House stake',
            body:
                'Soft bankrupt: once per match the House tops you up 50¢. '
                'After that, running dry can knock you out. Endless rounds until you End match.',
          ),
          _RuleCard(
            emoji: '🤖',
            title: 'Bots',
            body:
                'Choose 0–4 bots and 0–4 other local players before the match '
                '(at least one opponent; max 8 seats including you). '
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
