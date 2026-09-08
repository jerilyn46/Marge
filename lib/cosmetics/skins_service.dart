import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dice_skin.dart';

/// Result of buy / unlock / equip mutations for UI feedback.
class CosmeticsActionResult {
  const CosmeticsActionResult({
    required this.ok,
    this.message,
    this.unlockedSkin,
  });

  final bool ok;
  final String? message;
  final DiceSkinId? unlockedSkin;

  static const CosmeticsActionResult alreadyOwned = CosmeticsActionResult(
    ok: false,
    message: 'Already owned',
  );
}

/// Persistent cosmetics + meta wallet, plus per-match achievement counters.
class CosmeticsState {
  const CosmeticsState({
    this.walletCents = DiceSkinCatalog.startingWalletCents,
    this.owned = const {DiceSkinId.classic},
    this.equipped = DiceSkinId.classic,
    this.matchHandWins = 0,
    this.matchBusts = 0,
    this.pendingToast,
    this.loaded = false,
  });

  final int walletCents;
  final Set<DiceSkinId> owned;
  final DiceSkinId equipped;
  final int matchHandWins;
  final int matchBusts;
  final String? pendingToast;
  final bool loaded;

  DiceSkinTheme get equippedTheme => DiceSkinCatalog.byId(equipped).theme;

  bool isOwned(DiceSkinId id) => owned.contains(id);

  CosmeticsState copyWith({
    int? walletCents,
    Set<DiceSkinId>? owned,
    DiceSkinId? equipped,
    int? matchHandWins,
    int? matchBusts,
    String? pendingToast,
    bool clearToast = false,
    bool? loaded,
  }) => CosmeticsState(
    walletCents: walletCents ?? this.walletCents,
    owned: owned ?? this.owned,
    equipped: equipped ?? this.equipped,
    matchHandWins: matchHandWins ?? this.matchHandWins,
    matchBusts: matchBusts ?? this.matchBusts,
    pendingToast: clearToast ? null : (pendingToast ?? this.pendingToast),
    loaded: loaded ?? this.loaded,
  );
}

/// Pure inventory helpers (unit-testable without prefs).
class CosmeticsLogic {
  CosmeticsLogic._();

  static (CosmeticsState, CosmeticsActionResult) buy(
    CosmeticsState state,
    DiceSkinId id,
  ) {
    final def = DiceSkinCatalog.byId(id);
    if (state.isOwned(id)) {
      return (state, CosmeticsActionResult.alreadyOwned);
    }
    if (def.isFree) {
      final next = state.copyWith(
        owned: {...state.owned, id},
        pendingToast: 'Unlocked ${def.name}!',
      );
      return (
        next,
        CosmeticsActionResult(
          ok: true,
          message: next.pendingToast,
          unlockedSkin: id,
        ),
      );
    }
    if (state.walletCents < def.priceCents) {
      return (
        state,
        CosmeticsActionResult(
          ok: false,
          message: 'Need ${def.priceCents}¢ (you have ${state.walletCents}¢)',
        ),
      );
    }
    final next = state.copyWith(
      walletCents: state.walletCents - def.priceCents,
      owned: {...state.owned, id},
      pendingToast: 'Bought ${def.name}!',
    );
    return (
      next,
      CosmeticsActionResult(
        ok: true,
        message: next.pendingToast,
        unlockedSkin: id,
      ),
    );
  }

  static (CosmeticsState, CosmeticsActionResult) equip(
    CosmeticsState state,
    DiceSkinId id,
  ) {
    if (!state.isOwned(id)) {
      return (
        state,
        const CosmeticsActionResult(ok: false, message: 'Not owned'),
      );
    }
    final def = DiceSkinCatalog.byId(id);
    final next = state.copyWith(equipped: id);
    return (
      next,
      CosmeticsActionResult(ok: true, message: 'Equipped ${def.name}'),
    );
  }

  /// Grant a skin (achievement). No-op if already owned.
  static (CosmeticsState, CosmeticsActionResult) unlock(
    CosmeticsState state,
    DiceSkinId id, {
    String? reason,
  }) {
    if (state.isOwned(id)) {
      return (state, CosmeticsActionResult.alreadyOwned);
    }
    final def = DiceSkinCatalog.byId(id);
    final toast = reason ?? 'Unlocked ${def.name}!';
    final next = state.copyWith(
      owned: {...state.owned, id},
      pendingToast: toast,
    );
    return (
      next,
      CosmeticsActionResult(ok: true, message: toast, unlockedSkin: id),
    );
  }

  static CosmeticsState creditWallet(CosmeticsState state, int amount) {
    if (amount <= 0) return state;
    return state.copyWith(walletCents: state.walletCents + amount);
  }

  /// Local player swept the pot: wallet bonus + Gold unlock.
  static (CosmeticsState, List<String>) onPotWin(CosmeticsState state) {
    var next = creditWallet(state, DiceSkinCatalog.potWinWalletBonus);
    final toasts = <String>[
      '+${DiceSkinCatalog.potWinWalletBonus}¢ wallet bonus!',
    ];
    final (afterUnlock, result) = unlock(
      next,
      DiceSkinId.gold,
      reason: '🏆 Pot win! Unlocked Gold dice!',
    );
    if (result.ok) {
      next = afterUnlock;
      toasts.add(result.message!);
    } else {
      next = afterUnlock;
    }
    return (next.copyWith(pendingToast: toasts.join('\n')), toasts);
  }

