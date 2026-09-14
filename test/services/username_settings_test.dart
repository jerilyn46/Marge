import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marge/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SettingsNotifier.bootstrap = null;
  });

  test('username absent until setPlayerName writes prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await SettingsNotifier.load();
    expect(s.hasUsername, isFalse);
    expect(s.playerName, 'You');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_name', 'Jerilyn');
    final again = await SettingsNotifier.load();
    expect(again.hasUsername, isTrue);
    expect(again.playerName, 'Jerilyn');
  });

  test('setPlayerName persists and marks hasUsername', () async {
    SharedPreferences.setMockInitialValues({});
    SettingsNotifier.bootstrap = await SettingsNotifier.load();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(settingsProvider).hasUsername, isFalse);
    await container.read(settingsProvider.notifier).setPlayerName('  Nova  ');
    expect(container.read(settingsProvider).hasUsername, isTrue);
    expect(container.read(settingsProvider).playerName, 'Nova');

    final cold = await SettingsNotifier.load();
    expect(cold.hasUsername, isTrue);
    expect(cold.playerName, 'Nova');
  });
}
