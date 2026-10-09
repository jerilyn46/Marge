import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'denver_time.dart';

/// One local "free gems are ready" reminder, on the existing daily-drip clock.
///
/// - Scheduled only when the app goes to the background and the drip is
///   already claimed for today. Cancelled whenever the app comes back to the
///   foreground, so it can never pop over an active roll (the in-app prompt on
///   Home covers the foreground case).
/// - Never asks for notification permission. If the user has not already
///   allowed notifications (e.g. from the turn alert), nothing is scheduled.
/// - A single fixed notification id, so there is at most one pending reminder.
/// - Fires at 9:00 America/Denver on the day the drip unlocks, not at
///   midnight, to avoid a middle-of-the-night ping.
class DailyGemsReminder {
  DailyGemsReminder({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const notificationId = 7101;
  static const channelId = 'marge_daily_gems';
  static const channelName = 'Daily free gems';
  static const reminderHourDenver = 9;

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  /// Reminder instant for a drip that unlocks at [readyUtc] (Denver midnight).
  static DateTime reminderAtUtc(DateTime readyUtc) {
    final wall = DenverTime.wallClock(readyUtc.toUtc());
    return DenverTime.localToUtc(
      wall.year,
      wall.month,
      wall.day,
      reminderHourDenver,
    );
  }

  /// Schedule for [readyUtc] if notifications are already permitted.
  Future<void> scheduleIfPermitted(DateTime readyUtc, {DateTime? utcNow}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final at = reminderAtUtc(readyUtc);
      final now = (utcNow ?? DateTime.now().toUtc()).toUtc();
      if (!at.isAfter(now)) return;
      await _ensureReady();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return;
      final enabled = await android.areNotificationsEnabled() ?? false;
      if (!enabled) return;
      await _plugin.zonedSchedule(
        notificationId,
        'Marge',
        'Your free daily gems are ready.',
        tz.TZDateTime.from(at, tz.UTC),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: 'Once a day when free gems can be claimed',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e, st) {
      debugPrint('DailyGemsReminder: schedule failed (in-app prompt only): $e\n$st');
    }
  }

  Future<void> cancel() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _ensureReady();
      await _plugin.cancel(notificationId);
    } catch (e, st) {
      debugPrint('DailyGemsReminder: cancel failed: $e\n$st');
    }
  }

  Future<void> _ensureReady() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    _ready = true;
  }
}
