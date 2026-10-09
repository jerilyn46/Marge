# Store listing (draft copy for Play Console)

## Short description (78/80)
Free to play. Virtual gems have no cash value. Roll dice with bots or friends.

## Full description
Free to play. Virtual gems have no cash value. Gems cannot be withdrawn, sold, or exchanged for money or prizes.

Marge is a relaxed four-seat dice game. Roll three dice up to three times, keep the ones you like, and bank scoring hands like three of a kind or a straight to collect gems from the table. Roll three ones on your very first throw for the biggest win of the round.

Play on your own against three friendly bots (Spike, Mira, and Zig), or pass the phone around for a local game with friends on the same device. Daily free gems keep you at the table; optional gem packs and optional rewarded videos are also available.

For adults 18+. Contains ads. Optional in-app purchases of virtual gems.

## Keywords
dice, casual, dice game, table game, local multiplayer, pass and play, bots

## Assets
- App icon 512×512 PNG (32-bit, < 1 MB): `docs/store/marge-icon-512.png`
  (exported from `assets/branding/marge-launcher-1024.png`).
- Feature graphic 1024×500: not yet created.
- Phone screenshots (at least 2): not yet captured. Suggested: Home lobby, match
  table, dice keep + roll, daily free gems card, match results. Avoid any
  cash or casino imagery; show "virtual gems" copy where visible.

## Content rating
Not "Everyone". The rating comes from the IARC questionnaire in Play Console
(App content > Content rating). Answer truthfully: simulated gambling = yes
(virtual gems staked on dice outcomes, no cash value); in-app purchases = yes;
ads = yes; no user interaction/sharing. Target audience: 18+.

## Terms of Use effective date
`assets/legal/terms-of-use.md` is Legal's final text with a `{{EFFECTIVE_DATE}}`
token. Pass the date at build time, e.g.
`--dart-define=TERMS_EFFECTIVE_DATE="October 12, 2026"`. Without it the app
omits the "Effective date" line rather than show a placeholder.
