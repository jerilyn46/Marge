import 'dart:math';

import 'bot_ai.dart';
import 'dice.dart';
import 'hand_evaluator.dart';
import 'player.dart';
import 'turn_state.dart';

enum MatchPhase {
  setup,
  ante,
  playing,
  betweenTurns,
  roundEnd,
  matchEnd,
}

class MatchConfig {
  const MatchConfig({
    this.humanCount = 1,
    this.startBankCents = 100,
    this.anteCents = 10,
    this.houseStakeCents = 50,
    this.seatCount = 4,
    this.humanNames = const ['You'],
  });

  final int humanCount;
  final int startBankCents;
  final int anteCents;
  final int houseStakeCents;
  final int seatCount;
  final List<String> humanNames;
}

class MatchSnapshot {
  const MatchSnapshot({
    required this.phase,
    required this.players,
    required this.potCents,
    required this.roundNumber,
    required this.currentSeatIndex,
    required this.turn,
    required this.log,
    required this.lastPayout,
    required this.winnerId,
    required this.config,
  });

  final MatchPhase phase;
  final List<PlayerState> players;
  final int potCents;
  final int roundNumber;
  final int currentSeatIndex;
  final TurnState? turn;
  final List<String> log;
  final PayoutEvent? lastPayout;
  final String? winnerId;
  final MatchConfig config;

  PlayerState get currentPlayer => players[currentSeatIndex];

  List<PlayerState> get activePlayers =>
      players.where((p) => !p.eliminated).toList();
}

/// Orchestrates endless rounds of Marge.
class MatchController {
  MatchController({
    MatchConfig? config,
    Random? rng,
  })  : config = config ?? const MatchConfig(),
        rng = rng ?? Random();

  final MatchConfig config;
  final Random rng;
  late final BotAI _botAI = BotAI(rng);

  late List<PlayerState> _players;
  MatchPhase _phase = MatchPhase.setup;
  int _pot = 0;
  int _round = 0;
  int _seat = 0;
  TurnState? _turn;
  final List<String> _log = [];
  PayoutEvent? _lastPayout;
  String? _winnerId;

  MatchSnapshot get snapshot => MatchSnapshot(
        phase: _phase,
        players: List.unmodifiable(_players),
        potCents: _pot,
        roundNumber: _round,
        currentSeatIndex: _seat,
        turn: _turn,
        log: List.unmodifiable(_log),
        lastPayout: _lastPayout,
        winnerId: _winnerId,
        config: config,
      );

  void startMatch() {
    _players = _buildSeats();
    _pot = 0;
    _round = 0;
    _seat = 0;
    _turn = null;
    _log.clear();
    _lastPayout = null;
    _winnerId = null;
    _phase = MatchPhase.ante;
    _log.add('Match started — ${_players.length} seats, '
        '${config.startBankCents}¢ banks.');
    _beginRound();
  }

  List<PlayerState> _buildSeats() {
    final seats = <PlayerState>[];
    final humans = config.humanCount.clamp(1, config.seatCount);
    for (var i = 0; i < humans; i++) {
      final name = i < config.humanNames.length
          ? config.humanNames[i]
          : 'Player ${i + 1}';
      seats.add(PlayerState(
        profile: PlayerProfile(
          id: 'human_$i',
          name: name,
          kind: SeatKind.human,
          avatarEmoji: i == 0 ? '😎' : '🎲',
          colorSeed: 10 + i,
        ),
        bankCents: config.startBankCents,
      ));
    }
    var botIdx = 0;
    while (seats.length < config.seatCount) {
      final bot = BotRoster.bots[botIdx % BotRoster.bots.length];
      seats.add(PlayerState(
        profile: bot.copyWith(
          // Ensure unique ids when wrapping roster.
          name: botIdx < BotRoster.bots.length
              ? bot.name
              : '${bot.name}$botIdx',
        ),
        bankCents: config.startBankCents,
      ));
      // Fix unique id
      final last = seats.removeLast();
      seats.add(PlayerState(
        profile: PlayerProfile(
          id: '${bot.id}_$botIdx',
          name: last.profile.name,
          kind: SeatKind.bot,
          personality: bot.personality,
          avatarEmoji: bot.avatarEmoji,
          colorSeed: bot.colorSeed,
        ),
        bankCents: config.startBankCents,
      ));
      botIdx++;
    }
    return seats;
  }

  void _beginRound() {
    _round++;
    if (_lastPayout?.celebratory != true) {
      _lastPayout = null;
    }
    _log.add('— Round $_round — ante ${config.anteCents}¢ —');

    // Collect ante from each non-eliminated player.
    for (var i = 0; i < _players.length; i++) {
      final p = _players[i];
      if (p.eliminated) continue;
      final paid = _takeFromBank(i, config.anteCents, soft: true);
      _pot += paid;
      if (paid < config.anteCents) {
        _log.add('${p.profile.name} ante short ($paid¢).');
      }
    }

    _seat = _firstActiveSeat(from: 0);
    _phase = MatchPhase.playing;
    _startTurn();
  }

