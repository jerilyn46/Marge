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
  /// Post–turn-end gate: last roll locked until Next/Continue.
  awaitingHandoff,
  roundEnd,
  matchEnd,
}

/// Frozen last-roll result shown until the human taps Next/Continue.
class HandoffState {
  const HandoffState({
    required this.diceValues,
    required this.outcomeText,
    required this.bankDeltaCents,
    required this.fromSeatIndex,
    required this.nextSeatIndex,
    required this.restartsRound,
    required this.kind,
  });

  /// Locked faces from the settled roll (length 3).
  final List<int> diceValues;

  /// Short outcome label for the sticky strip.
  final String outcomeText;

  /// Signed bank change for the acting seat (+gain / −bust penalty).
  final int bankDeltaCents;

  final int fromSeatIndex;

  /// Seat that will become current after confirm (pre-computed; for pot-win
  /// restart this is the first active seat after the new ante).
  final int nextSeatIndex;

  /// True when confirming should start a fresh ante round (pot sweep).
  final bool restartsRound;

  final ScoreKind kind;

  /// Hotseat (other humans present) → "Next player"; else "Continue".
  static bool isHotseatCta(MatchConfig config) => config.humanCount > 1;
}

/// Lobby choices for a match.
///
/// Always includes the local user as seat 0 ("You" / Player 1).
/// [botCount] and [otherHumanCount] are independent choosers (0–4 each),
/// with validation: at least one opponent total, and at most 7 opponents
/// (8 seats including the local user).
class MatchConfig {
  const MatchConfig({
    this.botCount = 3,
    this.otherHumanCount = 0,
    this.startBankCents = 100,
    this.anteCents = 10,
    this.houseStakeCents = 50,
    this.localPlayerName = 'You',
    this.humanNames,
  })  : assert(botCount >= 0),
        assert(otherHumanCount >= 0);

  /// Number of bot seats (preferred range 0–4).
  final int botCount;

  /// Hotseat humans besides the local user (preferred range 0–4).
  final int otherHumanCount;

  final int startBankCents;
  final int anteCents;
  final int houseStakeCents;

  /// Display name for the local user (Player 1).
  final String localPlayerName;

  /// Optional explicit human names. Index 0 = local user; remaining are
  /// other hotseat players. If null/short, defaults are generated.
  final List<String>? humanNames;

  /// Total human seats including the local user.
  int get humanCount => 1 + otherHumanCount;

  /// Total seated players (local + others + bots).
  int get seatCount => 1 + otherHumanCount + botCount;

  /// Opponents excluding the local user.
  int get opponentCount => otherHumanCount + botCount;

  /// Max opponents allowed (local user + 7 others = 8 seats).
  static const int maxOpponents = 7;

  /// Preferred max on each lobby stepper.
  static const int maxBotsSelectable = 4;
  static const int maxOtherHumansSelectable = 4;

  bool get isValid =>
      opponentCount >= 1 &&
      opponentCount <= maxOpponents &&
      botCount >= 0 &&
      otherHumanCount >= 0 &&
      seatCount >= 2 &&
      seatCount <= maxOpponents + 1;

  /// Clamp bot count against a fixed other-human count (0–4, ≤7 opponents).
  static int clampBots(int bots, int others) {
    final o = others.clamp(0, maxOtherHumansSelectable);
    final maxB = (maxOpponents - o).clamp(0, maxBotsSelectable);
    return bots.clamp(0, maxB);
  }

  /// Clamp other-human count against a fixed bot count (0–4, ≤7 opponents).
  static int clampOthers(int bots, int others) {
    final b = bots.clamp(0, maxBotsSelectable);
    final maxO = (maxOpponents - b).clamp(0, maxOtherHumansSelectable);
    return others.clamp(0, maxO);
  }

  /// Clamp both into the valid lobby space (trims bots first if over cap).
  static (int bots, int others) clampLobby(int bots, int others) {
    final o = others.clamp(0, maxOtherHumansSelectable);
    final b = clampBots(bots, o);
    return (b, o);
  }

  /// Whether the +bot stepper should be enabled from [bots]/[others].
  static bool canIncrementBots(int bots, int others) =>
      bots < maxBotsSelectable && bots + others < maxOpponents;

