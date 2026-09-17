import '../../data/models/device_pairing.dart';
import '../repositories/device_pairing_repository.dart';

class ListDevicePairings {
  final IDevicePairingRepository _repository;
  ListDevicePairings(this._repository);

  Future<List<DevicePairing>> call() => _repository.list();
}
