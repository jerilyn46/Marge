/// Frequency gate for interstitials at match-end / return-to-lobby.
///
/// Policy: at most **one** interstitial per completed match; never
/// back-to-back on the same break; never mid-roll (caller must only
/// invoke at natural breaks — match end / quiet leave).
class InterstitialGate {
  InterstitialGate({int initialMatchesRequired = 1})
      : _matchesRequired = initialMatchesRequired.clamp(1, 1);

  int _completedSinceLastShow = 0;
  int _matchesRequired;
  bool _showedAtLastBreak = false;

  /// Matches that must complete before the next eligible show (always 1).
  int get matchesRequired => _matchesRequired;

  int get completedSinceLastShow => _completedSinceLastShow;

  /// Call once when a match reaches [MatchPhase.matchEnd] (or equivalent).
  void onMatchCompleted() {
    _completedSinceLastShow++;
    _showedAtLastBreak = false;
  }

  /// Whether an interstitial may be shown at this natural break.
  bool get canShow {
    if (_showedAtLastBreak) return false;
    return _completedSinceLastShow >= _matchesRequired;
  }

  /// Record that an interstitial was shown (or attempted and presented).
  void onShown() {
    _completedSinceLastShow = 0;
    _showedAtLastBreak = true;
    _matchesRequired = 1;
  }
}
