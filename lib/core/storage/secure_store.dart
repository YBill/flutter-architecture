import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain on iOS, encrypted storage on Android. No login policy is imposed.
final class SecureStore {
  SecureStore({required this.namespace, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final String namespace;
  final FlutterSecureStorage _storage;

  String _key(String key) => '$namespace$key';

  Future<String?> read(String key) => _storage.read(key: _key(key));
  Future<void> write(String key, String value) =>
      _storage.write(key: _key(key), value: value);
  Future<void> delete(String key) => _storage.delete(key: _key(key));

  Future<void> clear() async {
    final values = await _storage.readAll();
    final keys = values.keys.where((key) => key.startsWith(namespace)).toList();
    for (final key in keys) {
      await _storage.delete(key: key);
    }
  }
}
