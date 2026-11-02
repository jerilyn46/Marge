import 'package:flutter_test/flutter_test.dart';
import 'package:marge/online/auth_service.dart';
import 'package:marge/online/room_models.dart';

void main() {
  test('seat label defaults to Player + uid suffix, max 20', () {
    expect(OnlineAuthService.seatLabel(null, 'ab12xyz'), 'Player AB12');
    expect(OnlineAuthService.seatLabel('  ', 'zz99'), 'Player ZZ99');
    expect(OnlineAuthService.seatLabel('A' * 30, 'x').length, 20);
  });

  test('Room parses server match state', () {
    final r = Room.fromMap('r1', {
      'code': 'ABC234',
      'hostUid': 'a',
      'status': 'playing',
      'ante': 10,
      'version': 3,
      'seats': [
        {'index': 0, 'kind': 'host', 'uid': 'a'},
        {'index': 1, 'kind': 'open'},
      ],
      'match': {
        'pot': 22,
        'round': 1,
        'status': 'playing',
        'seats': [
          {'index': 0, 'kind': 'host', 'uid': 'a', 'bank': 88, 'eliminated': false},
          {'index': 1, 'kind': 'bot', 'bank': 90, 'eliminated': false},
        ],
        'turn': {
          'seat': 0,
          'rollNumber': 2,
          'dice': [3, 3, 5],
          'kept': [true, true, false],
          'score': {'kind': 'none'},
        },
        'lastPayout': {'message': 'Bot whiffs'},
      },
    });
    expect(r.openSeats, 1);
    final m = r.match!;
    expect(m.pot, 22);
    expect(m.turn!.rollsLeft, 1);
    expect(m.turn!.isScoring, isFalse);
    expect(m.seats[1].kind, SeatKind.bot);
    expect(m.lastPayoutMessage, 'Bot whiffs');
  });
}
