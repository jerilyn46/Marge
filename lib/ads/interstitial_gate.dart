/// Frequency gate for interstitials at match-end / return-to-lobby.
///
/// Policy: at most ~1 ad per 2–3 completed matches; never back-to-back;
/// never mid-roll (caller must only invoke at natural breaks).
class InterstitialGate {
  InterstitialGate({int initialMatchesRequired = 2})
      : _matchesRequired = initialMatchesRequired.clamp(2, 3);

  int _completedSinceLastShow = 0;
  int _matchesRequired;
  bool _showedAtLastBreak = false;

  /// Matches that must complete before the next eligible show (2 or 3).
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
    // Alternate 2 ↔ 3 so cadence stays in the ~2–3 match band.
    _matchesRequired = _matchesRequired == 2 ? 3 : 2;
  }
}
