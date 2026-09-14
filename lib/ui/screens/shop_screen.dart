import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/ad_ids.dart';
import '../../ads/ads_service.dart';
import '../../cosmetics/dice_skin.dart';
import '../../cosmetics/skins_service.dart';
import '../../engine/gem_label.dart';
import '../../services/coin_ledger.dart';
import '../../services/gem_iap.dart';
import '../../services/settings_service.dart';
import '../theme/marge_theme.dart';
import '../widgets/daily_drip_card.dart';
import '../widgets/die_widget.dart';

/// Virtual gems shop: daily drip, Play Billing packs, rewarded ads, skins.
///
/// Gems are virtual only — never real currency, never cash-out.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cos = ref.watch(cosmeticsProvider);
    final name = ref.watch(settingsProvider).playerName;
    final bank = ref.watch(coinLedgerProvider).availableHumanGems(name);

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
                  gemCount(bank),
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
              'Virtual gems only — never real currency, payouts, or cash-out.',
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
            const SizedBox(height: 4),
            Text(
              'Paid packs credit your gem bank. Separate from the free daily drip.',
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            for (final pack in GemPack.all) ...[
              _IapPackTile(pack: pack),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            const _RewardedGemsCard(),
            const SizedBox(height: 18),
            const _SectionTitle('Designer Collection'),
            const SizedBox(height: 4),
            Text(
              'Dice cosmetics unlocked with virtual gems or play milestones. '
              'Skin wallet: ${gemCount(cos.walletCents)}.',
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

class _IapPackTile extends ConsumerWidget {
  const _IapPackTile({required this.pack});
  final GemPack pack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iap = ref.watch(gemIapProvider);
    final details = iap.products[pack.productId];
    final busy = iap.purchasingId == pack.productId;
    final price = details?.price;
    final enabled = details != null && iap.purchasingId == null;

    return Card(
      child: ListTile(
        leading: const Icon(Icons.diamond_outlined, color: MargeColors.gold),
        title: Text(
          '${pack.title} · ${gemCount(pack.gems)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${pack.blurb} Virtual gems (not real money). No cash-out.',
        ),
        trailing: busy
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton(
                onPressed: enabled
                    ? () async {
                        final ok =
                            await ref.read(gemIapProvider.notifier).buy(pack);
                        if (!context.mounted) return;
                        final err = ref.read(gemIapProvider).lastError;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Purchase started for ${gemCount(pack.gems)}…'
                                  : (err ?? 'Purchase unavailable.'),
                            ),
                          ),
                        );
                      }
                    : null,
                child: Text(price ?? 'Unavailable'),
              ),
      ),
    );
  }
}

class _RewardedGemsCard extends ConsumerStatefulWidget {
  const _RewardedGemsCard();

  @override
  ConsumerState<_RewardedGemsCard> createState() => _RewardedGemsCardState();
}

class _RewardedGemsCardState extends ConsumerState<_RewardedGemsCard> {
  var _busy = false;

  Future<void> _watch() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ads = ref.read(adsServiceProvider);
      final name = ref.read(settingsProvider).playerName;
      final earned = await ads.showRewardedForVirtualChips(
        onReward: (amount) async {
          ref
              .read(coinLedgerProvider.notifier)
              .grantHumanPlayCoins(name, cents: amount);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            earned
                ? 'Earned ${gemCount(AdIds.rewardedChipGrant)} virtual gems. Not real money.'
                : kAdmobEnabled
                    ? 'Ad unavailable — try again later.'
                    : 'Ads are off in this build '
                        '(ADMOB_ENABLED / -PADMOB_ENABLED).',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adsOn = kAdmobEnabled;
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
              adsOn
                  ? 'A short video for +${AdIds.rewardedChipGrant} gems in your '
                      'gem bank. Virtual gems only — not real money.'
                  : 'Rewarded ads credit +${AdIds.rewardedChipGrant} gems when '
                      'AdMob is enabled for this build.',
              style: TextStyle(
                color: MargeColors.cream.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: (_busy || !adsOn) ? null : _watch,
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
                    : adsOn
                        ? 'Watch for +${AdIds.rewardedChipGrant}'
                        : 'Ads off in this build',
              ),
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
