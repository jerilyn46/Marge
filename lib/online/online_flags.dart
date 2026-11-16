/// Feature flag for invite/room-code remote multiplayer (WIP).
///
/// Off by default so Production builds are unaffected until Firebase is
/// configured. Enable with `--dart-define=MARGE_ONLINE_INVITE=true`.
const bool kOnlineInviteEnabled = bool.fromEnvironment(
  'MARGE_ONLINE_INVITE',
  defaultValue: false,
);
