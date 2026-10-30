import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Named table-felt cosmetics. Paid felts spend from the **gem bank**
/// (coin ledger) — never the legacy dice-skin wallet. Virtual gems only.
enum TableFeltId { forest, midnight, crimson, royal }

@immutable
class TableFeltDef {
  const TableFeltDef({
    required this.id,
    required this.name,
    required this.priceGems,
    required this.color,
    required this.lightColor,
    required this.deepColor,
    this.placeholder = true,
  });

  final TableFeltId id;
  final String name;
  final int priceGems;
  final Color color;
  final Color lightColor;
  final Color deepColor;

  /// Solid-colour placeholder until Designer final art lands.
  final bool placeholder;

  bool get isFree => priceGems == 0;
}

class TableFeltCatalog {
  TableFeltCatalog._();

  static const defaultId = TableFeltId.forest;

  static const all = <TableFeltDef>[
    TableFeltDef(
      id: TableFeltId.forest,
      name: 'Forest Felt',
      priceGems: 0,
      color: Color(0xFF1F4D3A), // == MargeColors.felt
      lightColor: Color(0xFF2E6B50), // == MargeColors.feltLight
      deepColor: Color(0xFF143526),
      placeholder: false,
    ),
    TableFeltDef(
      id: TableFeltId.midnight,
      name: 'Midnight Blue Felt',
      priceGems: 100,
      color: Color(0xFF1E3A5F),
      lightColor: Color(0xFF2E5788),
      deepColor: Color(0xFF12243C),
    ),
    TableFeltDef(
      id: TableFeltId.crimson,
      name: 'Crimson Felt',
      priceGems: 250,
      color: Color(0xFF6B1E2A),
      lightColor: Color(0xFF8E2E3C),
      deepColor: Color(0xFF431219),
    ),
    TableFeltDef(
      id: TableFeltId.royal,
      name: 'Royal Purple Felt',
      priceGems: 500,
      color: Color(0xFF4B2A6B),
      lightColor: Color(0xFF6A3F94),
      deepColor: Color(0xFF2E1943),
    ),
  ];

  static TableFeltDef byId(TableFeltId id) => all.firstWhere((d) => d.id == id);

  static TableFeltDef? tryParse(String raw) {
    for (final d in all) {
      if (d.id.name == raw) return d;
    }
    return null;
  }
}

class TableFeltState {
  const TableFeltState({
    this.owned = const {TableFeltCatalog.defaultId},
    this.equipped = TableFeltCatalog.defaultId,
    this.loaded = false,
  });

  final Set<TableFeltId> owned;
  final TableFeltId equipped;
  final bool loaded;

  TableFeltDef get equippedDef => TableFeltCatalog.byId(equipped);
  bool isOwned(TableFeltId id) => owned.contains(id);

  TableFeltState copyWith({
    Set<TableFeltId>? owned,
    TableFeltId? equipped,
    bool? loaded,
  }) => TableFeltState(
    owned: owned ?? this.owned,
    equipped: equipped ?? this.equipped,
    loaded: loaded ?? this.loaded,
  );
}

class FeltActionResult {
  const FeltActionResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// Pure logic. [spendGems] draws from the gem bank and returns the new
/// balance, or null when the bank can't cover it (no overspend).
class TableFeltLogic {
  TableFeltLogic._();

  static (TableFeltState, FeltActionResult) buy(
    TableFeltState state,
    TableFeltId id, {
    required int bankGems,
    required int? Function(int gems) spendGems,
  }) {
    final def = TableFeltCatalog.byId(id);
    if (state.isOwned(id)) {
      return (state, const FeltActionResult(false, 'Already owned'));
    }
    if (!def.isFree) {
      if (bankGems < def.priceGems) {
        return (
          state,
          FeltActionResult(
            false,
            'Need ${def.priceGems} gems (you have $bankGems gems)',
          ),
        );
      }
      if (spendGems(def.priceGems) == null) {
        return (state, const FeltActionResult(false, 'Not enough gems'));
      }
    }
    return (
      state.copyWith(owned: {...state.owned, id}),
      FeltActionResult(true, 'Bought ${def.name}!'),
    );
  }

  static (TableFeltState, FeltActionResult) equip(
    TableFeltState state,
    TableFeltId id,
  ) {
    if (!state.isOwned(id)) {
      return (state, const FeltActionResult(false, 'Not owned'));
    }
    return (
      state.copyWith(equipped: id),
      FeltActionResult(true, 'Equipped ${TableFeltCatalog.byId(id).name}'),
    );
  }
}

class TableFeltNotifier extends Notifier<TableFeltState> {
  static const kOwned = 'table_felts_owned';
  static const kEquipped = 'table_felt_equipped';

  @override
  TableFeltState build() {
    Future.microtask(() async {
      try {
        await _load();
      } catch (e, st) {
        debugPrint('TableFeltNotifier: prefs load failed: $e\n$st');
      }
    });
    return const TableFeltState();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final owned = <TableFeltId>{TableFeltCatalog.defaultId};
    for (final raw in p.getStringList(kOwned) ?? const <String>[]) {
      final d = TableFeltCatalog.tryParse(raw);
      if (d != null) owned.add(d.id);
    }
    final eq =
        TableFeltCatalog.tryParse(p.getString(kEquipped) ?? '')?.id ??
        TableFeltCatalog.defaultId;
    state = TableFeltState(
      owned: owned,
      equipped: owned.contains(eq) ? eq : TableFeltCatalog.defaultId,
      loaded: true,
    );
  }

  Future<void> reload() => _load();

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      kOwned,
      state.owned.map((e) => e.name).toList()..sort(),
    );
    await p.setString(kEquipped, state.equipped.name);
  }

  Future<FeltActionResult> buy(
    TableFeltId id, {
    required int bankGems,
    required int? Function(int gems) spendGems,
  }) async {
    final (next, r) = TableFeltLogic.buy(
      state,
      id,
      bankGems: bankGems,
      spendGems: spendGems,
    );
    if (r.ok) {
      state = next;
      await _persist();
    }
    return r;
  }

  Future<FeltActionResult> equip(TableFeltId id) async {
    final (next, r) = TableFeltLogic.equip(state, id);
    if (r.ok) {
      state = next;
      await _persist();
    }
    return r;
  }
}

final tableFeltProvider = NotifierProvider<TableFeltNotifier, TableFeltState>(
  TableFeltNotifier.new,
);
