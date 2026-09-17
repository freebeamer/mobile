import '../../domain/repositories/provisioning_repository.dart';
import '../datasources/secure_storage_data_source.dart';
import '../models/provisioning_payload.dart';

class ProvisioningRepositoryImpl implements IProvisioningRepository {
  static const _relayUrlKey = 'relay_url';
  static const _apiKeyKey = 'api_key';

  final ISecureStorageDataSource _storage;
  ProvisioningRepositoryImpl(this._storage);

  @override
  Future<void> save({required String relayUrl, required String apiKey}) async {
    await _storage.write(_relayUrlKey, relayUrl);
    await _storage.write(_apiKeyKey, apiKey);
  }

  @override
  Future<ProvisioningPayload?> load() async {
    final relayUrl = await _storage.read(_relayUrlKey);
    final apiKey = await _storage.read(_apiKeyKey);
    if (relayUrl == null || relayUrl.isEmpty || apiKey == null || apiKey.isEmpty) {
      return null;
    }
    return ProvisioningPayload(relayUrl: relayUrl, apiKey: apiKey);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(_relayUrlKey);
    await _storage.delete(_apiKeyKey);
  }
}
