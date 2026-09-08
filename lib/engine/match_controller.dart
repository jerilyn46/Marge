import 'dart:math';

import 'bot_ai.dart';
import 'dice.dart';
import 'hand_evaluator.dart';
import 'player.dart';
import 'seat_coin_book.dart';
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

/// Resolved lobby counts after seating priority is applied.
typedef LobbySeatPlan = ({int bots, int others, int online, int friends});

/// Lobby choices for a match.
///
/// Always includes the local user as seat 0 ("You" / Player 1).
/// Seating order is fixed: local user, other hotseat humans, chosen
/// friends (named waiting chairs — no live session), reserved online
/// slots, then bots filling leftover seats. Bots never displace a human,
/// friend, or online chair.
///
/// There is no live matchmaking session in this app. [onlinePlayerCount]
/// reserves chairs labeled [WaitingSeat.name]; it does not invent players
/// or convert those chairs into bots.
class MatchConfig {
  const MatchConfig({
    this.botCount = 3,
    this.otherHumanCount = 0,
    this.onlinePlayerCount = 0,
    this.friendNames = const [],
    this.startBankCents = 100,
    this.anteCents = 10,
    this.houseStakeCents = 50,
    this.localPlayerName = 'You',
    this.humanNames,
  }) : assert(botCount >= 0),
       assert(otherHumanCount >= 0),
       assert(onlinePlayerCount >= 0);

  /// Number of bot seats that actually sit (preferred range 0–4).
  /// Leftover after humans and online reservations — never more.
  final int botCount;

  /// Hotseat humans besides the local user (preferred range 0–4).
  final int otherHumanCount;

  /// Reserved online chairs (0–4). Seated after friends, before bots.
  /// With no live session these stay waiting and do not play.
  final int onlinePlayerCount;

  /// Friends the local player chose to sit. They are not on this device,
  /// so they are named waiting chairs — not bots and not invented players.
  final List<String> friendNames;

  final int startBankCents;
  final int anteCents;
  final int houseStakeCents;

  /// Display name for the local user (Player 1).
  final String localPlayerName;

  /// Optional explicit human names. Index 0 = local user; remaining are
  /// other hotseat players. If null/short, defaults are generated.
  /// Never used for online waiting chairs.
  final List<String>? humanNames;

  /// Total human seats including the local user.
  int get humanCount => 1 + otherHumanCount;

  int get friendCount => friendNames.length;

  /// Total chairs at the table (local + hotseat + friends + online + bots).
  int get seatCount =>
      1 + otherHumanCount + friendCount + onlinePlayerCount + botCount;

  /// Seats that roll, ante, and pay (waiting chairs excluded).
  int get playableSeatCount => 1 + otherHumanCount + botCount;

  /// Playable opponents excluding the local user. Waiting chairs do not count.
  int get opponentCount => otherHumanCount + botCount;

  /// True when reserved online chairs exist and no live session can fill them.
  bool get onlineSeatsAreWaiting => onlinePlayerCount > 0;

  /// Max opponents allowed (local user + 7 others = 8 seats).
  static const int maxOpponents = 7;

  /// Preferred max on each lobby stepper.
  static const int maxBotsSelectable = 4;
  static const int maxOtherHumansSelectable = 4;
  static const int maxOnlineSelectable = 4;

  bool get isValid =>
      opponentCount >= 1 &&
      opponentCount <= maxOpponents &&
      botCount >= 0 &&
      otherHumanCount >= 0 &&
      onlinePlayerCount >= 0 &&
      onlinePlayerCount <= maxOnlineSelectable &&
      seatCount >= 2 &&
      seatCount <= maxOpponents + 1;

  /// Humans, then online, then bots. Bots are trimmed first so they never
  /// displace a local human or a reserved online chair.
  static LobbySeatPlan clampLobbyCounts(
    int bots,
    int others, [
    int online = 0,
    int friends = 0,
  ]) {
    final seatedOthers = others.clamp(0, maxOtherHumansSelectable);
    var remaining = (maxOpponents - seatedOthers).clamp(0, maxOpponents);
    // Friends sit before unnamed online chairs and before bots.
    final seatedFriends = friends.clamp(0, remaining);
    remaining -= seatedFriends;
    final seatedOnline = online
        .clamp(0, maxOnlineSelectable)
        .clamp(0, remaining);
    remaining -= seatedOnline;
    final seatedBots = bots.clamp(0, maxBotsSelectable).clamp(0, remaining);
    return (
      bots: seatedBots,
      others: seatedOthers,
      online: seatedOnline,
      friends: seatedFriends,
    );
  }

