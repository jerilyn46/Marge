import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/ad_ids.dart';
import '../../cosmetics/dice_skin.dart';
import '../../cosmetics/skins_service.dart';
import '../../engine/gem_label.dart';
import '../../services/coin_ledger.dart';
import '../theme/marge_theme.dart';
import '../widgets/daily_drip_card.dart';
import '../widgets/die_widget.dart';

/// Virtual gems + Designer Collection. Packs / rewarded stay Coming soon.
/// No Play Billing, no AdMob CTAs while ads are off.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cos = ref.watch(cosmeticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: MargeColors.gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MargeColors.gold),
                ),
                child: Text(
                  gemCount(cos.walletCents),
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
            colors: [MargeColors.velvet, Color(0xFF243528), MargeColors.felt],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'Play gems — not real money',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.85),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Virtual gems only — never real currency or payouts.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.65),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            const DailyDripCard(),
            const SizedBox(height: 14),
            const _SectionTitle('Gem packs'),
            const SizedBox(height: 8),
            for (final gems in PlayerCoinLedger.previewPackGems) ...[
              _ComingSoonPackTile(gems: gems),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            const _ComingSoonRewardedCard(),
            const SizedBox(height: 18),
            const _SectionTitle('Designer Collection'),
            const SizedBox(height: 4),
            Text(
              'Dice cosmetics unlocked with virtual gems or play milestones.',
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 17,
        color: MargeColors.lamp,
      ),
    );
  }
}

class _ComingSoonPackTile extends StatelessWidget {
  const _ComingSoonPackTile({required this.gems});
  final int gems;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.diamond_outlined, color: MargeColors.gold),
        title: Text(
          gemCount(gems),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('Preview only — virtual gems (not real money)'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: MargeColors.velvet.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: MargeColors.woodEdge.withValues(alpha: 0.5),
            ),
          ),
          child: const Text(
            'Coming soon',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: MargeColors.cream,
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoonRewardedCard extends StatelessWidget {
  const _ComingSoonRewardedCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Watch for gems',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 4),
            Text(
              'A short video for +${AdIds.rewardedChipGrant} gems — Coming soon. '
              'No ad plays while AdMob stays off.',
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.ondemand_video_rounded),
              label: const Text('Coming soon'),
            ),
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
                              : '${gemCount(def.priceCents)} · ${def.unlockHint}'),
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
                        const OutlinedButton(
                          onPressed: null,
                          child: Text('Equipped'),
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
                                              (r.ok ? 'Unlocked!' : 'Failed'),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              : null,
                          child: Text(
                            'Spend ${gemCount(def.priceCents)}',
                          ),
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
