import '../../data/models/telemetry_config.dart';
import '../repositories/telemetry_repository.dart';

class NegotiateTelemetry {
  final ITelemetryRepository _repository;
  NegotiateTelemetry(this._repository);

  Future<int> call({required TelemetryConfig config}) =>
      _repository.negotiate(config: config);
}
