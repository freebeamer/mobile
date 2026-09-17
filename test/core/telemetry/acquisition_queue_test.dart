import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/core/telemetry/acquisition_queue.dart';
import 'package:freebeamer_mobile/data/models/telemetry_sample.dart';

TelemetrySample sampleFor(String id) =>
    TelemetrySample(deviceId: id, timestamp: DateTime.now(), values: const {});

void main() {
  test('push within capacity queues everything', () {
    final queue = AcquisitionQueue(capacity: 3);
    for (final id in ['a', 'b', 'c']) {
      expect(queue.push(sampleFor(id)), isTrue);
    }
    expect(queue.depth, 3);
    expect(queue.overflowCount, 0);
  });

  test('push drops the oldest queued sample on overflow', () {
    final queue = AcquisitionQueue(capacity: 2);
    queue.push(sampleFor('a'));
    queue.push(sampleFor('b'));
    expect(queue.push(sampleFor('c')), isFalse);
    expect(queue.overflowCount, 1);
    expect(queue.depth, 2);

    final first = queue.tryPop();
    expect(first!.deviceId, 'b'); // a should have been dropped
    final second = queue.tryPop();
    expect(second!.deviceId, 'c');
  });

  test('default capacity is defaultQueueCapacity', () {
    final queue = AcquisitionQueue();
    for (var i = 0; i < defaultQueueCapacity; i++) {
      expect(queue.push(sampleFor('s$i')), isTrue);
    }
    expect(queue.push(sampleFor('overflow')), isFalse);
  });

  test('tryPop returns null when empty', () {
    final queue = AcquisitionQueue(capacity: 2);
    expect(queue.tryPop(), isNull);
  });

  test('drained is false while a popped item is not yet marked handled', () {
    final queue = AcquisitionQueue(capacity: 2);
    queue.push(sampleFor('a'));
    expect(queue.drained, isFalse);
    final sample = queue.tryPop();
    expect(sample, isNotNull);
    // Popped but not yet marked handled: still not drained. This is the
    // exact gap a bare `depth == 0` check would miss.
    expect(queue.depth, 0);
    expect(queue.drained, isFalse);
    queue.markHandled();
    expect(queue.drained, isTrue);
  });

  test('an evicted sample counts toward drained without a consumer', () {
    final queue = AcquisitionQueue(capacity: 1);
    queue.push(sampleFor('a'));
    expect(queue.drained, isFalse);
    queue.push(sampleFor('b')); // evicts 'a'
    // 'a' was evicted (never reaches a consumer), 'b' is still queued and
    // not yet popped/handled.
    expect(queue.drained, isFalse);
    queue.markHandled(); // consumer finishes handling 'b'
    expect(queue.drained, isTrue);
  });
}
