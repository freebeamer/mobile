import '../../doip/payload_types.dart';
import '../../domain/repositories/vehicle_repository.dart';
import '../datasources/doip_data_source.dart';
import '../datasources/mhd_data_source.dart';
import '../models/mhd_value.dart';

class VehicleRepositoryImpl implements IVehicleRepository {
  final IDoipDataSource _doip;
  final IMhdDataSource _mhd;

  VehicleRepositoryImpl(this._doip, this._mhd);

  @override
  Future<int> connect({
    required String address,
    required int port,
    int sourceAddress = 0x0E00,
    Duration dialTimeout = const Duration(seconds: 2),
    Duration activateTimeout = const Duration(seconds: 2),
  }) async {
    await _doip.connect(address, port, timeout: dialTimeout);
    return _doip.activate(sourceAddress, activationDefault, timeout: activateTimeout);
  }

  @override
  Future<List<MhdValue>> readLive({Duration timeout = const Duration(seconds: 1)}) {
    return _mhd.readMonitor(timeout: timeout);
  }

  @override
  Future<void> disconnect() => _doip.close();
}
