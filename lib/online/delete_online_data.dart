import 'package:flutter/material.dart';

import 'auth_service.dart';

/// "Delete my online data" — required before online Play review.
/// Deletes the anonymous account plus server room/gem/name data.
Future<bool> confirmAndDeleteOnlineData(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Delete my online data?'),
      content: const Text(
        'Deletes your online account, display name, online gem balance and '
        'room history from our servers. Offline play and your on-device gems '
        'are not affected. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final done = await OnlineAuthService.instance.deleteOnlineData();
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          done
              ? 'Online data deleted.'
              : (OnlineAuthService.instance.lastError ?? 'Delete failed.'),
        ),
      ),
    );
  }
  return done;
}

class DeleteOnlineDataTile extends StatelessWidget {
  const DeleteOnlineDataTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('settings-delete-online-data'),
    leading: const Icon(Icons.delete_forever_outlined),
    title: const Text('Delete my online data'),
    subtitle: const Text('Online account, name, gems and rooms'),
    onTap: () => confirmAndDeleteOnlineData(context),
  );
}
