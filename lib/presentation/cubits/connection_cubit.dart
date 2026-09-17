import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/telemetry/telemetry_upload_service.dart';
import '../../data/models/telemetry_config.dart';
import '../../data/models/telemetry_sample.dart';
import '../../data/models/telemetry_session.dart';
import '../../domain/usecases/negotiate_telemetry.dart';
import '../../domain/usecases/connect_to_vehicle.dart';
import '../../domain/usecases/disconnect_from_vehicle.dart';
import '../../domain/usecases/read_live_sample.dart';
import 'connection_state.dart';

/// Orchestrates one streaming session: connect, then repeatedly read a
/// live MHD sample and hand it to TelemetryUploadService, until stop() is
/// called or an error occurs.
///
/// Acquisition (reading the adapter) is decoupled from delivery, mirroring
/// cmd/freebeamer/command_mhd.go's Phase 3a redesign: enqueue is
/// synchronous and non-blocking, so a slow/unreachable relay can never
/// stall the next scheduled read — see
/// docs/live-data-and-vehicle-mapping-plan.md's Phase 3 section and
/// TelemetryUploadService's own doc comment for the full rationale. All
/// other actual work is delegated to use cases/the upload service — this
/// class only sequences them and emits state.
class ConnectionCubit extends Cubit<VehicleConnectionState> {
  final ConnectToVehicle _connectToVehicle;
  final DisconnectFromVehicle _disconnectFromVehicle;
  final ReadLiveSample _readLiveSample;
  final ITelemetryUploadService _telemetryUploadService;
  final NegotiateTelemetry _negotiateTelemetry;
  bool _running = false;

  bool _stopRequested = false;

  ConnectionCubit({
    required ConnectToVehicle connectToVehicle,
    required DisconnectFromVehicle disconnectFromVehicle,
    required ReadLiveSample readLiveSample,
    required ITelemetryUploadService telemetryUploadService,
    required NegotiateTelemetry negotiateTelemetry,
  })  : _connectToVehicle = connectToVehicle,
        _disconnectFromVehicle = disconnectFromVehicle,
        _readLiveSample = readLiveSample,
        _telemetryUploadService = telemetryUploadService,
        _negotiateTelemetry = negotiateTelemetry,
        super(const VehicleConnectionState());

  Future<void> start({
    required String address,
    required int port,
    required String deviceId,
    required TelemetryConfig telemetryConfig,
    int sourceAddress = 0x0E00,
    Duration sampleInterval = const Duration(milliseconds: 200),
    Duration requestTimeout = const Duration(seconds: 1),
  }) async {
    if (_running || isClosed) {
      return;
    }
    _running = true;
    _stopRequested = false;
    emit(state.copyWith(
        status: ConnectionStatus.connecting,
        clearConnectionError: true,
        clearRecordingError: true));

    try {
      var version = telemetryVersion;
      try {
        version = await _negotiateTelemetry(config: telemetryConfig);
      } catch (_) {
        // Unknown/offline: retain v2 identity locally. Delivery checks again.
      }
      if (_stopRequested || isClosed) return;
      final session =
          version == telemetryVersion ? TelemetrySession.create() : null;
      var sequence = 0;
      await _connectToVehicle(
          address: address, port: port, sourceAddress: sourceAddress);
      if (_stopRequested || isClosed) return;
      await _telemetryUploadService.start(
          config: telemetryConfig, interval: sampleInterval);
      emit(state.copyWith(status: ConnectionStatus.streaming));

      while (!_stopRequested && !isClosed) {
        final values = await _readLiveSample(timeout: requestTimeout);
        final sample = TelemetrySample.fromMhdValues(
            deviceId: deviceId,
            timestamp: DateTime.now(),
            values: values,
            session: session,
            sequence: session == null ? null : sequence++);
        sample.validate();
        _telemetryUploadService.enqueue(sample); // sync, non-blocking
        if (isClosed) break;
        emit(state
            .copyWith(status: ConnectionStatus.streaming, values: values)
            .withUploadStatus(_telemetryUploadService.status));
        await Future.delayed(sampleInterval);
      }
      if (!isClosed) emit(state.copyWith(status: ConnectionStatus.stopped));
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
            status: ConnectionStatus.error, connectionError: e.toString()));
      }
    } finally {
      try {
        await _telemetryUploadService.stop();
      } finally {
        try {
          await _disconnectFromVehicle();
        } finally {
          if (_stopRequested &&
              !isClosed &&
              state.status != ConnectionStatus.error) {
            emit(state.copyWith(status: ConnectionStatus.stopped));
          }
          _running = false;
        }
      }
    }
  }

  /// Requests the streaming loop in start() to end after its current
  /// iteration. Cheap and safe to call from dispose/onStop handlers.
  void stop() {
    _stopRequested = true;
  }

  @override
  Future<void> close() {
    _stopRequested = true;
    return super.close();
  }
}
