# Remote multiplayer — invite / room-code MVP (Firebase)

Status: **WIP — match loop implemented, emulator-ready; Functions deploy blocked on Blaze.** Firebase project `marge-online` exists (Anonymous Auth + Firestore nam5 on; Android app registered; `google-services.json` on the build box only). `.firebaserc` default = `marge-online`. Approved shape: invite/room code, Firebase (Auth + Firestore + Cloud Functions), anonymous auth, server-checked gems. Invite-only. **No chat.**

Feature flag: `--dart-define=MARGE_ONLINE_INVITE=true` (off by default; Production builds unchanged). Local hotseat + bots, offline SharedPreferences gem bank, Ads/IAP: unchanged.

## Room flow
1. Player taps **PLAY ONLINE (INVITE)** on Setup (separate entry; does not use the legacy Online seat stepper).
2. Firebase initialises lazily + anonymous sign-in (never at app startup).
3. Host: `createRoom(seatCount, botCount, ante, displayName, clientGemClaim)` → 6-char code (alphabet without 0/O/1/I). Host shares code out-of-band.
4. Guest: `joinRoom(code, ...)` → takes first open seat.
5. Bots only in the leftover seats the host configured; **open human seats are never auto-filled with bots**.
6. Host `startMatch` → server debits antes, builds pot, owns dice/turns. Clients call `submitRoll` / `submitKeep`; server validates `expectedVersion` + turn ownership, advances, runs bot seats, and `resolveTurn` pays out.

## Firestore schema
- `users/{uid}`: `gems` (server-owned), `seededFromClaim`, `displayName`, `createdAt`. Client read-own only.
- `roomCodes/{code}`: `roomId`, `createdAt`.
- `rooms/{roomId}`: `code, hostUid, status(lobby|playing|finished|abandoned), ante, pot, turnSeat, version, memberUids[], seats[{index, kind(host|human|bot|open), uid?, displayName?, connected}], lastActivity`. Members read; nobody writes from client.
- `rooms/{roomId}/private/state`: dice, RNG, turn order — server only.
- Rules: `firestore.rules` (all client writes denied).

## Cloud Functions (`functions/src/`)
Rules engine: `functions/src/engine.ts` — pure TS port of `lib/engine/hand_evaluator.dart` + payout core of `match_controller.dart`; unit tests in `functions/test/engine.test.ts` (`npm test`). Dice use `crypto.randomInt` on the server.

| Function | State |
|---|---|
| createRoom / joinRoom | implemented |
| leaveRoom | implemented (lobby: free seat / host abandons; playing: you keep your table bank, out of match) |
| startMatch | implemented (host, ≥2 filled seats, ante check, escrow online balance → table bank, bots 100, open seats stay empty, code freed) |
| submitRoll | implemented (`keep` indexes, server dice, version check, auto-resolve pot win / 3rd-roll miss) |
| submitKeep | implemented — **banks** the current scoring hand (resolveTurn) |
| endMatch | implemented (host ends early; highest bank wins; everyone keeps their table bank) |
| sweepRooms (every 1 min) | implemented (turn > 60s → server auto-plays that seat like a bot; lobby idle 30 min → abandoned) |
| deleteOnlineData | implemented |

After every action, bot seats are played server-side until a human is up. On finish each human's table bank is credited back to `users/{uid}.gems`.

## Client
- `OnlineLobbyScreen`: display name (optional, max 20), bots slider, Create / Join by code, seat list, host Start; auto-opens the match screen when the server starts the match.
- `OnlineMatchScreen`: listens to `rooms/{id}.match`; seats + banks, pot, last payout, dice; local seat can tap-to-hold, ROLL, BANK; host can End match. Offline `MatchScreen` untouched.
- Settings → **Delete my online data** (flag-gated), also on the lobby screen.

