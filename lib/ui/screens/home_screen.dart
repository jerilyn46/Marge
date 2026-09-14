import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import '../../services/coin_ledger.dart';
import '../../services/friends_service.dart';
import '../../services/settings_service.dart';
import '../../engine/gem_label.dart';
import '../match_provider.dart';
import '../../services/saved_games.dart';
import '../theme/marge_theme.dart';
import 'match_screen.dart';
import 'rules_screen.dart';
import 'settings_screen.dart';
import '../widgets/play_coin_pack_button.dart';
import 'shop_screen.dart';
import '../../ads/banner_ad_widget.dart';
import '../../cosmetics/skins_service.dart';
import '../../startup_log.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Default: 3 bots, 0 other humans, 0 online (classic solo feel).
  int _bots = 3;
  int _otherHumans = 0;
  int _online = 0;
  final _friendName = TextEditingController();
  String? _friendError;

  @override
  void dispose() {
    _friendName.dispose();
    super.dispose();
  }

  int _seatedFriends(FriendsState friends) => friends.seatedNames.length;

  @override
  void initState() {
    super.initState();
    unawaited(StartupLog.mark('lobby-widget'));
  }

  /// Playable opponents only. Waiting online chairs do not count.
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

  void _addGems(BuildContext context, WidgetRef ref, int gems) {
    final name = PlayerCoinLedger.localIdentity(
      ref.read(settingsProvider).playerName,
    );
    final next = ref
        .read(coinLedgerProvider.notifier)
        .grantHumanPlayCoins(name, cents: gems);
    if (!context.mounted || next == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added $gems gems. Gem bank has $next gems.')),
    );
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
    final wallet = ref.watch(cosmeticsProvider).walletCents;
    final friends = ref.watch(friendsProvider);
    final ledger = ref.watch(coinLedgerProvider);
    final savedGames = ref.watch(savedGamesProvider);
    final gemBank = ledger.availableHumanGems(settings.playerName);
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [MargeColors.velvet, Color(0xFF2D1B69), MargeColors.felt],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ShopScreen()),
                        );
                      },
                      icon: const Icon(
                        Icons.casino_rounded,
                        color: MargeColors.gold,
                      ),
                      label: Text(
                        'Dice · $wallet gems',
                        style: const TextStyle(
                          color: MargeColors.gold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
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
                  ],
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Match setup',
                          style: Theme.of(context).textTheme.titleMedium
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
                          label: 'Other players',
                          subtitle: 'Local hotseat humans · seated first',
                          value: _otherHumans,
                          onDecrement: _otherHumans > 0
                              ? () => _setOthers(_otherHumans - 1)
                              : null,
                          onIncrement:
                              MatchConfig.canIncrementOthers(
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
                          onIncrement:
                              MatchConfig.canIncrementOnline(
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
                          onDecrement: _bots > 0
                              ? () => _setBots(_bots - 1)
                              : null,
                          onIncrement:
                              MatchConfig.canIncrementBots(
                                _bots,
                                _otherHumans,
                                _online,
                                friendCount,
                              )
                              ? () => _setBots(_bots + 1)
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
                                  color: MargeColors.cream.withValues(
                                    alpha: 0.8,
                                  ),
                                  fontSize: 13,
                                ),
                              ),
                              if (_online > 0) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'No live match yet. Those seats show as '
                                  '"Waiting for player" and are not filled by bots.',
                                  style: TextStyle(
                                    color: MargeColors.gold.withValues(
                                      alpha: 0.9,
                                    ),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                'Gems',
                                style: TextStyle(
                                  color: MargeColors.gold.withValues(
                                    alpha: 0.9,
                                  ),
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
                              const SizedBox(height: 10),
                              Text(
                                'Gem bank ${gemCount(gemBank)} available',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              GemDenominationPicker(
                                onChosen: (gems) =>
                                    _addGems(context, ref, gems),
                              ),
                              if (!canStart) ...[
                                const SizedBox(height: 6),
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _FriendsCard(
                  controller: _friendName,
                  error: _friendError,
                  friends: friends,
                  onAdd: () async {
                    final err = await ref
                        .read(friendsProvider.notifier)
                        .add(_friendName.text);
                    if (!mounted) return;
                    setState(() => _friendError = err);
                    if (err == null) _friendName.clear();
                    final count = ref.read(friendsProvider).seatedNames.length;
                    setState(
                      () => _applyPlan(_bots, _otherHumans, _online, count),
                    );
                  },
                  onRemove: (name) async {
                    await ref.read(friendsProvider.notifier).remove(name);
                    if (!mounted) return;
                    final count = ref.read(friendsProvider).seatedNames.length;
                    setState(
                      () => _applyPlan(_bots, _otherHumans, _online, count),
                    );
                  },
                  onToggle: (name, seated) async {
                    await ref
                        .read(friendsProvider.notifier)
                        .setSeated(name, seated);
                    if (!mounted) return;
                    final count = ref.read(friendsProvider).seatedNames.length;
                    setState(
                      () => _applyPlan(_bots, _otherHumans, _online, count),
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (savedGames.isNotEmpty) ...[
                  _SavedGamesCard(
                    games: savedGames,
                    onResume: (id) {
                      final ok = ref.read(matchProvider.notifier).resume(id);
                      if (!ok || !context.mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MatchScreen()),
                      );
                    },
                    onDrop: (id) =>
                        ref.read(matchProvider.notifier).dropSaved(id),
                  ),
                  const SizedBox(height: 16),
                ],
                ElevatedButton(
                  onPressed: canStart
                      ? () {
                          ref
                              .read(matchProvider.notifier)
                              .start(
                                botCount: _bots,
                                otherHumanCount: _otherHumans,
                                onlinePlayerCount: _online,
                                friendNames: seated,
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
                      MaterialPageRoute(builder: (_) => const ShopScreen()),
                    );
                  },
                  child: const Text('Cosmetics / Dice shop'),
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
                const SizedBox(height: 12),
                const Center(child: LobbyBannerAd()),
                const SizedBox(height: 8),
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

class _FriendsCard extends StatelessWidget {
  const _FriendsCard({
    required this.controller,
    required this.error,
    required this.friends,
    required this.onAdd,
    required this.onRemove,
    required this.onToggle,
  });

  final TextEditingController controller;
  final String? error;
  final FriendsState friends;
  final VoidCallback onAdd;
  final void Function(String name) onRemove;
  final void Function(String name, bool seated) onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Friends',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'People you know. They sit before bots as named waiting chairs — no live connection.',
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Add a friend by name',
                      isDense: true,
                    ),
                    onSubmitted: (_) => onAdd(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: onAdd, child: const Text('Add')),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(
                error!,
                style: const TextStyle(
                  color: MargeColors.coral,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
            if (friends.friends.isEmpty) ...[
              const SizedBox(height: 10),
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
                  onChanged: (v) => onToggle(friend.name, v ?? false),
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
                  onPressed: () => onRemove(friend.name),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SavedGamesCard extends StatelessWidget {
  const _SavedGamesCard({
    required this.games,
    required this.onResume,
    required this.onDrop,
  });

  final List<SavedGame> games;
  final ValueChanged<String> onResume;
  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Unfinished games',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Resume one, or start a new game. Starting new does not delete these.',
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            ),
            for (final game in games)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  game.resumeLine,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(game.seatSummary),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => onResume(game.id),
                      child: const Text('Resume'),
                    ),
                    IconButton(
                      tooltip: 'Drop game',
                      onPressed: () => onDrop(game.id),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
