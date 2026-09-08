enum SeatKind { human, bot, waiting }

/// Reserved online chair with nobody joined. Not a bot and not a person.
class WaitingSeat {
  static const name = 'Waiting for player';
  static const emoji = '⏳';
}

enum BotPersonality { aggressive, cautious, chaotic }

class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.name,
    required this.kind,
    this.personality,
    this.avatarEmoji = '🎲',
    this.colorSeed = 0,
  });

  final String id;
  final String name;
  final SeatKind kind;
  final BotPersonality? personality;
  final String avatarEmoji;
  final int colorSeed;

  bool get isHuman => kind == SeatKind.human;
  bool get isBot => kind == SeatKind.bot;
  bool get isWaiting => kind == SeatKind.waiting;

  /// Humans and bots play. Waiting chairs do not roll, ante, or pay.
  bool get participates => isHuman || isBot;

  PlayerProfile copyWith({
    String? name,
    SeatKind? kind,
    BotPersonality? personality,
    String? avatarEmoji,
    int? colorSeed,
  }) => PlayerProfile(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    personality: personality ?? this.personality,
    avatarEmoji: avatarEmoji ?? this.avatarEmoji,
    colorSeed: colorSeed ?? this.colorSeed,
  );
}

class PlayerState {
  const PlayerState({
    required this.profile,
    required this.bankCents,
    this.usedHouseStake = false,
    this.eliminated = false,
  });

  final PlayerProfile profile;
  final int bankCents;
  final bool usedHouseStake;
  final bool eliminated;

  PlayerState copyWith({
    PlayerProfile? profile,
    int? bankCents,
    bool? usedHouseStake,
    bool? eliminated,
  }) => PlayerState(
    profile: profile ?? this.profile,
    bankCents: bankCents ?? this.bankCents,
    usedHouseStake: usedHouseStake ?? this.usedHouseStake,
    eliminated: eliminated ?? this.eliminated,
  );
}

/// Default bot roster with distinct names / avatars.
class BotRoster {
  static const bots = <PlayerProfile>[
    PlayerProfile(
      id: 'bot_spike',
      name: 'Spike',
      kind: SeatKind.bot,
      personality: BotPersonality.aggressive,
      avatarEmoji: '🔥',
      colorSeed: 1,
    ),
    PlayerProfile(
      id: 'bot_mira',
      name: 'Mira',
      kind: SeatKind.bot,
      personality: BotPersonality.cautious,
      avatarEmoji: '🧊',
      colorSeed: 2,
    ),
    PlayerProfile(
      id: 'bot_zig',
      name: 'Zig',
      kind: SeatKind.bot,
      personality: BotPersonality.chaotic,
      avatarEmoji: '⚡',
      colorSeed: 3,
    ),
    PlayerProfile(
      id: 'bot_nova',
      name: 'Nova',
      kind: SeatKind.bot,
      personality: BotPersonality.aggressive,
      avatarEmoji: '🌟',
      colorSeed: 4,
    ),
  ];

  static const extraEmojis = <String>['🎯', '🃏', '🐉'];

  /// Display name for bot index 0..n. Matches the table roster.
  static String nameAt(int botIdx) {
    if (botIdx < bots.length) return bots[botIdx].name;
    return 'Bot ${botIdx + 1}';
  }

  static String emojiAt(int botIdx) {
    if (botIdx < bots.length) return bots[botIdx].avatarEmoji;
    return extraEmojis[botIdx % extraEmojis.length];
  }
}