  int _firstActiveSeat({required int from}) {
    for (var step = 0; step < _players.length; step++) {
      final i = (from + step) % _players.length;
      if (!_players[i].eliminated) return i;
    }
    return from;
  }

  void _startTurn() {
    final p = _players[_seat];
    _turn = TurnState.start(p.profile.id);
    if (_lastPayout?.celebratory != true) {
      _lastPayout = null;
    }
    _log.add("${p.profile.name}'s turn.");
    _phase = MatchPhase.playing;
  }

  /// Human / external: toggle keep on a die (only after first roll).
  void toggleKeep(int index) {
    final t = _turn;
    if (t == null || !t.hasRolled || t.rollNumber >= 3) return;
    if (_players[_seat].profile.isBot) return;
    _turn = t.copyWith(dice: t.dice.toggleKeep(index));
  }

  void setKeeps(List<bool> flags) {
    final t = _turn;
    if (t == null || !t.hasRolled) return;
    var dice = t.dice;
    for (var i = 0; i < 3; i++) {
      dice = dice.setKept(i, flags[i]);
    }
    _turn = t.copyWith(dice: dice);
  }

  /// Roll non-kept dice (or all on first roll).
  void roll() {
    final t = _turn;
    if (t == null) return;
    if (t.rollNumber >= 3) return;

    late DiceSet nextDice;
    final nextRoll = t.rollNumber + 1;
    if (!t.hasRolled) {
      nextDice = DiceSet.rollAll(rng);
    } else {
      nextDice = t.dice.roll(rng);
    }

    final score = HandEvaluator.evaluate(nextDice, rollNumber: nextRoll);
    _turn = t.copyWith(
      rollNumber: nextRoll,
      dice: nextDice,
      hasRolled: true,
      lastScore: score,
    );

    _log.add(
      '${_players[_seat].profile.name} rolled ${nextDice.values} '
      '(roll $nextRoll)${score.isScoring ? ' → ${score.kind.name}' : ''}',
    );

    // Auto-resolve pot win immediately — dramatic.
    if (score.kind == ScoreKind.tripleOnesPotWin) {
      _resolveBank();
      return;
    }

    // Only after the 3rd roll with still no winning hand does bust apply.
    // Earlier no-score rolls must leave the turn active so the player can
    // keep / re-roll (up to 3 rolls total).
    if (!score.isScoring && nextRoll >= 3) {
      _resolveBank();
    }
  }

  /// Bank current scoring hand (or finish after 3 rolls / bust).
  /// Refuses to end the turn early on a non-scoring hand while rolls remain.
  void bank() {
    final t = _turn;
    if (t == null || !t.hasRolled) return;
    if (!t.canBank && !t.mustFinish) return;
    _resolveBank();
  }

  void _resolveBank() {
    final t = _turn!;
    final score = t.lastScore;
    final player = _players[_seat];

    if (score.kind == ScoreKind.tripleOnesPotWin) {
      final won = _pot;
      _credit(_seat, won);
      _pot = 0;
      _lastPayout = PayoutEvent(
        message: '${player.profile.name} hit TRIPLE ONES on first roll '
            'and sweeps the pot (+$won¢)!',
        kind: ScoreKind.tripleOnesPotWin,
        amountCents: won,
        celebratory: true,
      );
      _log.add(_lastPayout!.message);
      _endRoundAfterPotWin();
      return;
    }

    if (score.isScoring) {
      final paidTotal = _collectFromOthers(score.perOpponentCents);
      _credit(_seat, paidTotal);
      _lastPayout = PayoutEvent(
        message: _describeScore(player.profile.name, score, paidTotal),
        kind: score.kind,
        amountCents: paidTotal,
        celebratory: score.kind == ScoreKind.tripleOnesPay,
      );
      _log.add(_lastPayout!.message);
    } else if (t.rollNumber >= 3) {
      // Bust: put 2¢ in pot.
      final pen = HandEvaluator.bustPenalty.potPenaltyCents;
      final paid = _takeFromBank(_seat, pen, soft: true);
      _pot += paid;
      _lastPayout = PayoutEvent(
        message: '${player.profile.name} whiffs — $paid¢ to the pot.',
        kind: ScoreKind.none,
        amountCents: paid,
      );
      _log.add(_lastPayout!.message);
    } else {
      // Guard: never advance on a no-score hand while rolls remain.
      _log.add(
        '${player.profile.name} still has rolls left — keep rolling.',
      );
      return;
    }

    _advanceTurn();
  }

