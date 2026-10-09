import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:marge/engine/engine.dart';

/// The Bank pill's '+N gems' comes straight from the engine
/// (MatchSnapshot.bankGems). It must equal what bank() then pays.
void main() {
  test('bankGems == what bank() credits, across random tables', () {
    var checked = 0;
    var houseStakeCases = 0;
    var shortfallCases = 0;
    for (var seed = 0; seed < 400; seed++) {
      final r = Random(seed);
      final c = MatchController(
        config: MatchConfig(
          botCount: 1 + r.nextInt(4),
          otherHumanCount: r.nextInt(2),
          // Low banks so soft takes, House stakes and shortfalls happen.
          startBankCents: r.nextInt(40),
          anteCents: 5 + r.nextInt(3) * 5,
        ),
        rng: Random(seed * 31 + 1),
      );
      c.startMatch();
      for (var step = 0; step < 200; step++) {
        final s = c.snapshot;
        if (s.phase == MatchPhase.matchEnd) break;
        if (s.phase == MatchPhase.awaitingHandoff) {
          c.confirmHandoff();
          continue;
        }
        if (s.phase == MatchPhase.awaitingShortfall) {
          c.quitShortfall();
          continue;
        }
        final t = s.turn;
        if (t == null) break;
        if (t.hasRolled && t.canBank) {
          final seat = s.currentSeatIndex;
          final before = s.players[seat].bankCents;
          final preview = s.bankGems;
          if (s.players.any(
            (p) => p.bankCents < t.lastScore.perOpponentCents,
          )) {
            houseStakeCases++;
          }
          c.bank();
          // A short person's choice: quitting pays exactly what was at the
          // table, which is what the preview promised.
          while (c.snapshot.phase == MatchPhase.awaitingShortfall) {
            shortfallCases++;
            c.quitShortfall();
          }
          final after = c.snapshot.players[seat].bankCents;
          expect(after - before, preview, reason: 'seed $seed step $step');
          checked++;
          continue;
        }
        expect(s.bankGems, 0);
        c.roll();
      }
    }
    expect(checked, greaterThan(200));
    expect(houseStakeCases, greaterThan(0));
    expect(shortfallCases, greaterThan(0));
  });

  test('a miss previews 0; nothing rolled previews 0', () {
    final c = MatchController(config: const MatchConfig(botCount: 1));
    c.startMatch();
    expect(c.snapshot.bankGems, 0);
  });
}
