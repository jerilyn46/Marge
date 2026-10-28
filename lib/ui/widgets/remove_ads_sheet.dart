import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/gem_iap.dart';
import '../../services/remove_ads.dart';
import '../theme/marge_theme.dart';

/// Opens the "Play without ads" sheet (money-features-v1 §1).
///
/// Only from a user tap at a natural break (Shop, Settings, lobby banner
/// link, match-end card) — never mid-roll, never automatically.
Future<void> showRemoveAdsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const RemoveAdsSheet(),
  );
}

/// Price from Play, or null when the product has not loaded.
String? removeAdsPrice(GemIapState iap) =>
    iap.products[RemoveAds.productId]?.price;

class RemoveAdsSheet extends ConsumerStatefulWidget {
  const RemoveAdsSheet({super.key});

  @override
  ConsumerState<RemoveAdsSheet> createState() => _RemoveAdsSheetState();
}

class _RemoveAdsSheetState extends ConsumerState<RemoveAdsSheet> {
  void _toast(String text) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _buy() async {
    final ok = await ref.read(gemIapProvider.notifier).buyRemoveAds();
    if (!mounted || ok) return;
    // Error: toast, sheet stays open.
    _toast(ref.read(gemIapProvider).lastError ?? 'Purchase unavailable.');
  }

  Future<void> _restore() async {
    final ok = await ref.read(gemIapProvider.notifier).restore();
    if (!mounted) return;
    if (!ok) {
      _toast(ref.read(gemIapProvider).lastError ?? 'Restore failed.');
    } else if (!ref.read(removeAdsOwnedProvider)) {
      _toast('Checking Google Play for your purchase…');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(removeAdsOwnedProvider, (prev, owned) {
      if (owned && prev != true) {
        _toast('Ads removed. Thanks for supporting Marge!');
        Navigator.of(context).maybePop();
      }
    });
    ref.listen<String?>(gemIapProvider.select((s) => s.lastError), (_, err) {
      if (err != null) _toast(err);
    });

    final iap = ref.watch(gemIapProvider);
    final owned = ref.watch(removeAdsOwnedProvider);
    final price = removeAdsPrice(iap);
    final pending = iap.purchasingId == RemoveAds.productId;
    final canBuy = !owned && price != null && iap.purchasingId == null;
    final muted = MargeColors.cream.withValues(alpha: 0.75);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          key: const ValueKey('remove-ads-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.block_rounded, size: 40, color: MargeColors.gold),
            const SizedBox(height: 8),
            Text(
              'Play without ads',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: MargeColors.gold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'No lobby banner. No break after a match.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Bonus-gem videos stay optional — only if you tap.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            if (owned)
              const Text(
                'Ads removed — thank you!',
                key: ValueKey('remove-ads-owned'),
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
              )
            else
              FilledButton(
                key: const ValueKey('remove-ads-cta'),
                onPressed: canBuy ? _buy : null,
                child: pending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        price == null
                            ? (iap.loading
                                  ? 'Loading price…'
                                  : 'Not available right now')
                            : 'Remove ads — $price',
                      ),
              ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('remove-ads-not-now'),
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(owned ? 'Close' : 'Not now'),
            ),
            if (!owned)
              TextButton(
                key: const ValueKey('remove-ads-restore'),
                onPressed: pending ? null : _restore,
                child: const Text('Restore purchase'),
              ),
            const SizedBox(height: 6),
            Text(
              'One-time purchase. Payment handled by Google Play.\n'
              'Virtual gems only — no cash-out.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shop tile (comp `01-remove-ads-tile.png`). Hidden once owned or when
/// this build serves no ads.
class RemoveAdsTile extends ConsumerWidget {
  const RemoveAdsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!RemoveAds.offersEnabled || ref.watch(removeAdsOwnedProvider)) {
      return const SizedBox.shrink();
    }
    final iap = ref.watch(gemIapProvider);
    final price = removeAdsPrice(iap);
    final pending = iap.purchasingId == RemoveAds.productId;
    return Card(
      key: const ValueKey('remove-ads-tile'),
      child: ListTile(
        leading: const Icon(Icons.block_rounded, color: MargeColors.gold),
        title: const Text(
          'Remove Ads',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('Banner + match-end ad off'),
        trailing: pending
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                price == null ? '' : '$price · once',
                style: const TextStyle(
                  color: MargeColors.gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
        onTap: () => showRemoveAdsSheet(context),
      ),
    );
  }
}

/// Soft, dismissible match-end offer. Shown on the results screen only
/// (never mid-roll), at most once per app session, never once owned.
class RemoveAdsMatchEndOffer extends ConsumerStatefulWidget {
  const RemoveAdsMatchEndOffer({super.key});

  /// Once-per-session guard (no nagging, SPEC §1).
  static bool shownThisSession = false;

  @override
  ConsumerState<RemoveAdsMatchEndOffer> createState() =>
      _RemoveAdsMatchEndOfferState();
}

class _RemoveAdsMatchEndOfferState
    extends ConsumerState<RemoveAdsMatchEndOffer> {
  late final bool _eligible;
  var _dismissed = false;

  @override
  void initState() {
    super.initState();
    _eligible =
        RemoveAds.offersEnabled &&
        !RemoveAds.owned.value &&
        !RemoveAdsMatchEndOffer.shownThisSession;
    if (_eligible) RemoveAdsMatchEndOffer.shownThisSession = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_eligible || _dismissed || ref.watch(removeAdsOwnedProvider)) {
      return const SizedBox.shrink();
    }
    return Card(
      key: const ValueKey('remove-ads-match-end'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        child: Row(
          children: [
            const Icon(Icons.block_rounded, color: MargeColors.gold, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Skip the break after matches?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            TextButton(
              key: const ValueKey('remove-ads-match-end-open'),
              onPressed: () => showRemoveAdsSheet(context),
              child: const Text('Remove ads'),
            ),
            IconButton(
              key: const ValueKey('remove-ads-match-end-dismiss'),
              tooltip: 'Not now',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => setState(() => _dismissed = true),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small link under the lobby banner ("banner link" entry, SPEC §1).
class RemoveAdsBannerLink extends ConsumerWidget {
  const RemoveAdsBannerLink({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!RemoveAds.offersEnabled || ref.watch(removeAdsOwnedProvider)) {
      return const SizedBox.shrink();
    }
    return TextButton(
      key: const ValueKey('remove-ads-banner-link'),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      onPressed: () => showRemoveAdsSheet(context),
      child: Text(
        'Remove ads',
        style: TextStyle(
          color: MargeColors.cream.withValues(alpha: 0.7),
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Settings / More row. Shows ownership once bought; opens the sheet
/// (with "Restore purchase") otherwise.
class RemoveAdsSettingsRow extends ConsumerWidget {
  const RemoveAdsSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!RemoveAds.offersEnabled) return const SizedBox.shrink();
    final owned = ref.watch(removeAdsOwnedProvider);
    return ListTile(
      key: const ValueKey('remove-ads-settings'),
      leading: Icon(
        owned ? Icons.check_circle_rounded : Icons.block_rounded,
        color: MargeColors.gold,
      ),
      title: Text(owned ? 'Ads removed' : 'Remove ads'),
      subtitle: Text(
        owned
            ? 'No lobby banner or match-end ad. Bonus-gem videos stay optional.'
            : 'One-time purchase · restore on a new device',
      ),
      trailing: owned ? null : const Icon(Icons.chevron_right_rounded),
      onTap: owned ? null : () => showRemoveAdsSheet(context),
    );
  }
}
