import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Lazily initialises Firebase and signs in anonymously.
///
/// Firebase is never touched at app startup — only when the player opens
/// "Play online (invite)" — so offline/hotseat play is unaffected when
/// google-services.json is missing.
class OnlineAuthService {
  OnlineAuthService._();
  static final OnlineAuthService instance = OnlineAuthService._();

  bool _ready = false;
  String? lastError;

  Future<bool> ensureFirebase() async {
    if (_ready) return true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _ready = true;
      return true;
    } catch (e) {
      lastError = 'Online play is not configured yet ($e)';
      return false;
    }
  }

  /// Returns the anonymous uid, or null if Firebase is unavailable.
  Future<String?> signInAnonymously() async {
    if (!await ensureFirebase()) return null;
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return auth.currentUser!.uid;
    try {
      final cred = await auth.signInAnonymously();
      return cred.user?.uid;
    } catch (e) {
      lastError = 'Sign-in failed ($e)';
      return null;
    }
  }

  /// Seat label: optional name, else "Player" + short uid suffix.
  static String seatLabel(String? name, String uid) {
    final n = name?.trim() ?? '';
    if (n.isNotEmpty) return n.length > 20 ? n.substring(0, 20) : n;
    final tail = uid.length >= 4 ? uid.substring(0, 4).toUpperCase() : uid;
    return 'Player $tail';
  }

  /// "Delete my online data": server deletes users/{uid}, gem ledger, and
  /// removes the uid from rooms, then the Auth user itself. Local
  /// SharedPreferences (offline bank) is untouched.
  Future<bool> deleteOnlineData() async {
    if (!await ensureFirebase()) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return true;
    try {
      await FirebaseFunctions.instance.httpsCallable('deleteOnlineData').call();
      await FirebaseAuth.instance.signOut();
      return true;
    } catch (e) {
      lastError = 'Delete failed ($e)';
      return false;
    }
  }
}