  /// Local player banked a scoring hand (not pot sweep).
  static (CosmeticsState, List<String>) onHandWin(CosmeticsState state) {
    final wins = state.matchHandWins + 1;
    var next = state.copyWith(matchHandWins: wins);
    final toasts = <String>[];
    if (wins >= 3) {
      final (after, result) = unlock(
        next,
        DiceSkinId.neon,
        reason: '⚡ 3 hands banked! Unlocked Neon dice!',
      );
      next = after;
      if (result.ok) toasts.add(result.message!);
    }
    return (
      next.copyWith(
        pendingToast: toasts.isEmpty ? next.pendingToast : toasts.join('\n'),
      ),
      toasts,
    );
  }

  /// Local player busted after 3 rolls.
  static (CosmeticsState, List<String>) onBust(CosmeticsState state) {
    final busts = state.matchBusts + 1;
    var next = state.copyWith(matchBusts: busts);
    final toasts = <String>[];
    if (busts >= 3) {
      final (after, result) = unlock(
        next,
        DiceSkinId.luckyBones,
        reason: '💀 3 busts! Unlocked Lucky Bones!',
      );
      next = after;
      if (result.ok) toasts.add(result.message!);
    }
    return (
      next.copyWith(
        pendingToast: toasts.isEmpty ? next.pendingToast : toasts.join('\n'),
      ),
      toasts,
    );
  }

  static CosmeticsState resetMatchProgress(CosmeticsState state) =>
      state.copyWith(matchHandWins: 0, matchBusts: 0);
}

class CosmeticsNotifier extends Notifier<CosmeticsState> {
  static const _kWallet = 'cosmetics_wallet_cents';
  static const _kOwned = 'cosmetics_owned';
  static const _kEquipped = 'cosmetics_equipped';

  SharedPreferences? _prefs;

  @override
  CosmeticsState build() {
    // Defaults first — prefs must not throw before the lobby frame.
    Future.microtask(() async {
      try {
        await _load();
      } catch (e, st) {
        debugPrint(
          'CosmeticsNotifier: prefs load failed (using defaults): $e\n$st',
        );
      }
    });
    return const CosmeticsState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    final wallet =
        prefs.getInt(_kWallet) ?? DiceSkinCatalog.startingWalletCents;
    final ownedRaw = prefs.getStringList(_kOwned) ?? const ['classic'];
    final owned = <DiceSkinId>{DiceSkinId.classic};
    for (final raw in ownedRaw) {
      final def = DiceSkinCatalog.tryParse(raw);
      if (def != null) owned.add(def.id);
    }
    final eqRaw = prefs.getString(_kEquipped) ?? DiceSkinId.classic.name;
    final eq = DiceSkinCatalog.tryParse(eqRaw)?.id ?? DiceSkinId.classic;
    final equipped = owned.contains(eq) ? eq : DiceSkinId.classic;
    state = CosmeticsState(
      walletCents: wallet,
      owned: owned,
      equipped: equipped,
      loaded: true,
    );
  }

  Future<void> _persist() async {
    final p = _prefs;
    if (p == null) return;
    await p.setInt(_kWallet, state.walletCents);
    await p.setStringList(
      _kOwned,
      state.owned.map((e) => e.name).toList()..sort(),
    );
    await p.setString(_kEquipped, state.equipped.name);
  }

  void clearToast() {
    if (state.pendingToast != null) {
      state = state.copyWith(clearToast: true);
    }
  }

  Future<CosmeticsActionResult> buy(DiceSkinId id) async {
    final (next, result) = CosmeticsLogic.buy(state, id);
    if (result.ok) {
      state = next;
      await _persist();
    }
    return result;
  }

  Future<CosmeticsActionResult> equip(DiceSkinId id) async {
    final (next, result) = CosmeticsLogic.equip(state, id);
    if (result.ok) {
      state = next;
      await _persist();
    }
    return result;
  }

  void beginMatch() {
    state = CosmeticsLogic.resetMatchProgress(state);
  }

  Future<List<String>> recordLocalPotWin() async {
    final (next, toasts) = CosmeticsLogic.onPotWin(state);
    state = next;
    await _persist();
    return toasts;
  }

  Future<List<String>> recordLocalHandWin() async {
    final (next, toasts) = CosmeticsLogic.onHandWin(state);
    state = next;
    await _persist();
    return toasts;
  }

  Future<List<String>> recordLocalBust() async {
    final (next, toasts) = CosmeticsLogic.onBust(state);
    state = next;
    await _persist();
    return toasts;
  }

  /// Grant virtual chips (¢) from a rewarded ad or test hook.
  /// Virtual currency only — never real money.
  Future<int> grantVirtualChips(int amount, {String? reason}) async {
    if (amount <= 0) return state.walletCents;
    final next = CosmeticsLogic.creditWallet(state, amount);
    final toast = reason ?? '+$amount¢ virtual chips!';
    state = next.copyWith(pendingToast: toast);
    await _persist();
    return state.walletCents;
  }
}

final cosmeticsProvider = NotifierProvider<CosmeticsNotifier, CosmeticsState>(
  CosmeticsNotifier.new,
);