## Parity risks vs local engine
- **No House stake** top-up online (local gives a once-per-match stake when short).
- **No human shortfall choice**: short payers pay what they have; at 0 they're out (local offers cover-with-bank / quit for humans).
- **No handoff confirm**: turn passes immediately; last payout message is shown instead of the handoff strip.
- First-roll triple 1s: each other pays 10 (pay what they have), roller takes pot, match ends — same as local, minus shortfall flow.
- Server bot is a simple policy (hold pairs, bank any score) — not `bot_ai.dart` personalities.
- No mid-match re-ante round restart (local restarts a round on some sweeps); match ends when ≤1 player remains or host ends.
- Dice animation / settle-lock UX not reused; plain dice tiles.

## Auth & display name
- Anonymous Firebase Auth; uid is the online identity.
- **Display name** (optional) is synced to Firestore (`users/{uid}.displayName`, room seat labels) — it **leaves the device**; Data safety declares *Name*. Default when skipped: `Player` + first 4 uid chars (e.g. `Player 7QK2`). Max 20 chars.

## Gems (server-checked)
- Online matches use `users/{uid}.gems`; offline bank stays in SharedPreferences.
- First auth seeds `gems` from the client's local balance claim, clamped to `MAX_CLIENT_CLAIM` (5000). **Honesty risk:** a modified client can claim up to the cap once per anonymous uid (and reinstall → new uid). MVP hardening: cap, `seededFromClaim` audit, later Play Integrity / App Check, and tying IAP grants to server receipts.
- All antes/payouts happen in Function transactions; clients cannot write gems.
- Sync back to offline bank: **not** in MVP (open question).

## Reconnect / timeout
- Room doc is the source of truth; app re-subscribes to `rooms/{id}` on resume (rejoin by code is idempotent).
- Turn timeout 60s → `sweepRooms` auto-plays that seat (one set) with server bot logic.
- Idle lobby 30 min → `abandoned`, code freed.

## Delete my online data (REQUIRED before online Play review)
- In-app control: **Delete my online data** (on the online lobby screen now; Settings entry TODO).
- Calls `deleteOnlineData` → scrubs uid from rooms (seat → open), deletes `users/{uid}` (gems + name), deletes the Firebase Auth user; client signs out. Local offline data untouched. Uninstall alone is not enough, which is why this exists.
- TODO: also delete finished-match history once a history collection exists.

## Legal
Paste pack (CoS hosts on gh-pages; Eng does not host): `/workspace/marge-growth/privacy-policy-online.md`, `terms-of-use-online.md`, `play-console-paste-online.md`. `{{EFFECTIVE_DATE}}` filled at publish. Online collects: anonymous ID, optional display name, online gem balance, room participation. No chat.

## Firebase Console checklist (Jerilyn / CoS)
1. ✅ console.firebase.google.com → Add project, suggested id **`marge-online`** (Analytics optional; off is simpler for Data safety).
2. ✅ Build → Authentication → Get started → Sign-in method → enable **Anonymous**.
3. ✅ (nam5) Build → Firestore Database → Create (production mode, region e.g. `us-central1`).
4. **(STILL BLOCKED)** Upgrade to **Blaze** plan (required for Cloud Functions; set a budget alert, e.g. $5).
5. ✅ app registered; SHA fingerprints TODO (not needed for anon). Project settings → Add app → Android, package **`com.jerilynroberts.marge`**, add SHA-1/SHA-256 of upload key and Play app-signing key (Play Console → App integrity).
6. ✅ Download **google-services.json** → place at `android/app/google-services.json` on the build box (gitignored; template `google-services.json.example`).
7. Give Eng deploy access: either add a service account key to `/home/box/secrets/` or run `firebase login:ci` and share the token — then Eng runs `firebase deploy --only functions,firestore:rules`.

## Open questions
- Ante/seat defaults for online; allow host to change?
- Sync online winnings back to offline bank?
- Server bot difficulty parity with `bot_ai.dart`.
- iOS config (GoogleService-Info.plist) — out of scope for Android MVP.
