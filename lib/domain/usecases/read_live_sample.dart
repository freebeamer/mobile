import '../../data/models/mhd_value.dart';
import '../repositories/vehicle_repository.dart';

class ReadLiveSample {
  final IVehicleRepository _repository;
  ReadLiveSample(this._repository);

  Future<List<MhdValue>> call({Duration timeout = const Duration(seconds: 1)}) {
    return _repository.readLive(timeout: timeout);
  }
}
