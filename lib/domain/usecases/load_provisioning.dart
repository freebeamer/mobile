import '../../data/models/provisioning_payload.dart';
import '../repositories/provisioning_repository.dart';

class LoadProvisioning {
  final IProvisioningRepository _repository;
  LoadProvisioning(this._repository);

  Future<ProvisioningPayload?> call() => _repository.load();
}
