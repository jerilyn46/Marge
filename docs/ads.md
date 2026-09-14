# AdMob + Play Billing (virtual gems)

**Kill switch:** AdMob is **off by default**. Dart `ADMOB_ENABLED` defaults to false (no `MobileAds.initialize`, UMP, banner, interstitial, or rewarded). Android leaves `APPLICATION_ID` removed unless `-PADMOB_ENABLED=true`, and always strips `MobileAdsInitProvider` so GMA cannot cold-start before Flutter. Enable monetization builds with **both**:

```bash
--dart-define=ADMOB_ENABLED=true -PADMOB_ENABLED=true
```

Unit / App IDs default to Google **test** samples. Inject real IDs only at build time — never commit them.

Package: `com.jerilyn.marge`  
Plugins: `google_mobile_ads`, `in_app_purchase`

> Virtual gems only. No real-money cash-out, side bets, loot chests, or dark patterns.

## Placement rules

| Format | Where | Notes |
|--------|--------|--------|
| Banner | Lobby reserved strip (`HomeScreen`) only | Never over active dice / Roll / Keep |
| Interstitial | Match end (≤1 per completed match) | Never mid-roll; never cold-start; never back-to-back on same break |
| Rewarded | Shop — “Watch for gems” | Credits **main gem bank** (+25) |
| App-open | **Out of scope** | Not implemented |

Fail closed: consent / SDK errors leave ads off.

## UMP consent

On supported mobile platforms, `AdsService.bootstrap()` runs **User Messaging Platform** before initializing `MobileAds`. Personalized requests are gated with `canRequestAds()`.

**Startup:** `main()` calls `runApp` first, then schedules `bootstrap()` after the first frame. Never await MobileAds/UMP before the lobby.

Settings → **Privacy / ad consent** opens the UMP privacy options form when required.

## Dart-define keys (ad unit IDs)

| Key | Purpose | Default (Google test) |
|-----|---------|------------------------|
| `ADMOB_BANNER_ID` | Banner unit | `ca-app-pub-3940256099942544/6300978111` |
| `ADMOB_INTERSTITIAL_ID` | Interstitial unit | `ca-app-pub-3940256099942544/1033173712` |
| `ADMOB_REWARDED_ID` | Rewarded unit | `ca-app-pub-3940256099942544/5224354917` |
| `ADMOB_APP_ID` | Documented App ID mirror | `ca-app-pub-3940256099942544~3347511713` |

Resolved in Dart by `lib/ads/ad_ids.dart`. Empty defines fall back to the test IDs above.

## Android App ID (manifest)

`AndroidManifest.xml` uses placeholder `${admobAppId}` with `tools:node="${admobAppIdNode}"`.

`android/app/build.gradle.kts` sets:

- **Default (`ADMOB_ENABLED` unset/false):** `tools:node=remove` — APPLICATION_ID absent
- **`-PADMOB_ENABLED=true`:** merge Google sample App ID (or `-PADMOB_APP_ID=`)
- **Override IDs:** Gradle property `ADMOB_APP_ID` (do not commit real values)

```bash
# Monetization / Tester build with Google test IDs
flutter build appbundle --release \
  --dart-define=ADMOB_ENABLED=true \
  -PADMOB_ENABLED=true

# Production IDs (CI secrets only — never in git)
flutter build appbundle --release \
  --dart-define=ADMOB_ENABLED=true \
  --dart-define=ADMOB_BANNER_ID="$PROD_BANNER" \
  --dart-define=ADMOB_INTERSTITIAL_ID="$PROD_INTERSTITIAL" \
  --dart-define=ADMOB_REWARDED_ID="$PROD_REWARDED" \
  -PADMOB_ENABLED=true \
  -PADMOB_APP_ID="$PROD_APP_ID"
```

## Play Billing gem packs

SKUs (consumable) credit the **main gem bank** (`PlayerCoinLedger`). Free daily drip stays separate.

| Product ID | Gems |
|------------|------|
| `marge_gems_small` | 100 |
| `marge_gems_medium` | 500 |
| `marge_gems_large` | 1200 |

See `lib/services/gem_iap.dart`. Clear Shop copy: virtual gems, not real money, no cash-out.

## Rematch

After pot is settled at match end: stay on table, one **Rematch** (same seats / ante, one tap, no ready-check). **Leave table** quietly returns home. Stop-and-pass stays off.

## Code map

```
lib/ads/
  ad_ids.dart             dart-define + Google test defaults
  interstitial_gate.dart  ≤1 interstitial per completed match
  ads_service.dart        UMP + MobileAds + interstitial/rewarded (fail closed)
  banner_ad_widget.dart   Lobby-only banner
lib/services/gem_iap.dart Play Billing packs → gem bank
lib/ui/widgets/reserved_banner_strip.dart  banner or house-art fallback
```
