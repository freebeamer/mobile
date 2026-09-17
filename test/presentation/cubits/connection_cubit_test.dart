import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/core/telemetry/telemetry_upload_service.dart';
import 'package:freebeamer_mobile/core/telemetry/telemetry_upload_status.dart';
import 'package:freebeamer_mobile/data/models/mhd_field.dart';
import 'package:freebeamer_mobile/data/models/mhd_value.dart';
import 'package:freebeamer_mobile/data/models/telemetry_sample.dart';
import 'package:freebeamer_mobile/data/models/telemetry_config.dart';
import 'package:freebeamer_mobile/domain/repositories/telemetry_repository.dart';
import 'package:freebeamer_mobile/domain/repositories/vehicle_repository.dart';
import 'package:freebeamer_mobile/domain/usecases/connect_to_vehicle.dart';
import 'package:freebeamer_mobile/domain/usecases/disconnect_from_vehicle.dart';
import 'package:freebeamer_mobile/domain/usecases/read_live_sample.dart';
import 'package:freebeamer_mobile/domain/usecases/negotiate_telemetry.dart';
import 'package:freebeamer_mobile/presentation/cubits/connection_cubit.dart';
import 'package:freebeamer_mobile/presentation/cubits/connection_state.dart';

class FakeVehicle implements IVehicleRepository {
  int connections = 0;
  @override
  Future<int> connect(
      {required String address,
      required int port,
      int sourceAddress = 0x0e00,
      Duration dialTimeout = const Duration(seconds: 2),
      Duration activateTimeout = const Duration(seconds: 2)}) async {
    connections++;
    return 0x1234;
  }

  @override
  Future<void> disconnect() async {}
  @override
  Future<List<MhdValue>> readLive(
          {Duration timeout = const Duration(seconds: 1)}) async =>
      [MhdValue(field: mhdFieldTable.first, raw: 800, value: 800)];
}

/// Controls NegotiateTelemetry's result — the Cubit's own upfront
/// negotiation used to decide whether to attach v2 session/sequence
/// identity, unrelated to TelemetryUploadService's own separately cached
/// negotiation before each delivery.
class FakeTelemetryRepository implements ITelemetryRepository {
  final int? version;
  Completer<int>? pending;
  FakeTelemetryRepository(this.version);
  @override
  Future<int> negotiate({required TelemetryConfig config}) async {
    if (pending != null) return pending!.future;
    if (version == null) throw Exception('offline');
    return version!;
  }

  @override
  Future<void> flushBuffer({required TelemetryConfig config}) async {}
  @override
  Future<bool> send(
          {required TelemetrySample sample,
          required TelemetryConfig config}) async =>
      false;
}

/// A fake ITelemetryUploadService: records every enqueued sample in order
/// and, via [stopCallback], lets a test end the cubit's read loop after a
/// specific enqueue (mirrors the pre-Phase-3b fake's role of driving the
/// loop to a deterministic stop without any real Duration-based waiting).
class FakeTelemetryUploadService implements ITelemetryUploadService {
  final samples = <TelemetrySample>[];
  late void Function() stopCallback;
  bool startCalled = false;
  bool stopCalled = false;

  @override
  Future<void> start(
      {required TelemetryConfig config, required Duration interval}) async {
    startCalled = true;
  }

  @override
  void enqueue(TelemetrySample sample) {
    samples.add(sample);
    if (samples.length.isEven) stopCallback();
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
  }

  @override
  TelemetryUploadStatus get status => const TelemetryUploadStatus();
}

void main() {
  test(
      'stop during negotiation prevents acquisition and clears connecting state',
      () async {
    final vehicle = FakeVehicle();
    final telemetryRepo = FakeTelemetryRepository(2)..pending = Completer<int>();
    final uploadService = FakeTelemetryUploadService();
    final cubit = ConnectionCubit(
        connectToVehicle: ConnectToVehicle(vehicle),
        disconnectFromVehicle: DisconnectFromVehicle(vehicle),
        readLiveSample: ReadLiveSample(vehicle),
        telemetryUploadService: uploadService,
        negotiateTelemetry: NegotiateTelemetry(telemetryRepo));
    addTearDown(cubit.close);
    final running = cubit.start(
        address: 'mock',
        port: 13400,
        deviceId: 'android',
        telemetryConfig:
            const TelemetryConfig(endpoint: '', apiKey: '', bufferPath: ''));
    cubit.stop();
    telemetryRepo.pending!.complete(2);
    await running;
    expect(vehicle.connections, 0);
    expect(uploadService.samples, isEmpty);
    expect(uploadService.startCalled, isFalse);
    expect(cubit.state.status, ConnectionStatus.stopped);
  });

  for (final version in [2, 1, null]) {
    test('producer session and sequence with negotiated $version', () async {
      final vehicle = FakeVehicle();
      final telemetryRepo = FakeTelemetryRepository(version);
      final uploadService = FakeTelemetryUploadService();
      final cubit = ConnectionCubit(
          connectToVehicle: ConnectToVehicle(vehicle),
          disconnectFromVehicle: DisconnectFromVehicle(vehicle),
          readLiveSample: ReadLiveSample(vehicle),
          telemetryUploadService: uploadService,
          negotiateTelemetry: NegotiateTelemetry(telemetryRepo));
      uploadService.stopCallback = cubit.stop;
      addTearDown(cubit.close);
      for (var run = 0; run < 2; run++) {
        await cubit.start(
            address: 'mock',
            port: 13400,
            deviceId: 'android',
            telemetryConfig:
                const TelemetryConfig(endpoint: '', apiKey: '', bufferPath: ''),
            sampleInterval: Duration.zero);
      }
      final samples = uploadService.samples;
      expect(samples.length, 4);
      for (final sample in samples) {
        sample.validate();
      }
      if (version == 1) {
        expect(
            samples.every((sample) =>
                sample.session == null &&
                sample.sequence == null &&
                sample.version == 0),
            isTrue);
      } else {
        expect(samples.map((sample) => sample.sequence), [0, 1, 0, 1]);
        expect(samples[0].session, samples[1].session);
        expect(samples[2].session, samples[3].session);
        expect(samples[0].session!.id, isNot(samples[2].session!.id));
      }
    });
  }
}
