import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/core/storage/preferences_store.dart';
import 'package:novelverse/core/storage/secure_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({'another_plugin.key': 'keep'});
    FlutterSecureStorage.setMockInitialValues({'another_plugin.key': 'keep'});
  });

  test(
    'SP instances share persistent data and clear only their namespace',
    () async {
      final dev = PreferencesStore(namespace: 'novelverse.dev.');
      final prod = PreferencesStore(namespace: 'novelverse.prod.');
      await dev.setString('locale', 'zh');
      await prod.setString('locale', 'en');
      expect(
        await PreferencesStore(namespace: 'novelverse.dev.')
            .getString('locale'),
        'zh',
      );
      await dev.clear();
      expect(await dev.getString('locale'), isNull);
      expect(await prod.getString('locale'), 'en');
      expect(
        await PreferencesStore(namespace: 'another_plugin.').getString('key'),
        'keep',
      );
    },
  );

  test(
    'clearing an empty SP namespace does not clear unrelated values',
    () async {
      await PreferencesStore(namespace: 'empty.').clear();
      expect(
        await PreferencesStore(namespace: 'another_plugin.').getString('key'),
        'keep',
      );
    },
  );

  test(
    'secure storage isolates environments and preserves unrelated keys',
    () async {
      final dev = SecureStore(namespace: 'novelverse.dev.');
      final prod = SecureStore(namespace: 'novelverse.prod.');
      await dev.write('token', 'development-value');
      await prod.write('token', 'production-value');
      expect(await dev.read('token'), 'development-value');
      await dev.clear();
      expect(await dev.read('token'), isNull);
      expect(await prod.read('token'), 'production-value');
      expect(
        await SecureStore(namespace: 'another_plugin.').read('key'),
        'keep',
      );
    },
  );
}
