import 'package:flutter/foundation.dart' show visibleForTesting;

import 'dart:math';

import 'bot_ai.dart';
import 'dice.dart';
import 'hand_evaluator.dart';
import 'player.dart';
import 'gem_label.dart';
import 'gem_shortfall.dart';
import 'match_checkpoint.dart';
import 'seat_coin_book.dart';
import 'turn_state.dart';

enum MatchPhase {
  setup,
  ante,
  playing,
  betweenTurns,

  /// Post–turn-end gate: last roll locked until Next/Continue.
  awaitingHandoff,

  /// First-roll trips shortfall: a human must cover or quit.
  awaitingShortfall,
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
  ]) => others < maxOtherHumansSelectable && others < maxOpponents;

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
    this.pendingShortfall,
    this.endMessage,
  });

  /// Why the match ended, when a rule ended it (e.g. first-roll triple 1s).
  final String? endMessage;

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
  final GemShortfall? pendingShortfall;

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
  String? _endMessage;
  HandoffState? _handoff;
  GemShortfall? _shortfall;
  int _tripsCollected = 0;

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
    pendingShortfall: _shortfall,
    config: config,
    handoff: _handoff,
    endMessage: _endMessage,
  );

  /// [carryPotGems] seeds the pot with gems left in the previous table's pot
  /// ("Continue playing"), so they are not destroyed between games.
  void startMatch({int carryPotGems = 0}) {
    _players = _buildSeats();
    _pot = carryPotGems > 0 ? carryPotGems : 0;
    _round = 0;
    _seat = 0;
    _turn = null;
    _handoff = null;
    _shortfall = null;
    _tripsCollected = 0;
    _log.clear();
    _lastPayout = null;
    _winnerId = null;
    _endMessage = null;
    _phase = MatchPhase.ante;
    final waiting = _players.where((p) => p.profile.isWaiting).length;
    final waitingBit = waiting > 0
        ? ', $waiting waiting for online players'
        : '';
    _log.add(
      'Match started — ${_players.length} seats$waitingBit, '
      '${config.startBankCents} gems banks.',
    );
    if (_pot > 0) _log.add('Pot carried over: ${gemCount(_pot)}.');
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

  /// Add virtual gems to the local human only (table grant / soft recovery).
  ///
  /// Bots and waiting chairs are never credited. If the local player was
  /// sitting out at zero, they come back so the next ante can include them.
  /// House stake is left as-is. Turn, seat, and ante rules are not changed.
  /// Returns the new bank, or null if there is no local human.
  int? grantLocalPlayCoins(int cents) {
    if (cents <= 0 || _players.isEmpty) return null;
    var index = -1;
    for (var i = 0; i < _players.length; i++) {
      if (_players[i].profile.id == 'human_0') {
        index = i;
        break;
      }
    }
    if (index < 0) return null;
    final p = _players[index];
    if (!p.profile.isHuman || p.profile.isBot || p.profile.isWaiting) {
      return null;
    }
    final next = p.bankCents + cents;
    var updated = p.copyWith(bankCents: next);
    if (updated.eliminated && next > 0) {
      updated = updated.copyWith(eliminated: false);
    }
    _players[index] = updated;
    _remember(index);
    _log.add(
      '${p.profile.name} adds ${gemCount(cents)} (virtual gems, not real money).',
    );
    return next;
  }

  /// Tests only: force a seat's table gems (and House-stake flag).
  @visibleForTesting
  void debugSetBank(int seatIndex, int gems, {bool usedHouseStake = true}) {
    _players[seatIndex] = _players[seatIndex].copyWith(
      bankCents: gems,
      usedHouseStake: usedHouseStake,
    );
  }

  /// Move virtual gems onto a seated human at this table only.
  int? addTableGems(int seatIndex, int gems) {
    if (gems <= 0 || seatIndex < 0 || seatIndex >= _players.length) return null;
    final p = _players[seatIndex];
    if (!p.profile.isHuman || p.profile.isWaiting) return null;
    final next = p.bankCents + gems;
    var updated = p.copyWith(bankCents: next);
    if (updated.eliminated && next > 0) {
      updated = updated.copyWith(eliminated: false);
    }
    _players[seatIndex] = updated;
    _remember(seatIndex);
    return next;
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
          // Absent until they sit. No saved balance and no 100 gems. Do not ante or roll.
          bankCents: 0,
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
    // New round: no banner from the last one (celebratory or not).
    _lastPayout = null;
    _log.add('— Round $_round — ante ${config.anteCents} gems —');

    // Collect ante from each seated player. Waiting chairs do not ante.
    for (var i = 0; i < _players.length; i++) {
      final p = _players[i];
      if (!_plays(p)) continue;
      final paid = _takeFromBank(i, config.anteCents, soft: true);
      _pot += paid;
      if (paid < config.anteCents) {
        _log.add('${p.profile.name} ante short ($paid gems).');
      }
    }
    if (_kickAfterAnte()) return;

    _seat = _firstActiveSeat(from: 0);
    _phase = MatchPhase.playing;
    _startTurn();
  }

  /// Jerilyn: bots are kicked any time they hit 0, including paying the
  /// ante. If that leaves one player, they take the pot. Returns true when
  /// the match ended.
  bool _kickAfterAnte() {
    final seated = [
      for (var i = 0; i < _players.length; i++)
        if (_plays(_players[i])) i,
    ];
    final kicked = _kickZeroedPayers(seated);
    if (kicked.isEmpty || _playableCount != 1) return false;
    final names = kicked.map((i) => _players[i].profile.name).join(', ');
    _sweepPotToLastPlayer(names, reason: 'paid the ante');
    return true;
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
    // New turn / set: the previous payout banner is stale. (A same-seat
    // win re-sets it right after this, so it shows on the winning roll.)
    _lastPayout = null;
    _log.add("${p.profile.name}'s turn.");
    _phase = MatchPhase.playing;
  }

  /// Human / external: toggle keep on a die (only after first roll).
  void toggleKeep(int index) {
    if (_phase == MatchPhase.awaitingHandoff ||
        _phase == MatchPhase.awaitingShortfall) {
      return;
    }
    final t = _turn;
    if (t == null || !t.hasRolled || t.rollNumber >= 3) return;
    if (_players[_seat].profile.isBot) return;
    _turn = t.copyWith(dice: t.dice.toggleKeep(index));
  }

  void setKeeps(List<bool> flags) {
    if (_phase == MatchPhase.awaitingHandoff ||
        _phase == MatchPhase.awaitingShortfall) {
      return;
    }
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
    if (!_plays(_players[_seat])) return;
    if (_phase == MatchPhase.awaitingHandoff ||
        _phase == MatchPhase.awaitingShortfall) {
      return;
    }
    final t = _turn;
    if (t == null) return;
    if (t.rollNumber >= 3) return;

    // A new roll starts: the previous hand's payout banner is stale now.
    _lastPayout = null;

    late DiceSet nextDice;
    final nextRoll = t.rollNumber + 1;
    if (!t.hasRolled) {
      nextDice = DiceSet.rollAll(rng);
    } else {
      nextDice = t.dice.roll(rng);
    }

    final score = HandEvaluator.evaluate(nextDice, rollNumber: nextRoll);
    // Snapshot which dice were carried into the final roll (and their faces)
    // before anything else can touch hold state.
    final carried = nextRoll == 3
        ? [for (final d in t.dice.dice) d.kept ? d.value : null]
        : null;
    _turn = t.copyWith(
      rollNumber: nextRoll,
      dice: nextDice,
      hasRolled: true,
      lastScore: score,
      carriedIntoFinal: carried,
      clearCarried: carried == null,
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
    if (_phase == MatchPhase.awaitingHandoff ||
        _phase == MatchPhase.awaitingShortfall) {
      return;
    }
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
      _resolveFirstRollTripleOnes();
      return;
    }

    if (score.isFirstRollTripsPay) {
      _resolveFirstRollTrips(score);
      return;
    }

    if (score.isScoring) {
      final paid = _collectFromOthers(score.perOpponentCents);
      final paidTotal = paid.values.fold<int>(0, (a, b) => a + b);
      _credit(_seat, paidTotal);
      final kicked = _kickZeroedPayers(paid.keys);
      if (kicked.isNotEmpty && _playableCount <= 1) {
        _sweepPotAfterKick(score, paid, kicked);
        return;
      }
      _lastPayout = PayoutEvent(
        message: _describeScore(
          player.profile.name,
          score,
          paidTotal,
          paid: paid,
          kicked: kicked,
        ),
        kind: score.kind,
        amountCents: paidTotal,
        celebratory: score.kind == ScoreKind.tripleOnesPay,
      );
      _log.add(_lastPayout!.message);
      if (_offerZeroBankChoice()) return;
      // Win banks, then this seat starts a fresh 3 rolls. Do not hand off.
      _continueSameSeatAfterWin(restartRound: false);
      return;
    } else if (t.rollNumber >= 3 && t.wentForTripleOnes) {
      _resolveMissedTripleOnes();
      return;
    } else if (t.rollNumber >= 3) {
      // Bust: put 2 gems in pot.
      final pen = HandEvaluator.bustPenalty.potPenaltyCents;
      final paid = _takeFromBank(_seat, pen, soft: true);
      _pot += paid;
      _lastPayout = PayoutEvent(
        message: '${player.profile.name} whiffs — $paid gems to the pot.',
        kind: ScoreKind.none,
        amountCents: paid,
      );
      _log.add(_lastPayout!.message);
      // Jerilyn: bots are kicked any time they hit 0, including a
      // no-score payment into the pot.
      final kicked = _kickZeroedPayers([_seat]);
      if (kicked.isNotEmpty && _playableCount == 1) {
        _sweepPotToLastPlayer(player.profile.name, reason: 'whiffs');
        return;
      }
      if (_playableCount <= 1) {
        _turn = null;
        _endMatch();
        return;
      }
    } else {
      // Guard: never advance on a no-score hand while rolls remain.
      _log.add('${player.profile.name} still has rolls left — keep rolling.');
      return;
    }

    _enterHandoff(restartsRound: false);
  }

  /// Gems each other seated player pays for first-roll triple 1s.
  static const firstRollOnesEach = 10;

  /// First-roll triple 1s: every other seated player pays the roller
  /// [firstRollOnesEach] gems (shortfall flow for humans who can't; bots pay
  /// what they can), then the roller wins the whole pot and the match ends.
  void _resolveFirstRollTripleOnes() {
    const due = firstRollOnesEach;
    final roller = _seat;
    _tripsCollected = 0;
    final humansShort = <int>[];
    for (var i = 0; i < _players.length; i++) {
      if (i == roller || !_plays(_players[i])) continue;
      final p = _players[i];
      if (p.bankCents >= due) {
        final paid = _takeFromBank(i, due, soft: false);
        _tripsCollected += paid;
        _credit(roller, paid);
        continue;
      }
      if (p.profile.isBot) {
        _payWhatTheyHaveAndQuit(i, roller);
        continue;
      }
      humansShort.add(i);
    }
    final name = _players[roller].profile.name;
    if (humansShort.isNotEmpty) {
      _lastPayout = PayoutEvent(
        message:
            '$name rolled three 1s on the first roll! Each other seated '
            'player owes ${gemCount(due)}. Collected '
            '${gemCount(_tripsCollected)} so far.',
        kind: ScoreKind.tripleOnesPotWin,
        amountCents: _tripsCollected,
        celebratory: true,
        diceValues: List<int>.unmodifiable(_turn!.dice.values),
        seatIndex: roller,
      );
      _shortfall = GemShortfall(
        payerSeatIndex: humansShort.first,
        rollerSeatIndex: roller,
        dueGems: due,
        face: 1,
        queuedSeatIndexes: humansShort.skip(1).toList(),
      );
      _phase = MatchPhase.awaitingShortfall;
      final payer = _players[humansShort.first];
      _log.add(
        '${payer.profile.name} cannot cover ${gemCount(due)} for three 1s. '
        'Choose: cover with bank gems, or spend '
        '${gemCount(payer.bankCents)} and quit this game.',
      );
      return;
    }
    _finishFirstRollTripleOnes();
  }

  /// Everyone has paid (or left): the roller takes the pot; match over.
  void _finishFirstRollTripleOnes() {
    final roller = _seat;
    final name = _players[roller].profile.name;
    final pot = _pot;
    _credit(roller, pot);
    _pot = 0;
    final collected = _tripsCollected;
    final message =
        '$name rolled three 1s on the first roll! '
        'Everyone pays ${gemCount(firstRollOnesEach)} and $name wins the pot.';
    _lastPayout = PayoutEvent(
      message: message,
      kind: ScoreKind.tripleOnesPotWin,
      amountCents: pot + collected,
      celebratory: true,
      diceValues: List<int>.unmodifiable(_turn!.dice.values),
      seatIndex: roller,
    );
    _log.add(
      '$message (+${gemCount(collected)} paid, '
      '+${gemCount(pot)} pot)',
    );
    final winnerId = _players[roller].profile.id;
    _endMatch();
    _winnerId = winnerId;
    _endMessage = message;
  }

  /// After a scoring bank: keep this seat and start a fresh 3-roll set.
  /// Does not apply to first-roll triple ones (that ends the round).
  /// First-roll three 2s–6s. Full payment from table gems, or a choice.
  /// Triple 1s never comes here. Waiting seats do not pay.
  void _resolveFirstRollTrips(ScoreResult score) {
    final due = score.perOpponentCents;
    final face = score.faceValue ?? 0;
    final roller = _seat;
    _tripsCollected = 0;
    final humansShort = <int>[];

    for (var i = 0; i < _players.length; i++) {
      if (i == roller || !_plays(_players[i])) continue;
      final p = _players[i];
      if (p.bankCents >= due) {
        final paid = _takeFromBank(i, due, soft: false);
        _tripsCollected += paid;
        _credit(roller, paid);
        continue;
      }
      if (p.profile.isBot) {
        _payWhatTheyHaveAndQuit(i, roller);
        continue;
      }
      humansShort.add(i);
    }

    _noteTripsPayout(score, waiting: humansShort.isNotEmpty);
    if (humansShort.isEmpty) {
      if (_kickAfterFirstRollTrips(score)) return;
      if (_offerZeroBankChoice()) return;
      _continueSameSeatAfterWin(restartRound: false);
      return;
    }
    _shortfall = GemShortfall(
      payerSeatIndex: humansShort.first,
      rollerSeatIndex: roller,
      dueGems: due,
      face: face,
      queuedSeatIndexes: humansShort.skip(1).toList(),
    );
    _phase = MatchPhase.awaitingShortfall;
    final payer = _players[humansShort.first];
    _log.add(
      '${payer.profile.name} cannot cover ${gemCount(due)} '
      'for three ${face}s. Choose: cover with bank gems, '
      'or spend ${gemCount(payer.bankCents)} and quit this game.',
    );
  }

  /// First-roll trips paid in full can still leave a payer at exactly 0:
  /// kick them; if nobody else is left, the roller sweeps the pot.
  bool _kickAfterFirstRollTrips(ScoreResult score) {
    final others = [
      for (var i = 0; i < _players.length; i++)
        if (i != _seat &&
            _players[i].profile.participates &&
            !_players[i].eliminated)
          i,
    ];
    final kicked = _kickZeroedPayers(others);
    if (kicked.isEmpty) return false;
    final names = kicked.map((i) => _players[i].profile.name).join(', ');
    if (_playableCount <= 1) {
      final roller = _seat;
      final name = _players[roller].profile.name;
      final pot = _pot;
      _credit(roller, pot);
      _pot = 0;
      final message =
          '${_lastPayout?.message ?? ''} $names is out of gems — '
          '$name wins the pot (${gemCount(pot)}).';
      _lastPayout = PayoutEvent(
        message: message.trim(),
        kind: ScoreKind.tripleOnesPotWin,
        amountCents: pot + _tripsCollected,
        celebratory: true,
        diceValues: List<int>.unmodifiable(_turn!.dice.values),
        seatIndex: roller,
      );
      _log.add(message);
      final winnerId = _players[roller].profile.id;
      _endMatch();
      _winnerId = winnerId;
      _endMessage = message.trim();
      return true;
    }
    final prev = _lastPayout!;
    _lastPayout = PayoutEvent(
      message: '${prev.message} $names is out of gems and out of the game.',
      kind: prev.kind,
      amountCents: prev.amountCents,
      celebratory: prev.celebratory,
    );
    return false;
  }

  void _noteTripsPayout(ScoreResult score, {required bool waiting}) {
    final name = _players[_seat].profile.name;
    final each = score.perOpponentCents;
    final face = score.faceValue;
    final message = waiting
        ? '$name hits three ${face}s on the first roll. '
              'Each other seated player owes ${gemCount(each)}. '
              'Collected ${gemCount(_tripsCollected)} so far.'
        : '$name hits three ${face}s on the first roll! '
              'Each other pays ${gemCount(each)}. '
              'Collects ${gemCount(_tripsCollected)}.';
    _lastPayout = PayoutEvent(
      message: message,
      kind: score.kind,
      amountCents: _tripsCollected,
      celebratory: false,
    );
    _log.add(message);
  }

  /// Gems into the pot when a player held two 1s for the 3rd roll and missed.
  static const missedOnesPenalty = 10;

  /// Missed triple ones: [missedOnesPenalty] into the pot instead of the
  /// normal bust. A hard take (like other 10-gem payments), so the House
  /// stake is not drawn; a human who is short gets the add-gems-or-leave
  /// choice, a bot pays what it has and is knocked out.
  void _resolveMissedTripleOnes() {
    const due = missedOnesPenalty;
    final p = _players[_seat];
    _tripsCollected = 0;
    if (p.bankCents >= due) {
      _pot += _takeFromBank(_seat, due, soft: false);
      // Jerilyn: bots are kicked any time they hit 0, including paying
      // a missed roll into the pot.
      _kickZeroedPayers([_seat]);
      _finishMissedTripleOnes(due);
      return;
    }
    if (p.profile.isBot) {
      final paid = p.bankCents;
      _payWhatTheyHaveAndQuit(_seat, _seat, toPot: true);
      _finishMissedTripleOnes(paid);
      return;
    }
    _shortfall = GemShortfall(
      payerSeatIndex: _seat,
      rollerSeatIndex: _seat,
      dueGems: due,
      face: 1,
      toPot: true,
    );
    _phase = MatchPhase.awaitingShortfall;
    _log.add(
      '${p.profile.name} missed triple ones and cannot cover '
      '${gemCount(due)} for the pot. Choose: cover with bank gems, or spend '
      '${gemCount(p.bankCents)} and quit this game.',
    );
  }

  void _finishMissedTripleOnes(int paid) {
    final name = _players[_seat].profile.name;
    _lastPayout = PayoutEvent(
      message: '$name missed triple ones — ${gemCount(paid)} to the pot.',
      kind: ScoreKind.none,
      amountCents: paid,
      missedTripleOnes: true,
    );
    _log.add(_lastPayout!.message);
    if (_players[_seat].eliminated && _playableCount == 1) {
      _sweepPotToLastPlayer(name);
      return;
    }
    if (_playableCount <= 1) {
      _turn = null;
      _endMatch();
      return;
    }
    _enterHandoff(restartsRound: false);
  }

  /// A bot paying a missed roll into the pot hit 0 and was kicked, leaving
  /// one player: that player takes the pot and the match ends.
  void _sweepPotToLastPlayer(
    String outName, {
    String reason = 'missed triple ones',
  }) {
    final winner = _players.indexWhere(
      (p) => p.profile.participates && !p.eliminated,
    );
    final name = _players[winner].profile.name;
    final pot = _pot;
    _credit(winner, pot);
    _pot = 0;
    final message =
        '$outName $reason and is out of gems — '
        '$name wins the pot (${gemCount(pot)}).';
    _lastPayout = PayoutEvent(
      message: message,
      kind: ScoreKind.tripleOnesPotWin,
      amountCents: pot,
      celebratory: true,
      seatIndex: winner,
    );
    _log.add(message);
    final winnerId = _players[winner].profile.id;
    _turn = null;
    _endMatch();
    _winnerId = winnerId;
    _endMessage = message;
  }

  /// Take this table's gems only. Leftover at this table is 0. Quit the game.
  /// [toPot]: the gems go into the pot instead of to [roller].
  void _payWhatTheyHaveAndQuit(int payer, int roller, {bool toPot = false}) {
    final p = _players[payer];
    final paid = p.bankCents;
    if (paid > 0) {
      _players[payer] = p.copyWith(bankCents: 0);
      _remember(payer);
      if (toPot) {
        _pot += paid;
      } else {
        _credit(roller, paid);
      }
      _tripsCollected += paid;
    } else {
      _players[payer] = p.copyWith(bankCents: 0);
    }
    final named = _players[payer];
    _players[payer] = named.copyWith(bankCents: 0, eliminated: true);
    _remember(payer);
    _log.add(
      '${named.profile.name} pays ${gemCount(paid)} and quits this game.',
    );
  }

  /// Human choice: pay whatever is at this table and leave this game.
  void quitShortfall() {
    final pending = _shortfall;
    if (pending == null || _phase != MatchPhase.awaitingShortfall) return;
    _payWhatTheyHaveAndQuit(
      pending.payerSeatIndex,
      pending.rollerSeatIndex,
      toPot: pending.toPot,
    );
    _advanceShortfall(pending);
  }

  /// Human choice: gems were moved onto this seat. Pay the full amount.
  /// Returns false if the table still cannot cover — nothing is taken.
  bool coverShortfall() {
    final pending = _shortfall;
    if (pending == null || _phase != MatchPhase.awaitingShortfall) return false;
    final payer = _players[pending.payerSeatIndex];
    if (payer.bankCents < pending.dueGems) return false;
    if (pending.zeroBank) {
      _log.add('${payer.profile.name} adds gems and stays in.');
      _advanceShortfall(pending);
      return true;
    }
    final paid = _takeFromBank(
      pending.payerSeatIndex,
      pending.dueGems,
      soft: false,
    );
    if (paid < pending.dueGems) return false;
    if (pending.toPot) {
      _pot += paid;
    } else {
      _credit(pending.rollerSeatIndex, paid);
    }
    _tripsCollected += paid;
    _log.add('${payer.profile.name} pays ${gemCount(paid)} in full.');
    _advanceShortfall(pending);
    return true;
  }

  void _advanceShortfall(GemShortfall pending) {
    if (pending.queuedSeatIndexes.isEmpty) {
      _shortfall = null;
      if (pending.toPot) {
        _finishMissedTripleOnes(_tripsCollected);
        return;
      }
      if (pending.zeroBank) {
        if (_playableCount <= 1) {
          _sweepPotToRoller(
            '${_players[pending.payerSeatIndex].profile.name} quits',
          );
          return;
        }
        _continueSameSeatAfterWin(restartRound: false);
        return;
      }
      final score = _turn?.lastScore;
      if (score != null && score.kind == ScoreKind.tripleOnesPotWin) {
        _finishFirstRollTripleOnes();
        return;
      }
      if (score != null && score.isFirstRollTripsPay) {
        _noteTripsPayout(score, waiting: false);
        if (_kickAfterFirstRollTrips(score)) return;
        if (_offerZeroBankChoice()) return;
      }
      _continueSameSeatAfterWin(restartRound: false);
      return;
    }
    final next = pending.queuedSeatIndexes.first;
    _shortfall = GemShortfall(
      payerSeatIndex: next,
      rollerSeatIndex: pending.rollerSeatIndex,
      dueGems: pending.dueGems,
      face: pending.face,
      queuedSeatIndexes: pending.queuedSeatIndexes.skip(1).toList(),
      zeroBank: pending.zeroBank,
    );
    _phase = MatchPhase.awaitingShortfall;
    final payer = _players[next];
    if (pending.zeroBank) {
      _log.add('${payer.profile.name} is at 0 gems. Buy more gems or quit.');
      return;
    }
    _log.add(
      '${payer.profile.name} cannot cover ${gemCount(pending.dueGems)} '
      'for three ${pending.face}s. Choose: cover with bank gems, '
      'or spend ${gemCount(payer.bankCents)} and quit this game.',
    );
  }

  void _continueSameSeatAfterWin({required bool restartRound}) {
    if (_playableCount <= 1) {
      _turn = null;
      _handoff = null;
      _shortfall = null;
      _tripsCollected = 0;
      _endMatch();
      return;
    }
    final payout = _lastPayout;
    final seat = _seat;
    _handoff = null;
    _shortfall = null;
    _tripsCollected = 0;
    if (restartRound) {
      _round++;
      _log.add('— Round $_round — ante ${config.anteCents} gems —');
      for (var i = 0; i < _players.length; i++) {
        final p = _players[i];
        if (!_plays(p)) continue;
        final paid = _takeFromBank(i, config.anteCents, soft: true);
        _pot += paid;
      }
      if (_kickAfterAnte()) return;
      if (_players[seat].eliminated) {
        _seat = _firstActiveSeat(from: seat);
      }
    }
    final prevSet = _turn?.setNumber ?? 1;
    _startTurn();
    if (!restartRound) _turn = _turn!.copyWith(setNumber: prevSet + 1);
    _lastPayout = payout;
    _log.add('${_players[_seat].profile.name} keeps the seat — fresh 3 rolls.');
  }

  String _describeScore(
    String name,
    ScoreResult score,
    int total, {
    Map<int, int> paid = const {},
    List<int> kicked = const [],
  }) {
    final each = payoutBreakdown(score.perOpponentCents, {
      for (final e in paid.entries) _players[e.key].profile.name: e.value,
    });
    var out = kicked.isEmpty
        ? ''
        : ' ${kicked.map((i) => _players[i].profile.name).join(', ')} '
              '${kicked.length == 1 ? 'is' : 'are'} out of gems and out of '
              'the game.';
    final zeroHumans = [
      for (final e in paid.entries)
        if (!_players[e.key].profile.isBot &&
            _players[e.key].bankCents == 0 &&
            !_players[e.key].eliminated)
          _players[e.key].profile.name,
    ];
    final broke = zeroHumans.isEmpty
        ? ''
        : ' ${zeroHumans.join(', ')} ${zeroHumans.length == 1 ? 'is' : 'are'} '
              'at 0 gems — buy more gems or quit.';
    out = '$out$broke';
    switch (score.kind) {
      case ScoreKind.tripleOnesPay:
        return '$name rolls triple ones! Collects $total gems ($each).$out';
      case ScoreKind.threeOfAKind:
        return '$name hits three ${score.faceValue}s! '
            'Collects $total gems ($each).$out';
      case ScoreKind.straight:
        return '$name nails a straight! Collects $total gems ($each).$out';
      case ScoreKind.tripleOnesPotWin:
        return '$name sweeps the pot!';
      case ScoreKind.none:
        return '$name scores nothing.';
    }
  }

  /// "10 gems each" when every payer covered [each]; otherwise names who
  /// paid short so the parenthetical always adds up to the collected total.
  static String payoutBreakdown(int each, Map<String, int> paidByName) {
    final short = paidByName.entries.where((e) => e.value < each).toList();
    if (short.isEmpty) return '$each gems each';
    final full = paidByName.length - short.length;
    final parts = <String>[
      if (full > 0)
        '$each gems each from ${full == 1 ? 'one player' : '$full players'}',
      for (final e in short) '${e.key} had only ${e.value} of $each',
    ];
    return parts.join('; ');
  }

  /// Seat index → gems actually paid, for every other seated player.
  Map<int, int> _collectFromOthers(int eachCents) {
    final out = <int, int>{};
    if (eachCents <= 0) return out;
    for (var i = 0; i < _players.length; i++) {
      if (i == _seat || !_plays(_players[i])) continue;
      out[i] = _takeFromBank(i, eachCents, soft: true);
    }
    return out;
  }

  /// Jerilyn's rule: a payout that leaves a player at 0 gems kicks them
  /// out of the game. Returns the seats kicked.
  List<int> _kickZeroedPayers(Iterable<int> payers) {
    final kicked = <int>[];
    for (final i in payers) {
      final p = _players[i];
      if (!p.profile.participates || p.bankCents > 0) continue;
      // Humans are never auto-kicked: they get buy-more-or-quit instead.
      if (!p.profile.isBot) continue;
      if (!p.eliminated) {
        _players[i] = p.copyWith(eliminated: true);
        _remember(i);
        _log.add('${p.profile.name} is at 0 gems — out of the game.');
      }
      kicked.add(i);
    }
    return kicked;
  }

  /// Humans (other than the roller) a payout left at exactly 0 gems get the
  /// existing shortfall dialog in "buy more gems or quit" mode. Returns true
  /// when the match now waits on that choice.
  bool _offerZeroBankChoice() {
    final zero = [
      for (var i = 0; i < _players.length; i++)
        if (i != _seat &&
            _plays(_players[i]) &&
            !_players[i].profile.isBot &&
            _players[i].bankCents == 0)
          i,
    ];
    if (zero.isEmpty) return false;
    _shortfall = GemShortfall(
      payerSeatIndex: zero.first,
      rollerSeatIndex: _seat,
      dueGems: config.anteCents,
      face: 0,
      queuedSeatIndexes: zero.skip(1).toList(),
      zeroBank: true,
    );
    _phase = MatchPhase.awaitingShortfall;
    _log.add(
      '${_players[zero.first].profile.name} is at 0 gems. '
      'Buy more gems or quit.',
    );
    return true;
  }

  /// A human at 0 quit and only the roller is left: roller takes the pot.
  void _sweepPotToRoller(String why) {
    final roller = _seat;
    final name = _players[roller].profile.name;
    final pot = _pot;
    _credit(roller, pot);
    _pot = 0;
    final message = '$why — $name wins the pot (${gemCount(pot)}).';
    _lastPayout = PayoutEvent(
      message: message,
      kind: ScoreKind.tripleOnesPotWin,
      amountCents: pot,
      celebratory: true,
      diceValues: _turn == null
          ? null
          : List<int>.unmodifiable(_turn!.dice.values),
      seatIndex: roller,
    );
    _log.add(message);
    final winnerId = _players[roller].profile.id;
    _endMatch();
    _winnerId = winnerId;
    _endMessage = message;
  }

  /// The last opponent was kicked by a payout: roller takes the pot and
  /// the match ends (same end path as a first-roll triple-ones sweep).
  void _sweepPotAfterKick(
    ScoreResult score,
    Map<int, int> paid,
    List<int> kicked,
  ) {
    final roller = _seat;
    final name = _players[roller].profile.name;
    final collected = paid.values.fold<int>(0, (a, b) => a + b);
    final pot = _pot;
    _credit(roller, pot);
    _pot = 0;
    final scoreLine = _describeScore(name, score, collected, paid: paid);
    final out = kicked.map((i) => _players[i].profile.name).join(', ');
    final message =
        '$scoreLine $out is out of gems — $name wins the pot '
        '(${gemCount(pot)}).';
    _lastPayout = PayoutEvent(
      message: message,
      kind: ScoreKind.tripleOnesPotWin,
      amountCents: pot + collected,
      celebratory: true,
      diceValues: List<int>.unmodifiable(_turn!.dice.values),
      seatIndex: roller,
    );
    _log.add(message);
    final winnerId = _players[roller].profile.id;
    _endMatch();
    _winnerId = winnerId;
    _endMessage = message;
  }

  void _credit(int index, int cents) {
    if (cents <= 0) return;
    if (!_players[index].profile.participates) return;
    final p = _players[index];
    _players[index] = p.copyWith(bankCents: p.bankCents + cents);
    _remember(index);
  }

  /// Gems the House fronted this seat at this table (once per match).
  /// The House stake is created by the House, not taken from the pot or
  /// another player, so it is repaid when the table cashes out to the gem
  /// bank (see SavedGameStore.returnLocalGems).
  static int houseStakeOwed(PlayerState p, MatchConfig config) =>
      p.usedHouseStake && config.houseStakeCents > 0
      ? config.houseStakeCents
      : 0;

  /// Soft take: apply house stake once if needed; never go negative.
  int _takeFromBank(int index, int amount, {required bool soft}) {
    if (amount <= 0) return 0;
    var p = _players[index];
    if (p.eliminated) return 0;
    if (!p.profile.participates) return 0;

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
        '+${config.houseStakeCents} gems (once).',
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
      _log.add('${p.profile.name} is out of gems.');
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
        return payout.missedTripleOnes ? 'Missed triple ones' : 'Bust';
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
      _shortfall = null;
      _tripsCollected = 0;
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
    _shortfall = null;
    _tripsCollected = 0;
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
    _shortfall = null;
    _tripsCollected = 0;
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
      'with ${sorted.first.bankCents} gems.',
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

  /// Freeze this table so it can be resumed without a new ante.
  MatchCheckpoint capture() => MatchCheckpoint(
    phase: _phase,
    players: List<PlayerState>.from(_players),
    potCents: _pot,
    roundNumber: _round,
    currentSeatIndex: _seat,
    config: config,
    turn: _turn,
    handoff: _handoff,
    log: List<String>.from(_log),
    lastPayout: _lastPayout,
    winnerId: _winnerId,
    pendingShortfall: _shortfall,
  );

  /// Restore a saved table exactly. Does not ante, and does not reset banks.
  void restore(MatchCheckpoint saved) {
    _players = List<PlayerState>.from(saved.players);
    _pot = saved.potCents;
    _round = saved.roundNumber;
    _seat = saved.currentSeatIndex.clamp(0, _players.length - 1);
    _phase = saved.phase;
    _turn = saved.turn;
    _handoff = saved.handoff;
    _shortfall = saved.pendingShortfall;
    _tripsCollected = saved.lastPayout?.amountCents ?? 0;
    _log
      ..clear()
      ..addAll(saved.log);
    _lastPayout = saved.lastPayout;
    _winnerId = saved.winnerId;
    for (var i = 0; i < _players.length; i++) {
      _remember(i);
    }
    if (_phase == MatchPhase.playing &&
        _turn == null &&
        _plays(_players[_seat])) {
      _startTurn();
    }
  }
}