  /// Whether the +other-human stepper should be enabled.
  static bool canIncrementOthers(int bots, int others) =>
      others < maxOtherHumansSelectable && bots + others < maxOpponents;
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
    this.handoff,
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
  final HandoffState? handoff;

  PlayerState get currentPlayer => players[currentSeatIndex];

  List<PlayerState> get activePlayers =>
      players.where((p) => !p.eliminated).toList();

  bool get awaitingHandoff =>
      phase == MatchPhase.awaitingHandoff && handoff != null;
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
  HandoffState? _handoff;

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
        handoff: _handoff,
      );

  void startMatch() {
    _players = _buildSeats();
    _pot = 0;
    _round = 0;
    _seat = 0;
    _turn = null;
    _handoff = null;
    _log.clear();
    _lastPayout = null;
    _winnerId = null;
    _phase = MatchPhase.ante;
    _log.add('Match started — ${_players.length} seats, '
        '${config.startBankCents}¢ banks.');
    _beginRound();
  }

  static const _personalities = <BotPersonality>[
    BotPersonality.aggressive,
    BotPersonality.cautious,
    BotPersonality.chaotic,
  ];

  static const _botEmojis = <String>['🔥', '🧊', '⚡', '🌟', '🎯', '🃏', '🐉'];

  List<PlayerState> _buildSeats() {
    final seats = <PlayerState>[];
    final names = config.humanNames;
    final humanTotal = config.humanCount;

    for (var i = 0; i < humanTotal; i++) {
      final String name;
      if (names != null && i < names.length) {
        name = names[i];
      } else if (i == 0) {
        name = config.localPlayerName;
      } else {
        name = 'Player ${i + 1}';
      }
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

    for (var botIdx = 0; botIdx < config.botCount; botIdx++) {
      final personality = _personalities[botIdx % _personalities.length];
      final String name;
      final String emoji;
      final int colorSeed;
      if (botIdx < BotRoster.bots.length) {
        final roster = BotRoster.bots[botIdx];
        name = roster.name;
        emoji = roster.avatarEmoji;
        colorSeed = roster.colorSeed;
      } else {
        name = 'Bot ${botIdx + 1}';
        emoji = _botEmojis[botIdx % _botEmojis.length];
        colorSeed = 20 + botIdx;
      }
      seats.add(PlayerState(
        profile: PlayerProfile(
          id: 'bot_$botIdx',
          name: name,
          kind: SeatKind.bot,
          personality: personality,
          avatarEmoji: emoji,
          colorSeed: colorSeed,
        ),
        bankCents: config.startBankCents,
      ));
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
    if (_phase == MatchPhase.awaitingHandoff) return;
    final t = _turn;
    if (t == null || !t.hasRolled || t.rollNumber >= 3) return;
    if (_players[_seat].profile.isBot) return;
    _turn = t.copyWith(dice: t.dice.toggleKeep(index));
  }

  void setKeeps(List<bool> flags) {
    if (_phase == MatchPhase.awaitingHandoff) return;
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
    if (_phase == MatchPhase.awaitingHandoff) return;
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

    // A non-winning hand with rolls remaining is still this player's turn.
    // Do not bust, do not enter handoff, do not advance the seat.
    if (!score.isScoring && nextRoll < 3) {
      _log.add(
        '${_players[_seat].profile.name} no score — keep rolling '
        '(${3 - nextRoll} left).',
      );
      return;
    }

    // Only after the 3rd roll with still no winning hand does bust apply.
    if (!score.isScoring && nextRoll >= 3) {
      _resolveBank();
    }
  }

  /// Bank current scoring hand (or finish after 3 rolls / bust).
  /// Refuses to end the turn early on a non-scoring hand while rolls remain.
  void bank() {
    if (_phase == MatchPhase.awaitingHandoff) return;
    final t = _turn;
    if (t == null || !t.hasRolled) return;
    // Refuse to end the turn on a miss while rolls remain. Banking a
    // non-score is not an option; the player must keep rolling.
    if (t.mustKeepRolling || (!t.canBank && !t.mustFinish)) {
      _log.add(
        '${_players[_seat].profile.name} cannot bank a miss — '
        '${t.rollsLeft} rolls left.',
      );
      return;
    }
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
      _enterHandoff(restartsRound: true);
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

    _enterHandoff(restartsRound: false);
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

  /// Short sticky-strip label for the settled outcome.
  static String shortOutcome(PayoutEvent payout) {
    switch (payout.kind) {
      case ScoreKind.tripleOnesPotWin:
        return 'Pot sweep!';
      case ScoreKind.tripleOnesPay:
        return 'Triple ones';
      case ScoreKind.threeOfAKind:
        return 'Three of a kind';
      case ScoreKind.straight:
        return 'Straight';
      case ScoreKind.none:
        return 'Bust';
    }
  }

  static int signedBankDelta(PayoutEvent payout) {
    if (payout.kind == ScoreKind.none) {
      // Bust: acting seat lost chips to the pot.
      return -payout.amountCents;
    }
    return payout.amountCents;
  }

  /// Lock last dice and wait for Next/Continue before advancing.
  void _enterHandoff({required bool restartsRound}) {
    final t = _turn!;
    // Hard stop: a mid-turn miss must never advance the seat.
    if (!restartsRound && t.mustKeepRolling) {
      _log.add(
        '${_players[_seat].profile.name} still has rolls left — keep rolling.',
      );
      return;
    }
    final payout = _lastPayout!;
    final active = _players.where((p) => !p.eliminated).length;
    if (active <= 1) {
      _turn = null;
      _handoff = null;
      _endMatch();
      return;
    }

    final next = restartsRound
        ? _firstActiveSeat(from: 0)
        : _firstActiveSeat(from: _seat + 1);

    _handoff = HandoffState(
      diceValues: List<int>.unmodifiable(t.dice.values),
      outcomeText: shortOutcome(payout),
      bankDeltaCents: signedBankDelta(payout),
      fromSeatIndex: _seat,
      nextSeatIndex: next,
      restartsRound: restartsRound,
      kind: payout.kind,
    );
    // Keep turn dice visible/locked; UI disables interaction while gated.
    _phase = MatchPhase.awaitingHandoff;
  }

  /// Dismiss the post-turn strip and start the next seat (or new round).
  /// Bots must not act until this is called.
  void confirmHandoff() {
    if (_phase != MatchPhase.awaitingHandoff || _handoff == null) return;
    final h = _handoff!;
    _handoff = null;
    _turn = null;

    if (h.restartsRound) {
      _phase = MatchPhase.roundEnd;
      _beginRound();
      return;
    }

    _seat = h.nextSeatIndex;
    _startTurn();
  }

  void endMatch() {
    _endMatch();
  }

  void _endMatch() {
    _phase = MatchPhase.matchEnd;
    _turn = null;
    _handoff = null;
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
    if (_phase == MatchPhase.awaitingHandoff) return false;
    if (_phase != MatchPhase.playing) return false;
    final p = _players[_seat];
    if (!p.profile.isBot || p.eliminated) return false;
    final t = _turn;
    if (t == null) return false;

    final personality =
        p.profile.personality ?? BotPersonality.cautious;
    final decision = _botAI.decide(t, personality);

    // Bank only a scoring hand, or a finished 3rd-roll miss.
    // A miss with rolls left always rolls again — same rule as humans.
    if (decision is BotBank &&
        t.hasRolled &&
        !t.mustKeepRolling &&
        (t.canBank || t.mustFinish)) {
      bank();
      return true;
    }

    if (t.hasRolled && decision is BotRoll) {
      final keepIndices = decision.keepIndices;
      var dice = t.dice.clearKept();
      for (final i in keepIndices) {
        if (i >= 0 && i < 3) dice = dice.setKept(i, true);
      }
      _turn = t.copyWith(dice: dice);
    }
    roll();
    return true;
  }

  /// Convenience: run bots until a human must act or match ends.
  void runBotsUntilHuman({int maxSteps = 64}) {
    var steps = 0;
    while (steps < maxSteps &&
        _phase == MatchPhase.playing &&
        _handoff == null &&
        _players[_seat].profile.isBot) {
      tickBot();
      steps++;
    }
  }
}
