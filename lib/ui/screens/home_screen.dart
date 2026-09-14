import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/gem_label.dart';
import '../../engine/match_controller.dart';
import '../../services/coin_ledger.dart';
import '../../services/friends_service.dart';
import '../../services/saved_games.dart';
import '../../services/settings_service.dart';
import '../../startup_log.dart';
import '../match_provider.dart';
import '../theme/marge_theme.dart';
import '../widgets/felt_hero_backdrop.dart';
import '../widgets/gem_bank_sheet.dart';
import '../widgets/get_more_gems_button.dart';
import '../widgets/reserved_banner_strip.dart';
import 'friends_screen.dart';
import 'match_screen.dart';
import 'more_screen.dart';
import 'setup_screen.dart';
import 'shop_screen.dart';

/// Inviting lobby — warm evening table. Dense setup lives after Play.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(StartupLog.mark('lobby-widget'));
    // Disk may have unfinished tables from leave/pause; refresh list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(savedGamesProvider.notifier).reload());
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final friends = ref.watch(friendsProvider);
    final ledger = ref.watch(coinLedgerProvider);
    final savedGames = ref.watch(savedGamesProvider);
    final gemBank = ledger.availableHumanGems(settings.playerName);
    final seated = friends.seatedNames;
    final ante = const MatchConfig().anteCents;
    final needsGems = gemBank < ante;

    return Scaffold(
      body: FeltHeroBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    _FriendsPeek(
                      seatedCount: seated.length,
                      totalCount: friends.friends.length,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FriendsScreen(),
                          ),
                        );
                      },
                    ),
                    const Spacer(),
                    _GemJewelTray(
                      gems: gemBank,
                      onTap: () => showGemBankSheet(context, ref),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const DieWidgetMini(value: 5),
                          const SizedBox(width: 12),
                          const DieWidgetMini(value: 3),
                          const SizedBox(width: 12),
                          const DieWidgetMini(value: 6),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Marge',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: MargeColors.lamp,
                              letterSpacing: 2,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'An evening table with friends',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: MargeColors.cream.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Chase the pot. Bank the trips.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: MargeColors.cream.withValues(alpha: 0.72),
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Virtual gems only — no real money.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: MargeColors.cream.withValues(alpha: 0.58),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 28),
                      _PlayPill(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SetupScreen(),
                            ),
                          );
                        },
                      ),
                      if (savedGames.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _ResumeSection(
                          games: savedGames,
                          onResume: (id) {
                            final ok =
                                ref.read(matchProvider.notifier).resume(id);
                            if (!ok || !context.mounted) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const MatchScreen(),
                              ),
                            );
                          },
                          onDrop: (id) =>
                              ref.read(matchProvider.notifier).dropSaved(id),
                        ),
                      ],
                      const SizedBox(height: 22),
                      _SecondaryRow(
                        onShop: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ShopScreen(),
                            ),
                          );
                        },
                        onMore: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MoreScreen(),
                            ),
                          );
                        },
                      ),
                      if (needsGems) ...[
                        const SizedBox(height: 14),
                        const GetMoreGemsButton(),
                      ],
                      const SizedBox(height: 18),
                      // Quiet reserved house-art strip — ads stay off; no AdMob.
                      const ReservedBannerStrip(),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DieWidgetMini extends StatelessWidget {
  const DieWidgetMini({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: MargeColors.cream,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MargeColors.woodEdge, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(painter: _MiniDiePainter(value)),
    );
  }
}

class _MiniDiePainter extends CustomPainter {
  _MiniDiePainter(this.value);

  final int value;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF2A2118);
    final r = size.shortestSide * 0.1;
    Offset p(double x, double y) => Offset(size.width * x, size.height * y);
    final map = <int, List<Offset>>{
      1: [p(0.5, 0.5)],
      2: [p(0.28, 0.28), p(0.72, 0.72)],
      3: [p(0.28, 0.28), p(0.5, 0.5), p(0.72, 0.72)],
      4: [p(0.28, 0.28), p(0.72, 0.28), p(0.28, 0.72), p(0.72, 0.72)],
      5: [
        p(0.28, 0.28),
        p(0.72, 0.28),
        p(0.5, 0.5),
        p(0.28, 0.72),
        p(0.72, 0.72),
      ],
      6: [
        p(0.28, 0.22),
        p(0.72, 0.22),
        p(0.28, 0.5),
        p(0.72, 0.5),
        p(0.28, 0.78),
        p(0.72, 0.78),
      ],
    };
    for (final o in map[value] ?? const <Offset>[]) {
      canvas.drawCircle(o, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniDiePainter oldDelegate) =>
      oldDelegate.value != value;
}

class _GemJewelTray extends StatelessWidget {
  const _GemJewelTray({required this.gems, required this.onTap});

  final int gems;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: MargeColors.velvet.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: MargeColors.gold.withValues(alpha: 0.65),
            ),
            boxShadow: [
              BoxShadow(
                color: MargeColors.lamp.withValues(alpha: 0.12),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GemChipAccent(size: 16),
              const SizedBox(width: 8),
              Text(
                gemCount(gems),
                style: const TextStyle(
                  color: MargeColors.gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendsPeek extends StatelessWidget {
  const _FriendsPeek({
    required this.seatedCount,
    required this.totalCount,
    required this.onTap,
  });

  final int seatedCount;
  final int totalCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = totalCount == 0
        ? 'Friends'
        : seatedCount > 0
            ? 'Friends · $seatedCount seated'
            : 'Friends · $totalCount';
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.people_alt_rounded, color: MargeColors.cream),
      label: Text(
        label,
        style: const TextStyle(
          color: MargeColors.cream,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PlayPill extends StatelessWidget {
  const _PlayPill({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: MargeColors.gold,
          foregroundColor: MargeColors.velvet,
          elevation: 6,
          shadowColor: MargeColors.lamp.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            letterSpacing: 1.2,
          ),
        ),
        child: const Text('Play'),
      ),
    );
  }
}

class _ResumeSection extends StatelessWidget {
  const _ResumeSection({
    required this.games,
    required this.onResume,
    required this.onDrop,
  });

  final List<SavedGame> games;
  final ValueChanged<String> onResume;
  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) {
    final shown = games.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Continue',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: MargeColors.lamp,
              ),
        ),
        const SizedBox(height: 8),
        for (final game in shown) ...[
          _ResumeCard(
            game: game,
            onResume: () => onResume(game.id),
            onDrop: () => onDrop(game.id),
          ),
          const SizedBox(height: 8),
        ],
        if (games.length > 3)
          Text(
            '+${games.length - 3} more unfinished',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MargeColors.cream.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),
      ],
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.game,
    required this.onResume,
    required this.onDrop,
  });

  final SavedGame game;
  final VoidCallback onResume;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MargeColors.felt.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onResume,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: MargeColors.woodEdge.withValues(alpha: 0.55),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              const GemChipAccent(size: 22, color: MargeColors.coral),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.resumeLine,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      game.seatSummary,
                      style: TextStyle(
                        color: MargeColors.cream.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onResume, child: const Text('Resume')),
              IconButton(
                tooltip: 'Drop game',
                onPressed: onDrop,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow({required this.onShop, required this.onMore});

  final VoidCallback onShop;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onShop,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Shop'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MargeColors.cream,
              side: BorderSide(
                color: MargeColors.woodEdge.withValues(alpha: 0.7),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onMore,
            icon: const Icon(Icons.more_horiz_rounded, size: 18),
            label: const Text('More'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MargeColors.cream,
              side: BorderSide(
                color: MargeColors.woodEdge.withValues(alpha: 0.7),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
