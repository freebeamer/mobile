import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/data/models/telemetry_config.dart';
import 'package:freebeamer_mobile/data/models/telemetry_sample.dart';
import 'package:freebeamer_mobile/data/repositories/telemetry_repository_impl.dart';
import 'package:freebeamer_mobile/core/error/exceptions.dart';

import '../../support/fakes.dart';

void main() {
  late FakeRemoteDataSource remote;
  late FakeLocalDataSource local;
  late TelemetryRepositoryImpl repository;
  const config = TelemetryConfig(
      endpoint: 'http://relay.example/v1/telemetry',
      apiKey: '',
      bufferPath: 'buffer.jsonl');

  TelemetrySample sampleFor(String id) => TelemetrySample(
      deviceId: id, timestamp: DateTime.now(), values: const {});

  setUp(() {
    remote = FakeRemoteDataSource();
    local = FakeLocalDataSource();
    repository = TelemetryRepositoryImpl(remote, local);
  });

  test('send delivers live when reachable', () async {
    final delivered =
        await repository.send(sample: sampleFor('a'), config: config);
    expect(delivered, isTrue);
    expect(remote.postedIds, ['a']);
    expect(await local.isEmpty(config.bufferPath), isTrue);
  });

  test('send buffers when the remote data source throws', () async {
    remote.shouldFail = (_) => true;
    final delivered =
        await repository.send(sample: sampleFor('a'), config: config);
    expect(delivered, isFalse);
    expect(remote.postedIds, isEmpty);
    expect(await local.isEmpty(config.bufferPath), isFalse);
  });

  test('send with an empty endpoint always buffers', () async {
    const noEndpointConfig =
        TelemetryConfig(endpoint: '', apiKey: '', bufferPath: 'buffer.jsonl');
    final delivered =
        await repository.send(sample: sampleFor('a'), config: noEndpointConfig);
    expect(delivered, isFalse);
    expect(remote.postedIds, isEmpty);
  });

  test('flushBuffer drains in order', () async {
    for (final id in ['a', 'b', 'c']) {
      await local.append(sampleFor(id), config.bufferPath);
    }
    await repository.flushBuffer(config: config);
    expect(remote.postedIds, ['a', 'b', 'c']);
    expect(await local.isEmpty(config.bufferPath), isTrue);
  });

  test('flushBuffer stops at the first failure and preserves the rest',
      () async {
    for (final id in ['a', 'b', 'c']) {
      await local.append(sampleFor(id), config.bufferPath);
    }
    remote.shouldFail = (sample) => sample.deviceId == 'b';

    await expectLater(repository.flushBuffer(config: config),
        throwsA(isA<TelemetryException>()));
    expect(remote.postedIds, ['a']);
    final remaining = await local.readLines(config.bufferPath);
    expect(remaining, hasLength(2));
  });

  test('send drains an existing backlog before delivering the new sample',
      () async {
    await local.append(sampleFor('old'), config.bufferPath);

    final delivered =
        await repository.send(sample: sampleFor('new'), config: config);
    expect(delivered, isTrue);
    expect(remote.postedIds, ['old', 'new']);
  });

  test(
      'send does not deliver the new sample live if the backlog fails to drain',
      () async {
    await local.append(sampleFor('old'), config.bufferPath);
    remote.shouldFail = (sample) => sample.deviceId == 'old';

    final delivered =
        await repository.send(sample: sampleFor('new'), config: config);
    expect(delivered, isFalse);
    expect(remote.postedIds, isEmpty);
    final remaining = await local.readLines(config.bufferPath);
    expect(remaining, hasLength(2)); // old (still failing) + new
  });
}
