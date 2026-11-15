import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cosmetics/table_felt.dart';

/// The table backdrop: night sky into the player's equipped felt. Shared by
/// the offline match screen and the online table so both look the same.
class TableFeltBackground extends ConsumerWidget {
  const TableFeltBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final felt = ref.watch(tableFeltProvider).equippedDef;
    return Container(
      key: const ValueKey('table-felt-background'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF1B0F3B), felt.color, felt.deepColor],
        ),
      ),
      child: child,
    );
  }
}
