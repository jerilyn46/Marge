# Marge (Marge Dice Game)

A colorful casual dice table game for Android (and web). Configurable seats (bots + local hotseat), ante into a shared pot, Yahtzee-style keep-and-reroll, and a dramatic **triple ones on the first roll** pot sweep.

**Package:** `com.jerilyn.marge`  
**Repo:** https://github.com/jerilyn46/Marge

> Virtual chips only. No real-money gambling.

## Rules

- **2–8 seats.** Lobby: **you**, then **0–4 other hotseat humans**, then **0–4 online seats**, then **0–4 bots** filling leftover seats only (at least 1 playable opponent). Default: **3 bots, 0 other humans, 0 online**. There is no live matchmaking; chosen online seats stay **Waiting for player** and are never converted into bots.
- **Start bank:** each identity keeps its saved coins (100¢ if new). Humans and friends persist forever. Bots reset to 100¢ every Monday 00:00 America/Denver.
- **Round ante:** each playing seat pays **10¢** into the pot. Waiting online chairs do not ante.
- **Turn:** 3 dice, up to **3 rolls**. Keep any subset between rolls. Bank early once you have a scoring hand.
- **Scoring priority**
  1. Three 1s on the **first** roll of the turn → win the **entire pot**; new round with ante.
  2. Three 1s on roll 2/3 → each other player pays you **10¢**.
  3. Other three-of-a-kind → each other pays **face value** ¢.
  4. Straight `{1,2,3}` / `{2,3,4}` / `{3,4,5}` / `{4,5,6}` → each other pays **5¢**.
  5. No score after 3 rolls → put **2¢** in the pot.
- **Soft bankrupt:** once per match the House tops you up **50¢**.
- Endless rounds. **End match** shows final banks and a winner.

Bots: **Spike** (aggressive), **Mira** (cautious), **Zig** (chaotic).

## Run

```bash
export PATH="/home/box/sdk/flutter/bin:$PATH"   # or your Flutter SDK
cd marge
flutter pub get
flutter run -d chrome          # or a device / emulator
flutter run -d web-server --web-port 8080
```

### Tests & analyze

```bash
flutter analyze
flutter test
```

### Web build

```bash
flutter build web
# output: build/web/
```

### Android APK / AAB

Requires Android SDK / cmdline-tools configured.

```bash
flutter build apk --release
flutter build appbundle --release
# APK: build/app/outputs/flutter-apk/app-release.apk
# AAB: build/app/outputs/bundle/release/app-release.aab
```

See `docs/store/` for Play listing placeholders.

## Ads (AdMob test scaffolding)

See **[docs/ads.md](docs/ads.md)** for dart-define keys, Android App ID injection, UMP consent, and Tester how-to.

Defaults use Google’s official **test** App ID and unit IDs. Do not commit production AdMob IDs.

```bash
# Ads test APK (Google test IDs by default)
export PATH="/home/box/sdk/flutter/bin:$PATH"
source /home/box/sdk/android-env.sh   # if present
flutter build apk --debug
# APK: build/app/outputs/flutter-apk/app-debug.apk
```


## Architecture

```
lib/
  engine/          Pure Dart game logic (no Flutter)
    dice.dart
    hand_evaluator.dart
    turn_state.dart
    player.dart
    bot_ai.dart
    match_controller.dart
  services/        Settings, coin ledger, friends, local turn notices
  ads/             AdMob test IDs, UMP consent, banner/interstitial/rewarded
  ui/
    theme/         Material 3 casual palette
    widgets/       Dice, pot heat meter, banners, confetti
    screens/       Home, match table, rules, settings
    match_provider.dart
  main.dart
test/engine/       Unit tests for scoring + match flow
```

State: **flutter_riverpod**. Persistence: **shared_preferences**. Fonts: **google_fonts**.

## Polish

- Distinct bot names / emoji avatars
- Pot heat meter
- Confetti + stinger placeholder on pot win
- Rematch from end screen
- SFX / haptics toggles (haptics no-op on Linux/web)

## License

Personal / portfolio project unless otherwise noted.
