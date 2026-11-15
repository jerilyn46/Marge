import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'active_room.dart';
import 'room_models.dart';

/// Thin client over the room Cloud Functions + a Firestore room listener.
/// All mutations go through callable functions (server-authoritative).
class RoomService {
  RoomService({FirebaseFunctions? functions, FirebaseFirestore? firestore})
    : _fnArg = functions,
      _dbArg = firestore;

  final FirebaseFunctions? _fnArg;
  final FirebaseFirestore? _dbArg;
  // Lazy: Firebase is only touched on first use (fakes in tests never do).
  late final FirebaseFunctions _fn = _fnArg ?? FirebaseFunctions.instance;
  late final FirebaseFirestore _db = _dbArg ?? FirebaseFirestore.instance;

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

  /// Roll; [keepIndexes] are held dice (ignored on the first roll of a set).
  /// Dice are rolled on the server.
  Future<void> submitRoll(
    String roomId, {
    List<int> keepIndexes = const [],
    required int expectedVersion,
  }) => _call('submitRoll', {
    'roomId': roomId,
    'keep': keepIndexes,
    'expectedVersion': expectedVersion,
  });

  /// Bank the current scoring hand.
  Future<void> bank(String roomId, {required int expectedVersion}) => _call(
    'submitKeep',
    {'roomId': roomId, 'expectedVersion': expectedVersion},
  );

  Future<void> endMatch(String roomId) => _call('endMatch', {'roomId': roomId});

  /// The live room (lobby or playing) this uid still sits in, if any.
  /// Same query the rejoin test script runs: `memberUids array-contains uid`
  /// (allowed by the member-read rule; single-field index, no composite),
  /// status filtered on the client by [pickActiveRoom].
  Future<Room?> findMyActiveRoom(String uid) async {
    final q = await _db
        .collection('rooms')
        .where('memberUids', arrayContains: uid)
        .get();
    return pickActiveRoom([
      for (final d in q.docs) Room.fromMap(d.id, d.data()),
    ], uid);
  }

  Stream<Room?> watchRoom(String roomId) => _db
      .collection('rooms')
      .doc(roomId)
      .snapshots()
      .map((s) => s.exists ? Room.fromMap(s.id, s.data()!) : null);
}
