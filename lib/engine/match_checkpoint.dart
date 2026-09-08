import 'dice.dart';
import 'gem_label.dart';
import 'gem_shortfall.dart';
import 'hand_evaluator.dart';
import 'match_controller.dart';
import 'player.dart';
import 'turn_state.dart';

/// Enough of a live table to resume later without re-ante or a fresh 100¢.
///
/// Each checkpoint is one table: its pot, seats, and those players' totals.
/// It does not share a pot or seated banks with any other unfinished game.
class MatchCheckpoint {
  const MatchCheckpoint({
    required this.phase,
    required this.players,
    required this.potCents,
    required this.roundNumber,
    required this.currentSeatIndex,
    required this.config,
    this.turn,
    this.handoff,
    this.log = const [],
    this.lastPayout,
    this.winnerId,
    this.pendingShortfall,
  });

  final MatchPhase phase;
  final List<PlayerState> players;
  final int potCents;
  final int roundNumber;
  final int currentSeatIndex;
  final MatchConfig config;
  final TurnState? turn;
  final HandoffState? handoff;
  final List<String> log;
  final PayoutEvent? lastPayout;
  final String? winnerId;
  final GemShortfall? pendingShortfall;

  bool get isUnfinished =>
      phase != MatchPhase.matchEnd && phase != MatchPhase.setup;

  PlayerState? get localPlayer {
    for (final p in players) {
      if (p.profile.id == 'human_0') return p;
    }
    for (final p in players) {
      if (p.profile.isHuman) return p;
    }
    return null;
  }

  int get localBankCents => localPlayer?.bankCents ?? 0;

  String get localName => localPlayer?.profile.name ?? config.localPlayerName;

  String get currentSeatName {
    if (players.isEmpty) return localName;
    final i = currentSeatIndex.clamp(0, players.length - 1);
    return players[i].profile.name;
  }

  /// Short lobby line. Pot and the local seated bank, not a reset stake.
  String get resumeLine {
    final you = localPlayer;
    final youBit = you == null
        ? ''
        : ' · ${you.profile.name} ${gemCount(you.bankCents)}';
    return 'Round $roundNumber · pot ${gemCount(potCents)}$youBit';
  }