  /// Clamp bot count to leftover seats after humans and online (0–4).
  static int clampBots(int bots, int others, [int online = 0]) =>
      clampLobbyCounts(bots, others, online).bots;

  /// Local humans are seated first. Bots and online do not reduce this cap
  /// (they are trimmed when the full plan is applied).
  static int clampOthers(int bots, int others, [int online = 0]) =>
      clampLobbyCounts(bots, others, online).others;

  /// Clamp online reservations to seats left after local humans (0–4).
  static int clampOnline(int bots, int others, int online) =>
      clampLobbyCounts(bots, others, online).online;

  /// Clamp into the valid lobby space (trims bots, then online, to keep humans).
  static (int bots, int others) clampLobby(int bots, int others) {
    final plan = clampLobbyCounts(bots, others, 0);
    return (plan.bots, plan.others);
  }

  /// Whether the +bot stepper should be enabled. Bots only fill leftover seats.
  static bool canIncrementBots(
    int bots,
    int others, [
    int online = 0,
    int friends = 0,
  ]) =>
      bots < maxBotsSelectable &&
      bots + others + online + friends < maxOpponents;

  /// Whether the +other-human stepper should be enabled.
  /// Local humans bump bots (and online, if needed) rather than being blocked.
  static bool canIncrementOthers(
    int bots,
    int others, [
    int online = 0,
    int friends = 0,
  ]) =>
      others < maxOtherHumansSelectable && others < maxOpponents;

  /// Whether the +online stepper should be enabled. Online is seated before bots.
  static bool canIncrementOnline(
    int bots,
    int others,
    int online, [
    int friends = 0,
  ]) =>
      online < maxOnlineSelectable && others + friends + online < maxOpponents;
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
      players.where((p) => p.profile.participates && !p.eliminated).toList();

  bool get awaitingHandoff =>
      phase == MatchPhase.awaitingHandoff && handoff != null;
}

/// Orchestrates endless rounds of Marge.
class MatchController {
  MatchController({MatchConfig? config, Random? rng, this.coins})
    : config = config ?? const MatchConfig(),
      rng = rng ?? Random();

  final MatchConfig config;
  final Random rng;

