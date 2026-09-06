import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/ad_ids.dart';
import '../../ads/ads_service.dart';
import '../../cosmetics/dice_skin.dart';
import '../../cosmetics/skins_service.dart';
import '../theme/marge_theme.dart';
import '../widgets/die_widget.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cos = ref.watch(cosmeticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dice shop'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: MargeColors.gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MargeColors.gold),
                ),
                child: Text(
                  'Wallet ${cos.walletCents}¢',
                  style: const TextStyle(
                    color: MargeColors.gold,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [MargeColors.velvet, Color(0xFF2D1B69)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const _WatchAdForChipsCard(),
            const SizedBox(height: 12),
            for (var i = 0; i < DiceSkinCatalog.all.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _SkinTile(def: DiceSkinCatalog.all[i], cos: cos),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkinTile extends ConsumerWidget {
  const _SkinTile({required this.def, required this.cos});

  final DiceSkinDef def;
  final CosmeticsState cos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = cos.isOwned(def.id);
    final equipped = cos.equipped == def.id;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                DieWidget(
                  value: 5,
                  kept: false,
                  enabled: false,
                  size: 56,
                  theme: def.theme,
                ),
                const SizedBox(height: 6),
                DieWidget(
                  value: 6,
                  kept: true,
                  enabled: false,
                  size: 40,
                  theme: def.theme,
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          def.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      if (equipped)
                        const Text(
                          'EQUIPPED',
                          style: TextStyle(
                            color: MargeColors.gold,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    def.blurb,
                    style: TextStyle(
                      color: MargeColors.cream.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    owned
                        ? (def.isFree ? 'Free · Owned' : 'Owned')
                        : (def.isFree
                            ? 'Free'
                            : '${def.priceCents}¢ · ${def.unlockHint}'),
                    style: TextStyle(
                      color: owned
                          ? MargeColors.sky
                          : MargeColors.cream.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!owned &&
                      def.unlockRule != SkinUnlockRule.shop &&
                      def.unlockRule != SkinUnlockRule.free) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Win: ${def.unlockHint}',
                      style: const TextStyle(
                        color: MargeColors.coral,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (owned && !equipped)
                        FilledButton(
                          onPressed: () async {
                            final r = await ref
                                .read(cosmeticsProvider.notifier)
                                .equip(def.id);
                            if (context.mounted && r.message != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(r.message!)),
                              );
                            }
                          },
                          child: const Text('Equip'),
                        ),
                      if (owned && equipped)
                        OutlinedButton(
                          onPressed: null,
                          child: const Text('Equipped'),
                        ),
                      if (!owned && !def.isFree)
                        ElevatedButton(
                          onPressed: cos.walletCents >= def.priceCents
                              ? () async {
                                  final r = await ref
                                      .read(cosmeticsProvider.notifier)
                                      .buy(def.id);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          r.message ??
                                              (r.ok ? 'Bought!' : 'Failed'),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              : null,
                          child: Text('Buy ${def.priceCents}¢'),
                        ),
                    ],
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

class _WatchAdForChipsCard extends ConsumerStatefulWidget {
  const _WatchAdForChipsCard();

  @override
  ConsumerState<_WatchAdForChipsCard> createState() =>
      _WatchAdForChipsCardState();
}

class _WatchAdForChipsCardState extends ConsumerState<_WatchAdForChipsCard> {
  bool _busy = false;

  Future<void> _watch() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ads = ref.read(adsServiceProvider);
    final earned = await ads.showRewardedForVirtualChips(
      onReward: (amount) async {
        await ref.read(cosmeticsProvider.notifier).grantVirtualChips(
              amount,
              reason: '+$amount¢ virtual chips from ad!',
            );
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final msg = earned
        ? 'Granted ${AdIds.rewardedChipGrant}¢ virtual chips!'
        : 'Ad not available right now — try again later.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Free virtual chips',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 4),
            Text(
              'Watch a short ad to earn ${AdIds.rewardedChipGrant}¢ virtual chips '
              'for the dice shop. Not real money.',
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _watch,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ondemand_video_rounded),
              label: Text(
                _busy
                    ? 'Loading…'
                    : 'Watch ad for +${AdIds.rewardedChipGrant}¢',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
