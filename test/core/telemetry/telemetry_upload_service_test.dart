import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/core/telemetry/telemetry_upload_service.dart';
import 'package:freebeamer_mobile/core/telemetry/telemetry_upload_status.dart';
import 'package:freebeamer_mobile/data/models/telemetry_config.dart';
import 'package:freebeamer_mobile/data/models/telemetry_sample.dart';

import '../../support/fakes.dart';

TelemetrySample sampleFor(String id, {DateTime? timestamp}) => TelemetrySample(
    deviceId: id, timestamp: timestamp ?? DateTime.now(), values: const {});

/// Polls cond (which may itself be async) until it's true or timeout
/// elapses, whichever first — this repo's established pattern for
/// deterministic async test waits without fake_async (see
/// telemetry_negotiation_test.dart's own restart-simulation tests).
Future<void> waitFor(FutureOr<bool> Function() cond,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await cond()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late FakeRemoteDataSource remote;
  late FakeLocalDataSource local;
  late TelemetryUploadServiceImpl service;
  const config = TelemetryConfig(
      endpoint: 'http://relay.example/v1/telemetry',
      apiKey: '',
      bufferPath: 'buffer.jsonl');

  setUp(() {
    remote = FakeRemoteDataSource();
    local = FakeLocalDataSource();
    service = TelemetryUploadServiceImpl(remote, local);
  });

  test('enqueued samples are delivered in order', () async {
    await service.start(config: config, interval: const Duration(milliseconds: 10));
    for (final id in ['a', 'b', 'c']) {
      service.enqueue(sampleFor(id));
    }
    await waitFor(() => remote.postedIds.length == 3);
    await service.stop();
    expect(remote.postedIds, ['a', 'b', 'c']);
    expect(await local.pendingCount(config.bufferPath), 0);
  });

  test('recovers after a delivery failure via backoff', () async {
    var calls = 0;
    remote.shouldFail = (_) {
      calls++;
      return calls == 1;
    };
    await service.start(config: config, interval: const Duration(milliseconds: 10));
    service.enqueue(sampleFor('a'));
    // Wait for the sample to actually show up delivered, not merely for
    // the spool to read empty (which is trivially true before the sample
    // is even appended — the same premature-emptiness pitfall
    // AcquisitionQueue.drained exists to guard the service's own internals
    // against, here on the test side of the fence instead).
    await waitFor(() => remote.postedIds.contains('a'));
    await service.stop();
    expect(calls, greaterThanOrEqualTo(2));
    expect(remote.postedIds, ['a']);
  });

  test('stop cancels promptly without waiting out a full backoff', () async {
    remote.shouldFail = (_) => true;
    await service.start(config: config, interval: const Duration(milliseconds: 10));
    service.enqueue(sampleFor('a'));
    await waitFor(() => service.status.uploadState == TelemetryUploadState.backingOff);
    final started = DateTime.now();
    await service.stop();
    final elapsed = DateTime.now().difference(started);
    expect(elapsed, lessThan(const Duration(milliseconds: 500)));
    expect(service.status.uploadState, TelemetryUploadState.stopped);
  });

  test('a fully drained catch-up backlog reports 100% progress', () async {
    final old = DateTime.now().subtract(const Duration(hours: 1));
    for (var i = 0; i < 5; i++) {
      await local.append(sampleFor('old-$i', timestamp: old), config.bufferPath);
    }
    await service.start(config: config, interval: const Duration(milliseconds: 10));
    await waitFor(() async => (await local.pendingCount(config.bufferPath)) == 0);
    await waitFor(() => service.status.catchupProgress == 1);
    await service.stop();
    expect(service.status.catchupInProgress, isFalse);
    // Every delivered sample here was stale catch-up, not live.
    expect(service.status.lastFreshSampleAt, isNull);
  });

  test('reprovisioning to a different destination does not touch the original spool',
      () async {
    // Two independent services, simulating two sessions against different
    // destinations sharing the same on-disk local data source instance but
    // distinct bufferPaths (the isolation itself is handled by
    // resolveSpoolPath/buildTelemetryConfig upstream — this test just
    // confirms the service never cross-writes between two configured
    // paths it's given).
    const configA = TelemetryConfig(
        endpoint: 'http://relay.example/v1/telemetry',
        apiKey: 'a',
        bufferPath: 'buffer-a.jsonl');
    const configB = TelemetryConfig(
        endpoint: 'http://relay.example/v1/telemetry',
        apiKey: 'b',
        bufferPath: 'buffer-b.jsonl');
    remote.shouldFail = (_) => true;

    final serviceA = TelemetryUploadServiceImpl(remote, local);
    await serviceA.start(config: configA, interval: const Duration(milliseconds: 10));
    serviceA.enqueue(sampleFor('a'));
    await waitFor(() async => (await local.pendingCount(configA.bufferPath)) == 1);
    await serviceA.stop();

    final serviceB = TelemetryUploadServiceImpl(remote, local);
    await serviceB.start(config: configB, interval: const Duration(milliseconds: 10));
    serviceB.enqueue(sampleFor('b'));
    await waitFor(() async => (await local.pendingCount(configB.bufferPath)) == 1);
    await serviceB.stop();

    expect(await local.pendingCount(configA.bufferPath), 1);
    expect(await local.pendingCount(configB.bufferPath), 1);
    final linesA = await local.readLines(configA.bufferPath);
    expect(linesA.single, contains('"device_id":"a"'));
  });

  test(
      'a sample enqueued while the uploader is mid-delivery is not lost when the spool empties',
      () async {
    // Regression test for a real crash found via manual device testing:
    // the uploader's rewrite() (which deletes the spool file once it's
    // fully drained) raced with the spool-writer's concurrent append,
    // throwing PathNotFoundException. remote.delay lets us reliably win
    // that race by keeping the uploader's single in-flight delivery open
    // long enough for the spool-writer to enqueue and append a second
    // sample before the first delivery's rewrite step runs.
    remote.delay = () => const Duration(milliseconds: 200);
    await service.start(config: config, interval: const Duration(milliseconds: 10));
    service.enqueue(sampleFor('a'));
    await waitFor(() => service.status.uploadState == TelemetryUploadState.uploading);
    service.enqueue(sampleFor('b')); // enqueued while 'a' is still in flight
    await waitFor(() => remote.postedIds.length == 2, timeout: const Duration(seconds: 3));
    await service.stop();
    expect(remote.postedIds, ['a', 'b']);
    expect(await local.pendingCount(config.bufferPath), 0);
  });

  test('starting again for a different config while running throws', () async {
    const other = TelemetryConfig(
        endpoint: 'http://relay.example/v1/telemetry',
        apiKey: 'different',
        bufferPath: 'buffer.jsonl');
    await service.start(config: config, interval: const Duration(milliseconds: 10));
    expect(
        () => service.start(config: other, interval: const Duration(milliseconds: 10)),
        throwsA(isA<StateError>()));
    await service.stop();
  });

  test('a single 401 triggers exactly one silent reauthenticate-and-retry',
      () async {
    remote.authFailuresRemaining = 1;
    var reauthCalls = 0;
    await service.start(
      config: config,
      interval: const Duration(milliseconds: 10),
      reauthenticate: () async {
        reauthCalls++;
        return 'refreshed-token';
      },
    );
    service.enqueue(sampleFor('a'));
    await waitFor(() => remote.postedIds.contains('a'));
    await service.stop();

    expect(reauthCalls, 1);
    expect(remote.postedApiKeys, ['refreshed-token']);
    // Delivery succeeded on the retry, so the sample never sat in the
    // backing-off state for the test to observe.
    expect(remote.postedIds, ['a']);
  });

  test('a second consecutive 401 falls through to normal backoff', () async {
    // The first post() fails, triggering the one-time reauth retry; that
    // retry's post() fails too (still-bad-token), so this must give up
    // rather than looping.
    remote.authFailuresRemaining = 2;
    var reauthCalls = 0;
    await service.start(
      config: config,
      interval: const Duration(milliseconds: 10),
      reauthenticate: () async {
        reauthCalls++;
        return 'still-bad-token';
      },
    );
    service.enqueue(sampleFor('a'));
    await waitFor(() => service.status.uploadState == TelemetryUploadState.backingOff);
    await service.stop();

    expect(reauthCalls, 1); // not retried a second time in the same attempt
    expect(remote.postedIds, isEmpty);
  });

  test('a null reauthenticate result gives up rather than retrying forever',
      () async {
    remote.authFailuresRemaining = 1;
    await service.start(
      config: config,
      interval: const Duration(milliseconds: 10),
      reauthenticate: () async => null, // e.g. the pairing was forgotten
    );
    service.enqueue(sampleFor('a'));
    await waitFor(() => service.status.uploadState == TelemetryUploadState.backingOff);
    await service.stop();

    expect(remote.postedIds, isEmpty);
  });

  test('no reauthenticate callback just fails through like any other error',
      () async {
    remote.authFailuresRemaining = 1;
    await service.start(config: config, interval: const Duration(milliseconds: 10));
    service.enqueue(sampleFor('a'));
    await waitFor(() => service.status.uploadState == TelemetryUploadState.backingOff);
    await service.stop();

    expect(remote.postedIds, isEmpty);
  });
}
