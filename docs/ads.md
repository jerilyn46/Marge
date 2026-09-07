# AdMob test scaffolding

Marge ships with **Google official test / sample AdMob IDs** by default. Production App ID and unit IDs must be injected at build time — never committed.

Package: `com.jerilyn.marge`  
Plugin: `google_mobile_ads` (see `pubspec.yaml`)

> Virtual chips only. Rewarded ads grant cosmetics-wallet ¢ — not real money.

## Placement rules

| Format | Where | Notes |
|--------|--------|--------|
| Banner | Main menu / lobby (`HomeScreen`) only | Never over active dice / roll UI |
| Interstitial | Match end / return to lobby | Max ~1 per 2–3 completed matches; never back-to-back; never mid-roll |
| Rewarded | Dice shop — “Watch ad for +N¢” | Grants virtual chips via `CosmeticsNotifier.grantVirtualChips` |
| App-open | **Out of scope** | Not implemented |

## UMP consent

On supported mobile platforms, `AdsService.bootstrap()` runs **User Messaging Platform** (`ConsentInformation` / `ConsentForm`) before initializing `MobileAds` and loading ads. Personalized ad requests are gated with `canRequestAds()`.

**Startup:** `main()` calls `runApp` first, then schedules `bootstrap()` after the first frame (try/catch). Never await MobileAds/UMP before the lobby — cold-start on Android (e.g. Flip 7) crashed when consent ran with no ready Activity.

Settings → **Privacy / ad consent** opens the UMP privacy options form when required (EU/EEA/UK message types).

## Dart-define keys (ad unit IDs)

| Key | Purpose | Default (Google test) |
|-----|---------|------------------------|
| `ADMOB_BANNER_ID` | Banner unit | `ca-app-pub-3940256099942544/6300978111` |
| `ADMOB_INTERSTITIAL_ID` | Interstitial unit | `ca-app-pub-3940256099942544/1033173712` |
| `ADMOB_REWARDED_ID` | Rewarded unit | `ca-app-pub-3940256099942544/5224354917` |
| `ADMOB_APP_ID` | Documented App ID mirror | `ca-app-pub-3940256099942544~3347511713` |

Resolved in Dart by `lib/ads/ad_ids.dart`. Empty defines fall back to the test IDs above.

## Android App ID (manifest)

`AndroidManifest.xml` uses placeholder `${admobAppId}`.

`android/app/build.gradle.kts` sets:

- **Default:** Google sample App ID `ca-app-pub-3940256099942544~3347511713`
- **Override:** Gradle property `ADMOB_APP_ID` (do not commit real values)

```bash
# Test APK (defaults — recommended for Tester)
flutter build apk --debug

# Or explicitly pass test IDs
flutter build apk --debug \
  --dart-define=ADMOB_BANNER_ID=ca-app-pub-3940256099942544/6300978111 \
  --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-3940256099942544/1033173712 \
  --dart-define=ADMOB_REWARDED_ID=ca-app-pub-3940256099942544/5224354917 \
  -PADMOB_APP_ID=ca-app-pub-3940256099942544~3347511713
```

Production (local / CI secrets only — never in git):

```bash
flutter build apk --release \
  --dart-define=ADMOB_BANNER_ID="$PROD_BANNER" \
  --dart-define=ADMOB_INTERSTITIAL_ID="$PROD_INTERSTITIAL" \
  --dart-define=ADMOB_REWARDED_ID="$PROD_REWARDED" \
  -PADMOB_APP_ID="$PROD_APP_ID"
```

APK output: `build/app/outputs/flutter-apk/app-debug.apk` (or `app-release.apk`).

## Tester how-to

1. Build the debug APK with defaults (test IDs).
2. Install on an Android device / emulator with Google Play services.
3. Cold-start the app — UMP may show a consent form in EEA/UK (or use AdMob debug geography while developing).
4. **Lobby:** confirm a test banner at the bottom of the home screen.
5. **Shop:** tap **Watch ad for +25¢** — complete the rewarded test ad; wallet should increase by 25¢.
6. **Interstitial:** finish **2–3 matches** (End match → standings). An interstitial may appear at match end / when returning home; the next match end should not show back-to-back.
7. Confirm **no banner** on the active dice table during rolls.

## Code map

```
lib/ads/
  ad_ids.dart           dart-define + Google test defaults
  interstitial_gate.dart  2–3 match frequency helper
  ads_service.dart      UMP + MobileAds + interstitial/rewarded
  banner_ad_widget.dart Lobby-only banner
```
