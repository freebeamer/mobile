import '../repositories/vehicle_repository.dart';

class ConnectToVehicle {
  final IVehicleRepository _repository;
  ConnectToVehicle(this._repository);

  /// Returns the discovered DME target address.
  Future<int> call({
    required String address,
    required int port,
    int sourceAddress = 0x0E00,
    Duration dialTimeout = const Duration(seconds: 2),
    Duration activateTimeout = const Duration(seconds: 2),
  }) {
    return _repository.connect(
      address: address,
      port: port,
      sourceAddress: sourceAddress,
      dialTimeout: dialTimeout,
      activateTimeout: activateTimeout,
    );
  }
}