  /// Saved per-player banks. Null keeps the old per-match start bank.
  final SeatCoinBook? coins;
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
    final waiting = _players.where((p) => p.profile.isWaiting).length;
    final waitingBit = waiting > 0
        ? ', $waiting waiting for online players'
        : '';
    _log.add(
      'Match started — ${_players.length} seats$waitingBit, '
      '${config.startBankCents}¢ banks.',
    );
    _beginRound();
  }

  static const _personalities = <BotPersonality>[
    BotPersonality.aggressive,
    BotPersonality.cautious,
    BotPersonality.chaotic,
  ];

  bool _plays(PlayerState player) =>
      player.profile.participates && !player.eliminated;

  int _openingBank(String name, {required bool bot}) {
    final book = coins;
    if (book == null) return config.startBankCents;
    return book.openingCents(name, bot: bot, fallback: config.startBankCents);
  }

  void _remember(int index) {
    final book = coins;
    if (book == null) return;
    final p = _players[index];
    if (!p.profile.participates) return;
    book.write(p.profile.name, bot: p.profile.isBot, cents: p.bankCents);
  }

  List<PlayerState> _buildSeats() {
    // Priority: local user, other hotseat humans, online reservations, bots.
    // There is no live session, so online chairs stay "Waiting for player".
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
      seats.add(
        PlayerState(
          profile: PlayerProfile(
            id: 'human_$i',
            name: name,
            kind: SeatKind.human,
            avatarEmoji: i == 0 ? '😎' : '🎲',
            colorSeed: 10 + i,
          ),
          bankCents: _openingBank(name, bot: false),
        ),
      );
    }

    for (var i = 0; i < config.friendNames.length; i++) {
      final name = config.friendNames[i].trim();
      if (name.isEmpty) continue;
      seats.add(
        PlayerState(
          profile: PlayerProfile(
            id: 'friend_$i',
            name: name,
            kind: SeatKind.waiting,
            avatarEmoji: '👋',
            colorSeed: 30 + i,
          ),
          // Saved coins stay visible; waiting friends do not ante or roll.
          bankCents: _openingBank(name, bot: false),
        ),
      );
    }

    for (var i = 0; i < config.onlinePlayerCount; i++) {
      seats.add(
        PlayerState(
          profile: PlayerProfile(
            id: 'online_$i',
            name: WaitingSeat.name,
            kind: SeatKind.waiting,
            avatarEmoji: WaitingSeat.emoji,
            colorSeed: 40 + i,
          ),
          bankCents: 0,
        ),
      );
    }

    for (var botIdx = 0; botIdx < config.botCount; botIdx++) {
      final personality = _personalities[botIdx % _personalities.length];
      final name = BotRoster.nameAt(botIdx);
      final emoji = BotRoster.emojiAt(botIdx);
      final colorSeed = botIdx < BotRoster.bots.length
          ? BotRoster.bots[botIdx].colorSeed
          : 20 + botIdx;
      seats.add(
        PlayerState(
          profile: PlayerProfile(
            id: 'bot_$botIdx',
            name: name,
            kind: SeatKind.bot,
            personality: personality,
            avatarEmoji: emoji,
            colorSeed: colorSeed,
          ),
          bankCents: _openingBank(name, bot: true),
        ),
      );
    }
    return seats;
  }

  void _beginRound() {
    _round++;
    if (_lastPayout?.celebratory != true) {
      _lastPayout = null;
    }
    _log.add('— Round $_round — ante ${config.anteCents}¢ —');

    // Collect ante from each seated player. Waiting chairs do not ante.
    for (var i = 0; i < _players.length; i++) {
      final p = _players[i];
      if (!_plays(p)) continue;
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
      if (_plays(_players[i])) return i;
    }
    return from;
  }

  int get _playableCount => _players.where(_plays).length;

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
        message:
            '${player.profile.name} hit TRIPLE ONES on first roll '
            'and sweeps the pot (+$won¢)!',
        kind: ScoreKind.tripleOnesPotWin,
        amountCents: won,
        celebratory: true,
      );
      _log.add(_lastPayout!.message);
      // First-roll triple ones: take the pot, end the round, re-ante, then
      // the same winner starts a fresh 3 rolls. Do not pass the seat.
      _continueSameSeatAfterWin(restartRound: true);
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
      // Win banks, then this seat starts a fresh 3 rolls. Do not hand off.
      _continueSameSeatAfterWin(restartRound: false);
      return;
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
      _log.add('${player.profile.name} still has rolls left — keep rolling.');
      return;
    }

    _enterHandoff(restartsRound: false);
  }

  /// After a scoring bank: keep this seat and start a fresh 3-roll set.
  /// Does not apply to first-roll triple ones (that ends the round).
  void _continueSameSeatAfterWin({required bool restartRound}) {
    if (_playableCount <= 1) {
      _turn = null;
      _handoff = null;
      _endMatch();
      return;
    }
    final payout = _lastPayout;
    final seat = _seat;
    _handoff = null;
    if (restartRound) {
      _round++;
      _log.add('— Round $_round — ante ${config.anteCents}¢ —');
      for (var i = 0; i < _players.length; i++) {
        final p = _players[i];
        if (!_plays(p)) continue;
        final paid = _takeFromBank(i, config.anteCents, soft: true);
        _pot += paid;
      }
      if (_players[seat].eliminated) {
        _seat = _firstActiveSeat(from: seat);
      }
    }
    _startTurn();
    _lastPayout = payout;
    _log.add('${_players[_seat].profile.name} keeps the seat — fresh 3 rolls.');
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
      if (i == _seat || !_plays(_players[i])) continue;
      final paid = _takeFromBank(i, eachCents, soft: true);
      total += paid;
    }
    return total;
  }

  void _credit(int index, int cents) {
    if (cents <= 0) return;
    final p = _players[index];
    _players[index] = p.copyWith(bankCents: p.bankCents + cents);
    _remember(index);
  }

  /// Soft take: apply house stake once if needed; never go negative.
  int _takeFromBank(int index, int amount, {required bool soft}) {
    if (amount <= 0) return 0;
    var p = _players[index];
    if (p.eliminated) return 0;

    if (p.bankCents >= amount) {
      _players[index] = p.copyWith(bankCents: p.bankCents - amount);
      _remember(index);
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
        _remember(index);
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
    _remember(index);
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
    if (_playableCount <= 1) {
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
    final sorted = _players.where(_plays).toList()
      ..sort((a, b) => b.bankCents.compareTo(a.bankCents));
    if (sorted.isEmpty) {
      _winnerId = null;
      _log.add('Match over. No seated players.');
      return;
    }
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
    if (!p.profile.isBot || !_plays(p)) return false;
    final t = _turn;
    if (t == null) return false;

    final personality = p.profile.personality ?? BotPersonality.cautious;
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
        _players[_seat].profile.isBot &&
        _plays(_players[_seat])) {
      tickBot();
      steps++;
    }
  }
}
