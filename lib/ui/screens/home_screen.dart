import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/settings_service.dart';
import '../match_provider.dart';
import '../theme/marge_theme.dart';
import 'match_screen.dart';
import 'rules_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _humans = 1;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              MargeColors.velvet,
              Color(0xFF2D1B69),
              MargeColors.felt,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    tooltip: 'Settings',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings_rounded),
                    color: MargeColors.cream,
                  ),
                ),
                const Spacer(),
                Text(
                  '🎲 MARGE',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: MargeColors.gold,
                        letterSpacing: 4,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Dice Game',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: MargeColors.cream,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Chase the pot. Bank the trips.\nHit triple ones on the first roll.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: MargeColors.cream.withValues(alpha: 0.8),
                      ),
                ),
                const Spacer(),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Seats: $_humans human${_humans == 1 ? '' : 's'}'
                          ' + ${4 - _humans} bot${4 - _humans == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Slider(
                          value: _humans.toDouble(),
                          min: 1,
                          max: 4,
                          divisions: 3,
                          label: '$_humans',
                          activeColor: MargeColors.gold,
                          onChanged: (v) =>
                              setState(() => _humans = v.round()),
                        ),
                        Text(
                          'Hello, ${settings.playerName}! Hotseat supported.',
                          style: TextStyle(
                            color: MargeColors.cream.withValues(alpha: 0.75),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.read(matchProvider.notifier).start(
                          humanCount: _humans,
                          playerName: settings.playerName,
                        );
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MatchScreen()),
                    );
                    if (!settings.seenRules) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RulesScreen(fromOnboarding: true),
                        ),
                      );
                    }
                  },
                  child: const Text('PLAY'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MargeColors.cream,
                    side: const BorderSide(color: MargeColors.gold),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RulesScreen()),
                    );
                  },
                  child: const Text('How to play'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
