import 'package:shared_preferences/shared_preferences.dart';

/// Small, non-sensitive preferences. Platform failures propagate to the caller.
final class PreferencesStore {
  PreferencesStore({
    required this.namespace,
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final String namespace;
  final SharedPreferencesAsync _preferences;

  String _key(String key) => '$namespace$key';

  Future<String?> getString(String key) => _preferences.getString(_key(key));
  Future<int?> getInt(String key) => _preferences.getInt(_key(key));
  Future<double?> getDouble(String key) => _preferences.getDouble(_key(key));
  Future<bool?> getBool(String key) => _preferences.getBool(_key(key));
  Future<List<String>?> getStringList(String key) =>
      _preferences.getStringList(_key(key));

  Future<void> setString(String key, String value) =>
      _preferences.setString(_key(key), value);
  Future<void> setInt(String key, int value) =>
      _preferences.setInt(_key(key), value);
  Future<void> setDouble(String key, double value) =>
      _preferences.setDouble(_key(key), value);
  Future<void> setBool(String key, bool value) =>
      _preferences.setBool(_key(key), value);
  Future<void> setStringList(String key, List<String> value) =>
      _preferences.setStringList(_key(key), value);

  Future<bool> containsKey(String key) => _preferences.containsKey(_key(key));
  Future<void> remove(String key) => _preferences.remove(_key(key));

  /// Only removes this environment's keys, including when other plugins use SP.
  Future<void> clear() async {
    final keys = await _preferences.getKeys();
    await _preferences.clear(
      allowList: keys.where((key) => key.startsWith(namespace)).toSet(),
    );
  }
}
