import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import '../../services/coin_ledger.dart';
import '../../services/friends_service.dart';
import '../../services/settings_service.dart';
import '../match_provider.dart';
import '../theme/marge_theme.dart';
import 'match_screen.dart';
import 'rules_screen.dart';

/// Seat / bots flow after Play — dense controls live here, not on home.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  int _bots = 3;
  int _otherHumans = 0;
  int _online = 0;

  int _seatedFriends(FriendsState friends) => friends.seatedNames.length;

  int get _playableOpponents => _bots + _otherHumans;
  int _totalSeats(int friends) => 1 + _otherHumans + friends + _online + _bots;
  bool _canStart(int friends) =>
      _playableOpponents >= 1 &&
      _playableOpponents <= MatchConfig.maxOpponents &&
      _totalSeats(friends) <= MatchConfig.maxOpponents + 1;

  void _applyPlan(int bots, int others, int online, int friends) {
    final plan = MatchConfig.clampLobbyCounts(bots, others, online, friends);
    _bots = plan.bots;
    _otherHumans = plan.others;
    _online = plan.online;
  }

  void _setBots(int value) {
    final friends = _seatedFriends(ref.read(friendsProvider));
    setState(() => _applyPlan(value, _otherHumans, _online, friends));
  }

  void _setOthers(int value) {
    final friends = _seatedFriends(ref.read(friendsProvider));
    setState(() => _applyPlan(_bots, value, _online, friends));
  }

  void _setOnline(int value) {
    final friends = _seatedFriends(ref.read(friendsProvider));
    setState(() => _applyPlan(_bots, _otherHumans, value, friends));
  }

  String get _seatSummary {
    final parts = <String>['You'];
    if (_otherHumans > 0) {
      parts.add('$_otherHumans human${_otherHumans == 1 ? '' : 's'}');
    }
    final seatedFriends = _seatedFriends(ref.read(friendsProvider));
    if (seatedFriends > 0) {
      parts.add('$seatedFriends friend${seatedFriends == 1 ? '' : 's'}');
    }
    if (_online > 0) {
      parts.add('$_online online (waiting)');
    }
    if (_bots > 0) {
      parts.add('$_bots bot${_bots == 1 ? '' : 's'}');
    }
    return parts.join(' + ');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final friends = ref.watch(friendsProvider);
    final ledger = ref.watch(coinLedgerProvider);
    final seated = friends.seatedNames;
    final friendCount = seated.length;
    final canStart = _canStart(friendCount);
    final seats = PlayerCoinLedger.lobbySeats(
      localName: settings.playerName,
      otherHumans: _otherHumans,
      online: _online,
      bots: _bots,
      friendNames: seated,
      ledger: ledger,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set the table'),
        backgroundColor: MargeColors.velvet,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [MargeColors.velvet, Color(0xFF243528), MargeColors.felt],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                'Hello, ${settings.playerName}! You are Player 1.',
                style: TextStyle(
                  color: MargeColors.cream.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _CountStepper(
                        label: 'Other players',
                        subtitle: 'Local hotseat humans · seated first',
                        value: _otherHumans,
                        onDecrement: _otherHumans > 0
                            ? () => _setOthers(_otherHumans - 1)
                            : null,
                        onIncrement: MatchConfig.canIncrementOthers(
                              _bots,
                              _otherHumans,
                              _online,
                              friendCount,
                            )
                            ? () => _setOthers(_otherHumans + 1)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _CountStepper(
                        label: 'Online players',
                        subtitle:
                            'Reserved before bots · waiting if no one joins',
                        value: _online,
                        onDecrement: _online > 0
                            ? () => _setOnline(_online - 1)
                            : null,
                        onIncrement: MatchConfig.canIncrementOnline(
                              _bots,
                              _otherHumans,
                              _online,
                              friendCount,
                            )
                            ? () => _setOnline(_online + 1)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _CountStepper(
                        label: 'Bots',
                        subtitle: 'Fill leftover seats only',
                        value: _bots,
                        onDecrement:
                            _bots > 0 ? () => _setBots(_bots - 1) : null,
                        onIncrement: MatchConfig.canIncrementBots(
                              _bots,
                              _otherHumans,
                              _online,
                              friendCount,
                            )
                            ? () => _setBots(_bots + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: MargeColors.velvet.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: MargeColors.woodEdge.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seats: ${_totalSeats(friendCount)} / 8',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _seatSummary,
                      style: TextStyle(
                        color: MargeColors.cream.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                    if (_online > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'No live match yet. Those seats show as '
                        '"Waiting for player" and are not filled by bots.',
                        style: TextStyle(
                          color: MargeColors.gold.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Table gems preview',
                      style: TextStyle(
                        color: MargeColors.gold.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final seat in seats)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          seat.line,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    if (!canStart) ...[
                      const SizedBox(height: 8),
                      Text(
                        _online > 0 || friendCount > 0
                            ? 'Waiting seats do not play. Add a bot or local player to start.'
                            : 'Add at least 1 bot or other player.',
                        style: const TextStyle(
                          color: MargeColors.coral,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: canStart
                    ? () {
                        ref.read(matchProvider.notifier).start(
                              botCount: _bots,
                              otherHumanCount: _otherHumans,
                              onlinePlayerCount: _online,
                              friendNames: seated,
                              playerName: settings.playerName,
                            );
                        Navigator.of(context).pushReplacement(
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
              const SizedBox(height: 8),
              Text(
                'Virtual gems only — no real money.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MargeColors.cream.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
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
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
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
            disabledBackgroundColor: MargeColors.velvet.withValues(alpha: 0.25),
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
            disabledBackgroundColor: MargeColors.velvet.withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }
}
