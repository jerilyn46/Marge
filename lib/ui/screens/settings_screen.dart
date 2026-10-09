import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/ads_service.dart';
import '../../services/settings_service.dart';
import '../legal_links.dart';
import '../theme/marge_theme.dart';
import 'terms_screen.dart';

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
            subtitle: const Text('Dice and table sounds'),
            value: s.sfxEnabled,
            activeThumbColor: MargeColors.gold,
            onChanged: (v) => n.setSfx(v),
          ),
          SwitchListTile(
            title: const Text('Haptics'),
            subtitle: const Text('Vibrate on rolls and wins'),
            value: s.hapticsEnabled,
            activeThumbColor: MargeColors.gold,
            onChanged: (v) => n.setHaptics(v),
          ),
          SwitchListTile(
            key: const ValueKey('lite-dice-switch'),
            title: const Text('Simple dice'),
            subtitle: const Text('Lighter roll animation for older phones'),
            value: s.liteDice,
            activeThumbColor: MargeColors.gold,
            onChanged: (v) => n.setLiteDice(v),
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
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy / ad consent'),
            subtitle: const Text('UMP privacy options (EU/EEA/UK when required)'),
            onTap: () async {
              final ads = ref.read(adsServiceProvider);
              final required = await ads.isPrivacyOptionsRequired();
              if (!context.mounted) return;
              if (required) {
                await ads.showPrivacyOptions();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Privacy options not required in this region '
                      '(or ads unavailable on this platform).',
                    ),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Privacy policy'),
            subtitle: const Text('jerilyn46.github.io/Marge/privacy-policy'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => LegalLinks.open(
              context,
              LegalLinks.privacyPolicyUri,
              fallback: LegalLinks.privacyPolicyUrl,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_rounded),
            title: const Text('Terms of Use'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TermsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline_rounded),
            title: const Text('Contact support'),
            subtitle: const Text(LegalLinks.supportEmail),
            onTap: () => LegalLinks.open(
              context,
              LegalLinks.supportMailUri,
              fallback: LegalLinks.supportEmail,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Marge Dice Game · com.jerilynroberts.marge\nVirtual gems only — no real money.',
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