  String _describeScore(String name, ScoreResult score, int total) {
    switch (score.kind) {
      case ScoreKind.tripleOnesPay:
        return '$name rolls triple ones! Collects $total¢ '
            '(${score.perOpponentCents}¢ each).';
      case ScoreKind.threeOfAKind:
        return '$name hits three ${score.faceValue}s! '
            'Collects $total¢ (${score.perOpponentCents}¢ each).';
      case ScoreKind.straight:
        return '$name nails a straight! Collects $total¢ (5¢ each).';
      case ScoreKind.tripleOnesPotWin:
        return '$name sweeps the pot!';
      case ScoreKind.none:
        return '$name scores nothing.';
    }
  }

  int _collectFromOthers(int eachCents) {
    if (eachCents <= 0) return 0;
    var total = 0;
    for (var i = 0; i < _players.length; i++) {
      if (i == _seat || _players[i].eliminated) continue;
      final paid = _takeFromBank(i, eachCents, soft: true);
      total += paid;
    }
    return total;
  }

  void _credit(int index, int cents) {
    if (cents <= 0) return;
    final p = _players[index];
    _players[index] = p.copyWith(bankCents: p.bankCents + cents);
  }

  /// Soft take: apply house stake once if needed; never go negative.
  int _takeFromBank(int index, int amount, {required bool soft}) {
    if (amount <= 0) return 0;
    var p = _players[index];
    if (p.eliminated) return 0;

    if (p.bankCents >= amount) {
      _players[index] = p.copyWith(bankCents: p.bankCents - amount);
      return amount;
    }

    // Soft bankrupt: once-per-match House stake top-up.
    if (soft && !p.usedHouseStake) {
      final topped = p.bankCents + config.houseStakeCents;
      _log.add(
        '🏠 House stake: ${p.profile.name} gets '
        '+${config.houseStakeCents}¢ (once).',
      );
      p = p.copyWith(bankCents: topped, usedHouseStake: true);
      _players[index] = p;
      if (p.bankCents >= amount) {
        _players[index] = p.copyWith(bankCents: p.bankCents - amount);
        return amount;
      }
    }

    // Pay what they can; mark eliminated if broke after house stake used.
    final paid = p.bankCents;
    p = p.copyWith(bankCents: 0);
    if (p.usedHouseStake && paid == 0) {
      p = p.copyWith(eliminated: true);
      _log.add('${p.profile.name} is out of chips.');
    } else if (p.usedHouseStake && p.bankCents == 0 && paid < amount) {
      // Still broke after paying remainder — soft eliminate next ante.
      if (p.bankCents == 0) {
        // leave at 0; may get eliminated on next failed ante
      }
    }
    _players[index] = p;
    return paid;
  }

  void _advanceTurn() {
    _turn = null;
    final active = _players.where((p) => !p.eliminated).length;
    if (active <= 1) {
      _endMatch();
      return;
    }

    // Next active seat.
    final next = _firstActiveSeat(from: _seat + 1);
    // If we wrapped past the starting seat of the round without everyone
    // acting — actually we just keep going endlessly; a "round" ends only
    // on pot-win. Turns continue around the table forever.
    _seat = next;
    _startTurn();
  }

  void _endRoundAfterPotWin() {
    _turn = null;
    final active = _players.where((p) => !p.eliminated).length;
    if (active <= 1) {
      _endMatch();
      return;
    }
    _phase = MatchPhase.roundEnd;
    // Immediately start next round with ante.
    _beginRound();
  }

  void endMatch() {
    _endMatch();
  }

  void _endMatch() {
    _phase = MatchPhase.matchEnd;
    _turn = null;
    final sorted = [..._players]
      ..sort((a, b) => b.bankCents.compareTo(a.bankCents));
    _winnerId = sorted.first.profile.id;
    _log.add(
      'Match over. Winner: ${sorted.first.profile.name} '
      'with ${sorted.first.bankCents}¢.',
    );
  }

  /// Drive one bot action if current seat is a bot. Returns true if acted.
  bool tickBot() {
    if (_phase != MatchPhase.playing) return false;
    final p = _players[_seat];
    if (!p.profile.isBot || p.eliminated) return false;
    final t = _turn;
    if (t == null) return false;

    final personality =
        p.profile.personality ?? BotPersonality.cautious;
    final decision = _botAI.decide(t, personality);

    switch (decision) {
      case BotRoll(:final keepIndices):
        if (t.hasRolled) {
          var dice = t.dice.clearKept();
          for (final i in keepIndices) {
            if (i >= 0 && i < 3) dice = dice.setKept(i, true);
          }
          _turn = t.copyWith(dice: dice);
        }
        roll();
        // If pot win auto-resolved, stop.
        return true;
      case BotBank():
        if (t.hasRolled) {
          bank();
        } else {
          roll();
        }
        return true;
    }
  }

  /// Convenience: run bots until a human must act or match ends.
  void runBotsUntilHuman({int maxSteps = 64}) {
    var steps = 0;
    while (steps < maxSteps &&
        _phase == MatchPhase.playing &&
        _players[_seat].profile.isBot) {
      tickBot();
      steps++;
    }
  }
}
