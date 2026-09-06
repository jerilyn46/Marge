import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
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
  /// Default: 3 bots, 0 other humans (classic solo feel).
  int _bots = 3;
  int _otherHumans = 0;

  int get _opponents => _bots + _otherHumans;
  int get _totalSeats => 1 + _opponents;
  bool get _canStart => _opponents >= 1 && _opponents <= MatchConfig.maxOpponents;

  void _setBots(int value) {
    setState(() => _bots = MatchConfig.clampBots(value, _otherHumans));
  }

  void _setOthers(int value) {
    setState(() => _otherHumans = MatchConfig.clampOthers(_bots, value));
  }

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
                const Spacer(flex: 2),
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
                const Spacer(flex: 2),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Match setup',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hello, ${settings.playerName}! You are Player 1.',
                          style: TextStyle(
                            color: MargeColors.cream.withValues(alpha: 0.75),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _CountStepper(
                          label: 'Bots',
                          subtitle: 'Auto-play opponents',
                          value: _bots,
                          onDecrement: _bots > 0
                              ? () => _setBots(_bots - 1)
                              : null,
                          onIncrement:
                              MatchConfig.canIncrementBots(_bots, _otherHumans)
                                  ? () => _setBots(_bots + 1)
                                  : null,
                        ),
                        const SizedBox(height: 12),
                        _CountStepper(
                          label: 'Other players',
                          subtitle: 'Local hotseat humans',
                          value: _otherHumans,
                          onDecrement: _otherHumans > 0
                              ? () => _setOthers(_otherHumans - 1)
                              : null,
                          onIncrement: MatchConfig.canIncrementOthers(
                                  _bots, _otherHumans)
                              ? () => _setOthers(_otherHumans + 1)
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: MargeColors.velvet.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Seats: $_totalSeats / 8',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'You'
                                '${_otherHumans > 0 ? ' + $_otherHumans human${_otherHumans == 1 ? '' : 's'}' : ''}'
                                '${_bots > 0 ? ' + $_bots bot${_bots == 1 ? '' : 's'}' : ''}',
                                style: TextStyle(
                                  color:
                                      MargeColors.cream.withValues(alpha: 0.8),
                                  fontSize: 13,
                                ),
                              ),
                              if (!_canStart) ...[
                                const SizedBox(height: 6),
                                const Text(
                                  'Add at least 1 bot or other player.',
                                  style: TextStyle(
                                    color: MargeColors.coral,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _canStart
                      ? () {
                          ref.read(matchProvider.notifier).start(
                                botCount: _bots,
                                otherHumanCount: _otherHumans,
                                playerName: settings.playerName,
                              );
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MatchScreen(),
                            ),
                          );
                          if (!settings.seenRules) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const RulesScreen(fromOnboarding: true),
                              ),
                            );
                          }
                        }
                      : null,
                  child: const Text('START MATCH'),
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

class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String label;
  final String subtitle;
  final int value;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: MargeColors.cream.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: onDecrement,
          icon: const Icon(Icons.remove_rounded),
          style: IconButton.styleFrom(
            backgroundColor: MargeColors.velvet.withValues(alpha: 0.55),
            foregroundColor: MargeColors.cream,
            disabledBackgroundColor:
                MargeColors.velvet.withValues(alpha: 0.25),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: MargeColors.gold,
            ),
          ),
        ),
        IconButton.filledTonal(
          onPressed: onIncrement,
          icon: const Icon(Icons.add_rounded),
          style: IconButton.styleFrom(
            backgroundColor: MargeColors.velvet.withValues(alpha: 0.55),
            foregroundColor: MargeColors.cream,
            disabledBackgroundColor:
                MargeColors.velvet.withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }
}
