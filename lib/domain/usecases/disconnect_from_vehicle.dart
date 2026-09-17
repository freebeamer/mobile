import '../repositories/vehicle_repository.dart';

class DisconnectFromVehicle {
  final IVehicleRepository _repository;
  DisconnectFromVehicle(this._repository);

  Future<void> call() => _repository.disconnect();
}
