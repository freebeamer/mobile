import 'package:freebeamer_mobile/data/datasources/secure_storage_data_source.dart';

/// An in-memory ISecureStorageDataSource — stands in for the platform
/// Keychain/Keystore, which isn't available in a bare unit test.
class FakeSecureStorage implements ISecureStorageDataSource {
  final Map<String, String> values = {};

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
