import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/settings_service.dart';
import '../theme/marge_theme.dart';
import '../widgets/felt_hero_backdrop.dart';

/// First-launch gate: one field, confirm, then Home / Play.
class UsernameScreen extends ConsumerStatefulWidget {
  const UsernameScreen({super.key});

  @override
  ConsumerState<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends ConsumerState<UsernameScreen> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Pick a name to sit at the table.');
      return;
    }
    if (name.length > 24) {
      setState(() => _error = 'Keep it to 24 characters.');
      return;
    }
    await ref.read(settingsProvider.notifier).setPlayerName(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FeltHeroBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                Text(
                  'Marge',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: MargeColors.lamp,
                        letterSpacing: 2,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'What should we call you at the table?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: MargeColors.cream.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _confirm(),
                  maxLength: 24,
                  style: const TextStyle(
                    color: MargeColors.cream,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Username',
                    counterStyle: TextStyle(
                      color: MargeColors.cream.withValues(alpha: 0.5),
                    ),
                    labelStyle: TextStyle(
                      color: MargeColors.cream.withValues(alpha: 0.75),
                    ),
                    filled: true,
                    fillColor: MargeColors.velvet.withValues(alpha: 0.55),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: MargeColors.woodEdge.withValues(alpha: 0.7),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: MargeColors.woodEdge.withValues(alpha: 0.7),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: MargeColors.gold),
                    ),
                    errorText: _error,
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MargeColors.gold,
                      foregroundColor: MargeColors.velvet,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    child: const Text('Continue'),
                  ),
                ),
                const Spacer(flex: 3),
                Text(
                  'Virtual gems only — no real money.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MargeColors.cream.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
