import 'package:flutter/material.dart';

import '../ui/screens/online_lobby_screen.dart';
import '../ui/widgets/rejoin_banner.dart';
import 'auth_service.dart';
import 'online_flags.dart';
import 'room_models.dart';
import 'room_service.dart';

/// Live room for the persisted anonymous uid (never creates an account).
Future<Room?> findMyLiveRoom() async {
  if (!kOnlineInviteEnabled) return null;
  final uid = await OnlineAuthService.instance.existingUid();
  if (uid == null) return null;
  return RoomService().findMyActiveRoom(uid);
}

/// Rejoin prompt wired to the real backend, for Home and Set the table.
/// Rejoin opens the lobby on that room, which goes straight to the match
/// screen if it is already playing.
Widget liveRejoinPrompt(
  BuildContext context, {
  required String displayName,
  required int gemClaim,
  Key? key,
}) {
  if (!kOnlineInviteEnabled) return const SizedBox.shrink();
  return RejoinPrompt(
    key: key,
    find: findMyLiveRoom,
    onRejoin: (room) => Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OnlineLobbyScreen(
          displayName: displayName,
          gemClaim: gemClaim,
          resumeRoomId: room.id,
        ),
      ),
    ),
    leave: (room) => RoomService().leaveRoom(room.id),
  );
}
