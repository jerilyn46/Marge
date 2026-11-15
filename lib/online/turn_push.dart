import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'online_flags.dart';

/// "Your turn in Marge (room XXXXXX)" pushes for online invite play.
///
/// The server sends them (FCM) when the turn passes to you — after an
/// opponent's move or a 60 s timeout auto-play — never for bots or the
/// player who just acted. While Marge is open, Android does not show them
/// and the in-app "Your turn!" banner covers it ([onMessage] is ignored).
///
/// Permission (Android 13+ POST_NOTIFICATIONS) is asked once, the first time
/// the player goes online. If denied we never ask again; the lobby shows a
/// one-line hint and the in-app banner still works.
class TurnPush {
  TurnPush._();
  static final TurnPush instance = TurnPush._();

  static const channelId = 'marge_online_turns';
  static const channelName = 'Your turn (online)';
  static const _kAsked = 'online_push_asked';
  static const _kToken = 'online_push_token';

  /// null = not checked yet; false = notifications off for Marge.
  final ValueNotifier<bool?> permitted = ValueNotifier(null);

  StreamSubscription<String>? _refreshSub;
  bool _tapsStarted = false;

  /// Room id from a "Your turn" push payload, or null for anything else.
  static String? roomIdFromData(Map<String, dynamic> data) {
    if (data['type'] != 'turn') return null;
    final id = data['roomId'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// Lobby entry (signed in). Asks once, creates the channel, registers the
  /// FCM token with the server. Never throws; returns whether pushes can show.
  Future<bool> enableForOnline() async {
    if (!kOnlineInviteEnabled) return false;
    try {
      await _createChannel();
      final fm = FirebaseMessaging.instance;
      final prefs = await SharedPreferences.getInstance();
      NotificationSettings settings;
      if (prefs.getBool(_kAsked) ?? false) {
        settings = await fm.getNotificationSettings();
      } else {
        await prefs.setBool(_kAsked, true);
        settings = await fm.requestPermission();
      }
      final ok =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      permitted.value = ok;
      if (!ok) return false;
      await fm.setAutoInitEnabled(true);
      // FCM registration token (what the Admin SDK multicast sends to). The
      // newer FID register() API targets a different send path, so keep this.
      // ignore: deprecated_member_use
      final token = await fm.getToken();
      if (token != null) await _register(token);
      // ignore: deprecated_member_use
      _refreshSub ??= fm.onTokenRefresh.listen(
        (t) => unawaited(_register(t)),
        onError: (Object e) => debugPrint('marge-push[refresh]: $e'),
      );
      return true;
    } catch (e) {
      debugPrint('marge-push[enable]: $e');
      return permitted.value ?? false;
    }
  }

  Future<void> _register(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getString(_kToken);
      await FirebaseFunctions.instance.httpsCallable('registerPushToken').call({
        'token': token,
        if (prev != null && prev != token) 'replaces': prev,
      });
      await prefs.setString(_kToken, token);
    } catch (e) {
      debugPrint('marge-push[register]: $e');
    }
  }

  Future<void> _createChannel() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: 'When it is your turn in an online room',
          importance: Importance.high,
        ),
      );
    } catch (e) {
      debugPrint('marge-push[channel]: $e');
    }
  }

  /// App start (online builds only, after the first frame): a tap on a
  /// "Your turn" push opens that match — cold start via getInitialMessage,
  /// from the background via onMessageOpenedApp.
  Future<void> startTapHandling(void Function(String roomId) open) async {
    if (!kOnlineInviteEnabled || _tapsStarted) return;
    _tapsStarted = true;
    try {
      if (!await OnlineAuthService.instance.ensureFirebase()) return;
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        final id = roomIdFromData(msg.data);
        if (id != null) open(id);
      });
      // Foreground: the table's banner (or the Rejoin card) covers it.
      FirebaseMessaging.onMessage.listen(
        (msg) => debugPrint('marge-push: foreground ${msg.data['type']}'),
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      final id = initial == null ? null : roomIdFromData(initial.data);
      if (id != null) open(id);
    } catch (e) {
      debugPrint('marge-push[taps]: $e');
    }
  }

  /// "Delete my online data": drop this device's token (the server deletes
  /// pushTokens/{uid} too). Never throws.
  Future<void> forget() async {
    try {
      await _refreshSub?.cancel();
      _refreshSub = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kToken);
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('marge-push[forget]: $e');
    }
  }
}
