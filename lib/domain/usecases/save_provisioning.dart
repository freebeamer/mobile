import '../repositories/provisioning_repository.dart';

class SaveProvisioning {
  final IProvisioningRepository _repository;
  SaveProvisioning(this._repository);

  Future<void> call({required String relayUrl, required String apiKey}) {
    return _repository.save(relayUrl: relayUrl, apiKey: apiKey);
  }
}
