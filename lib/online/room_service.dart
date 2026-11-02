import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'room_models.dart';

/// Thin client over the room Cloud Functions + a Firestore room listener.
/// All mutations go through callable functions (server-authoritative).
class RoomService {
  RoomService({FirebaseFunctions? functions, FirebaseFirestore? firestore})
    : _fn = functions ?? FirebaseFunctions.instance,
      _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _fn;
  final FirebaseFirestore _db;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final res = await _fn.httpsCallable(name).call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(res.data);
  }

  /// Creates a room; returns `{roomId, code}`.
  Future<({String roomId, String code})> createRoom({
    required int seatCount,
    required int botCount,
    required int ante,
    required String displayName,
    required int clientGemClaim,
  }) async {
    final r = await _call('createRoom', {
      'seatCount': seatCount,
      'botCount': botCount,
      'ante': ante,
      'displayName': displayName,
      'clientGemClaim': clientGemClaim,
    });
    return (roomId: r['roomId'] as String, code: r['code'] as String);
  }

  /// Joins by 6-char code; returns roomId.
  Future<String> joinByCode(
    String code, {
    required String displayName,
    required int clientGemClaim,
  }) async {
    final r = await _call('joinRoom', {
      'code': code.trim().toUpperCase(),
      'displayName': displayName,
      'clientGemClaim': clientGemClaim,
    });
    return r['roomId'] as String;
  }

  Future<void> leaveRoom(String roomId) =>
      _call('leaveRoom', {'roomId': roomId});

  Future<void> startMatch(String roomId) =>
      _call('startMatch', {'roomId': roomId});

  Future<void> submitRoll(String roomId, {required int expectedVersion}) =>
      _call('submitRoll', {
        'roomId': roomId,
        'expectedVersion': expectedVersion,
      });

  Future<void> submitKeep(
    String roomId, {
    required List<int> keepIndexes,
    required int expectedVersion,
  }) => _call('submitKeep', {
    'roomId': roomId,
    'keep': keepIndexes,
    'expectedVersion': expectedVersion,
  });

  Stream<Room?> watchRoom(String roomId) => _db
      .collection('rooms')
      .doc(roomId)
      .snapshots()
      .map((s) => s.exists ? Room.fromMap(s.id, s.data()!) : null);
}
