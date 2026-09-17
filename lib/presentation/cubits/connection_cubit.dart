import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/telemetry/telemetry_upload_service.dart';
import '../../data/models/device_pairing.dart';
import '../../data/models/telemetry_config.dart';
import '../../data/models/telemetry_sample.dart';
import '../../data/models/telemetry_session.dart';
import '../../domain/usecases/authenticate_device.dart';
import '../../domain/usecases/negotiate_telemetry.dart';
import '../../domain/usecases/connect_to_vehicle.dart';
import '../../domain/usecases/disconnect_from_vehicle.dart';
import '../../domain/usecases/read_live_sample.dart';
import 'connection_state.dart';

// A tear-off, captured here (before ConnectionCubit's constructor
// parameter of the same name shadows it) as this class's default for
// building a TelemetryConfig — see buildTelemetryConfig's own doc
// comment.
const _defaultBuildTelemetryConfig = buildTelemetryConfig;

/// Orchestrates one streaming session: authenticate against the paired
/// device's relay, connect to the vehicle, then repeatedly read a live
/// MHD sample and hand it to TelemetryUploadService, until stop() is
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
  final AuthenticateDevice _authenticateDevice;
  final Future<TelemetryConfig> Function(
      {required String endpoint,
      required String clientId,
      required String sessionToken}) _buildTelemetryConfig;
  bool _running = false;

  bool _stopRequested = false;

  /// The most recently obtained device session token, if any —
  /// available for a best-effort LogoutDevice call when the session
  /// ends (see StatusScreen). Not authoritative: a session started
  /// while offline may never have one, and a mid-stream refresh (see
  /// TelemetryUploadService's reauthenticate retry) updates it silently.
  String? get currentSessionToken => _currentSessionToken;
  String? _currentSessionToken;

  ConnectionCubit({
    required ConnectToVehicle connectToVehicle,
    required DisconnectFromVehicle disconnectFromVehicle,
    required ReadLiveSample readLiveSample,
    required ITelemetryUploadService telemetryUploadService,
    required NegotiateTelemetry negotiateTelemetry,
    required AuthenticateDevice authenticateDevice,
    // Overridable so tests don't need path_provider's platform channel
    // (buildTelemetryConfig's default) registered — see
    // buildTelemetryConfig's own doc comment for what the real one does.
    Future<TelemetryConfig> Function(
            {required String endpoint,
            required String clientId,
            required String sessionToken})?
        buildTelemetryConfig,
  })  : _connectToVehicle = connectToVehicle,
        _disconnectFromVehicle = disconnectFromVehicle,
        _readLiveSample = readLiveSample,
        _telemetryUploadService = telemetryUploadService,
        _negotiateTelemetry = negotiateTelemetry,
        _authenticateDevice = authenticateDevice,
        _buildTelemetryConfig = buildTelemetryConfig ?? _defaultBuildTelemetryConfig,
        super(const VehicleConnectionState());

  Future<void> start({
    required DevicePairing pairing,
    required String address,
    required int port,
    required String deviceId,
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
      // A relay/auth failure here is not fatal: the vehicle connection
      // and local buffering proceed regardless (mirrors the negotiate
      // fallback just below) — the reauthenticate callback passed to
      // the upload service keeps retrying once the relay is reachable.
      var sessionToken = '';
      try {
        sessionToken = await _authenticateDevice(pairing);
        _currentSessionToken = sessionToken;
      } catch (_) {
        // Unreachable/offline, or the pairing was revoked: proceed
        // with an empty token — delivery falls back to buffering.
      }
      final telemetryConfig = await _buildTelemetryConfig(
          endpoint: '${pairing.relayUrl}/v1/telemetry',
          clientId: pairing.clientId,
          sessionToken: sessionToken);

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
          config: telemetryConfig,
          interval: sampleInterval,
          reauthenticate: () => _reauthenticate(pairing));
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

  /// Re-authenticates pairing for TelemetryUploadService's reauthenticate
  /// retry, swallowing any failure to null (its documented "give up,
  /// fall through to backoff" signal) rather than letting it propagate
  /// out of the upload loop.
  Future<String?> _reauthenticate(DevicePairing pairing) async {
    try {
      final token = await _authenticateDevice(pairing);
      _currentSessionToken = token;
      return token;
    } catch (_) {
      return null;
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
