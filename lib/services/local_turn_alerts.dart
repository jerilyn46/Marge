import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Device-local "{name}'s turn" notification.
///
/// This is not a push. Remote friends are not pinged. If Android permission
/// is denied, the caller still shows the in-app banner.
class LocalTurnAlerts {
  LocalTurnAlerts({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const channelId = 'marge_turns';
  static const channelName = 'Group turns';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  bool _askedPermission = false;
  bool _permitted = false;
  int _id = 0;

  Future<void> show(String message) async {
    try {
      await _ensureReady();
      if (!_askedPermission) {
        _askedPermission = true;
        _permitted = await _requestPermission();
      }
      if (!_permitted) return;
      _id = (_id + 1) % 100000;
      await _plugin.show(
        _id,
        'Marge',
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: "When it is your group's turn at the table",
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('LocalTurnAlerts: show failed (banner still shown): $e\n$st');
    }
  }

  Future<void> _ensureReady() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    _ready = true;
  }

  Future<bool> _requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return false;
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    } catch (e, st) {
      debugPrint('LocalTurnAlerts: permission request failed: $e\n$st');
      return false;
    }
  }
}
