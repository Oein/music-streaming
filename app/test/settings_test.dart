import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/settings/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings survive a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final a = SettingsService();
    await a.load();
    await a.update(forceAac: true, volume: 0.4);

    final b = SettingsService(); // fresh launch
    await b.load();
    expect(b.forceAac, isTrue);
    expect(b.volume, 0.4);
  });
}