  String get seatSummary {
    final parts = <String>[localName];
    if (config.otherHumanCount > 0) {
      parts.add(
        '${config.otherHumanCount} human${config.otherHumanCount == 1 ? '' : 's'}',
      );
    }
    if (config.friendCount > 0) {
      parts.add(
        '${config.friendCount} friend${config.friendCount == 1 ? '' : 's'}',
      );
    }
    if (config.onlinePlayerCount > 0) {
      parts.add('${config.onlinePlayerCount} waiting');
    }
    if (config.botCount > 0) {
      parts.add('${config.botCount} bot${config.botCount == 1 ? '' : 's'}');
    }
    return parts.join(' + ');
  }

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'players': players.map(_playerToJson).toList(),
    'potCents': potCents,
    'roundNumber': roundNumber,
    'currentSeatIndex': currentSeatIndex,
    'config': _configToJson(config),
    if (turn != null) 'turn': _turnToJson(turn!),
    if (handoff != null) 'handoff': _handoffToJson(handoff!),
    'log': log,
    if (lastPayout != null) 'lastPayout': _payoutToJson(lastPayout!),
    if (winnerId != null) 'winnerId': winnerId,
    if (pendingShortfall != null)
      'pendingShortfall': pendingShortfall!.toJson(),
  };

  static MatchCheckpoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final phase = _phase(raw['phase']);
    final config = _configFromJson(raw['config']);
    final playersRaw = raw['players'];
    if (phase == null || config == null || playersRaw is! List) return null;
    final players = <PlayerState>[
      for (final item in playersRaw)
        if (_playerFromJson(item) case final p?) p,
    ];
    if (players.isEmpty) return null;
    final pot = _asInt(raw['potCents']) ?? 0;
    final round = _asInt(raw['roundNumber']) ?? 1;
    final seat = _asInt(raw['currentSeatIndex']) ?? 0;
    final logRaw = raw['log'];
    final log = <String>[
      if (logRaw is List)
        for (final line in logRaw)
          if (line is String) line,
    ];
    return MatchCheckpoint(
      phase: phase,
      players: players,
      potCents: pot,
      roundNumber: round,
      currentSeatIndex: seat.clamp(0, players.length - 1),
      config: config,
      turn: _turnFromJson(raw['turn']),
      handoff: _handoffFromJson(raw['handoff']),
      log: log,
      lastPayout: _payoutFromJson(raw['lastPayout']),
      winnerId: raw['winnerId'] is String ? raw['winnerId'] as String : null,
      pendingShortfall: GemShortfall.fromJson(raw['pendingShortfall']),
    );
  }

  static Map<String, Object?> _playerToJson(PlayerState p) => {
    'id': p.profile.id,
    'name': p.profile.name,
    'kind': p.profile.kind.name,
    if (p.profile.personality != null)
      'personality': p.profile.personality!.name,
    'avatarEmoji': p.profile.avatarEmoji,
    'colorSeed': p.profile.colorSeed,
    'bankCents': p.bankCents,
    'usedHouseStake': p.usedHouseStake,
    'eliminated': p.eliminated,
  };

  static PlayerState? _playerFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final kind = _seatKind(raw['kind']);
    if (id is! String || name is! String || kind == null) return null;
    return PlayerState(
      profile: PlayerProfile(
        id: id,
        name: name,
        kind: kind,
        personality: _personality(raw['personality']),
        avatarEmoji: raw['avatarEmoji'] is String
            ? raw['avatarEmoji'] as String
            : '🎲',
        colorSeed: _asInt(raw['colorSeed']) ?? 0,
      ),
      bankCents: _asInt(raw['bankCents']) ?? 0,
      usedHouseStake: raw['usedHouseStake'] == true,
      eliminated: raw['eliminated'] == true,
    );
  }

  static Map<String, Object?> _configToJson(MatchConfig c) => {
    'botCount': c.botCount,
    'otherHumanCount': c.otherHumanCount,
    'onlinePlayerCount': c.onlinePlayerCount,
    'friendNames': c.friendNames,
    'startBankCents': c.startBankCents,
    'anteCents': c.anteCents,
    'houseStakeCents': c.houseStakeCents,
    'localPlayerName': c.localPlayerName,
    if (c.humanNames != null) 'humanNames': c.humanNames,
  };

  static MatchConfig? _configFromJson(Object? raw) {
    if (raw is! Map) return null;
    final friendsRaw = raw['friendNames'];
    final humansRaw = raw['humanNames'];
    return MatchConfig(
      botCount: _asInt(raw['botCount']) ?? 0,
      otherHumanCount: _asInt(raw['otherHumanCount']) ?? 0,
      onlinePlayerCount: _asInt(raw['onlinePlayerCount']) ?? 0,
      friendNames: friendsRaw is List
          ? [
              for (final n in friendsRaw)
                if (n is String) n,
            ]
          : const [],
      startBankCents: _asInt(raw['startBankCents']) ?? 100,
      anteCents: _asInt(raw['anteCents']) ?? 10,
      houseStakeCents: _asInt(raw['houseStakeCents']) ?? 50,
      localPlayerName: raw['localPlayerName'] is String
          ? raw['localPlayerName'] as String
          : 'You',
      humanNames: humansRaw is List
          ? [
              for (final n in humansRaw)
                if (n is String) n,
            ]
          : null,
    );
  }

  static Map<String, Object?> _turnToJson(TurnState t) => {
    'playerId': t.playerId,
    'rollNumber': t.rollNumber,
    'hasRolled': t.hasRolled,
    'values': t.dice.values,
    'kept': t.dice.keptFlags,
    'score': _scoreToJson(t.lastScore),
  };

  static TurnState? _turnFromJson(Object? raw) {
    if (raw is! Map) return null;
    final playerId = raw['playerId'];
    if (playerId is! String || playerId.isEmpty) return null;
    final valuesRaw = raw['values'];
    final keptRaw = raw['kept'];
    final values = valuesRaw is List
        ? [
            for (final v in valuesRaw)
              if (_asInt(v) != null) _asInt(v)!,
          ]
        : const <int>[];
    final kept = keptRaw is List
        ? [for (final v in keptRaw) v == true]
        : const <bool>[];
    final dice = values.length == 3
        ? DiceSet.fromValues(values, kept: kept.length == 3 ? kept : null)
        : DiceSet.blank();
    return TurnState(
      playerId: playerId,
      rollNumber: _asInt(raw['rollNumber']) ?? 0,
      dice: dice,
      hasRolled: raw['hasRolled'] == true,
      lastScore: _scoreFromJson(raw['score']) ?? ScoreResult.none,
    );
  }

  static Map<String, Object?> _handoffToJson(HandoffState h) => {
    'diceValues': h.diceValues,
    'outcomeText': h.outcomeText,
    'bankDeltaCents': h.bankDeltaCents,
    'fromSeatIndex': h.fromSeatIndex,
    'nextSeatIndex': h.nextSeatIndex,
    'restartsRound': h.restartsRound,
    'kind': h.kind.name,
  };

  static HandoffState? _handoffFromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = _scoreKind(raw['kind']);
    final valuesRaw = raw['diceValues'];
    if (kind == null || valuesRaw is! List) return null;
    final values = [
      for (final v in valuesRaw)
        if (_asInt(v) != null) _asInt(v)!,
    ];
    if (values.length != 3) return null;
    return HandoffState(
      diceValues: values,
      outcomeText: raw['outcomeText'] is String
          ? raw['outcomeText'] as String
          : '',
      bankDeltaCents: _asInt(raw['bankDeltaCents']) ?? 0,
      fromSeatIndex: _asInt(raw['fromSeatIndex']) ?? 0,
      nextSeatIndex: _asInt(raw['nextSeatIndex']) ?? 0,
      restartsRound: raw['restartsRound'] == true,
      kind: kind,
    );
  }

  static Map<String, Object?> _payoutToJson(PayoutEvent p) => {
    'message': p.message,
    'kind': p.kind.name,
    'amountCents': p.amountCents,
    'celebratory': p.celebratory,
  };

  static PayoutEvent? _payoutFromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = _scoreKind(raw['kind']);
    final message = raw['message'];
    if (kind == null || message is! String) return null;
    return PayoutEvent(
      message: message,
      kind: kind,
      amountCents: _asInt(raw['amountCents']) ?? 0,
      celebratory: raw['celebratory'] == true,
    );
  }

  static Map<String, Object?> _scoreToJson(ScoreResult s) => {
    'kind': s.kind.name,
    if (s.faceValue != null) 'faceValue': s.faceValue,
    'perOpponentCents': s.perOpponentCents,
    'takesPot': s.takesPot,
    'potPenaltyCents': s.potPenaltyCents,
    'bankedOnly': s.bankedOnly,
  };

  static ScoreResult? _scoreFromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = _scoreKind(raw['kind']);
    if (kind == null) return null;
    return ScoreResult(
      kind: kind,
      faceValue: _asInt(raw['faceValue']),
      perOpponentCents: _asInt(raw['perOpponentCents']) ?? 0,
      takesPot: raw['takesPot'] == true,
      potPenaltyCents: _asInt(raw['potPenaltyCents']) ?? 0,
      bankedOnly: raw['bankedOnly'] == true,
    );
  }

  static MatchPhase? _phase(Object? raw) {
    if (raw is! String) return null;
    for (final p in MatchPhase.values) {
      if (p.name == raw) return p;
    }
    return null;
  }

  static SeatKind? _seatKind(Object? raw) {
    if (raw is! String) return null;
    for (final k in SeatKind.values) {
      if (k.name == raw) return k;
    }
    return null;
  }

  static BotPersonality? _personality(Object? raw) {
    if (raw is! String) return null;
    for (final p in BotPersonality.values) {
      if (p.name == raw) return p;
    }
    return null;
  }

  static ScoreKind? _scoreKind(Object? raw) {
    if (raw is! String) return null;
    for (final k in ScoreKind.values) {
      if (k.name == raw) return k;
    }
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}
