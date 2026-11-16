import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Player-facing text for anything that goes wrong in the online screens.
///
/// Never shows a stack trace or `toString()` of an exception: the detail is
/// logged with [debugPrint] and the player gets one short, plain sentence.
class OnlineErrors {
  OnlineErrors._();

  static const notActive = "That room code isn't active.";
  static const network = "Can't reach the server. Check your connection.";
  static const generic = 'Something went wrong. Please try again.';

  /// Maps [error] to a friendly message and logs the raw detail.
  static String friendly(Object error, {String where = 'online'}) {
    debugPrint('marge-online[$where]: $error');
    return message(error);
  }

  /// Pure mapping (no logging) so it is unit-testable.
  @visibleForTesting
  static String message(Object error) {
    if (error is FirebaseFunctionsException) {
      return forCode(error.code, serverMessage: error.message);
    }
    if (error is FirebaseException) {
      return forCode(error.code, serverMessage: error.message);
    }
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return network;
    }
    return generic;
  }

  /// [code] is a Firebase error code (`not-found`, `unavailable`, ...).
  /// [serverMessage] is the HttpsError text from our Cloud Functions; it is
  /// only used to pick a sentence, never shown as-is.
  static String forCode(String code, {String? serverMessage}) {
    final m = (serverMessage ?? '').toLowerCase();
    switch (code) {
      case 'not-found':
        return notActive;
      case 'failed-precondition':
        if (m.contains('not enough online gems') ||
            m.contains('lacks the ante')) {
          return "Not enough online gems for this table's ante.";
        }
        if (m.contains('room not open')) {
          return 'That game has already started or closed.';
        }
        if (m.contains('in another match')) {
          return 'A player is still in another online match.';
        }
        if (m.contains('match not running')) {
          return 'This match has ended.';
        }
        if (m.contains('not your turn')) return "It's not your turn.";
        if (m.contains('cannot bank a miss')) {
          return "You can't bank a miss — roll again.";
        }
        return "That can't be done right now.";
      case 'permission-denied':
        return m.contains('host only')
            ? 'Only the host can do that.'
            : "You're not seated at this table.";
      case 'resource-exhausted':
        return 'That room is full.';
      case 'aborted':
        return 'The table just changed. Try again.';
      case 'already-exists':
        return 'You are already at this table.';
      case 'invalid-argument':
        return "That didn't look right. Check it and try again.";
      case 'unauthenticated':
        return "Couldn't sign you in for online play. Try again.";
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
      case 'internal':
        return network;
      default:
        return generic;
    }
  }
}
