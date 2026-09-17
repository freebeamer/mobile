import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper over FlutterSecureStorage (Keychain on iOS, Keystore
/// on Android) — kept as its own data source so
/// IProvisioningRepository doesn't depend on the storage package
/// directly, matching this app's interface/implementation convention
/// throughout the data layer.
abstract class ISecureStorageDataSource {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class SecureStorageDataSourceImpl implements ISecureStorageDataSource {
  final FlutterSecureStorage _storage;
  SecureStorageDataSourceImpl({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
