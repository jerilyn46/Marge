import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/settings_service.dart';
import '../theme/marge_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: ref.read(settingsProvider).playerName,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            onSubmitted: (v) => n.setPlayerName(v.trim().isEmpty ? 'You' : v.trim()),
            onChanged: (v) => n.setPlayerName(v.trim().isEmpty ? 'You' : v.trim()),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Sound effects'),
            subtitle: const Text('Console stubs / future audio pack'),
            value: s.sfxEnabled,
            activeThumbColor: MargeColors.gold,
            onChanged: (v) => n.setSfx(v),
          ),
          SwitchListTile(
            title: const Text('Haptics'),
            subtitle: const Text('No-op on Linux / web — fine on phones'),
            value: s.hapticsEnabled,
            activeThumbColor: MargeColors.gold,
            onChanged: (v) => n.setHaptics(v),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.menu_book_rounded),
            title: const Text('Reset rules onboarding'),
            onTap: () async {
              await n.setSeenRules(false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rules tip will show next play')),
                );
              }
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Marge Dice Game · com.jerilyn.marge\nVirtual chips only — no real money.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MargeColors.cream.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
