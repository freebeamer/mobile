import 'dart:collection';

import '../../data/models/telemetry_sample.dart';

/// Default capacity for [AcquisitionQueue] — mirrors
/// pkg/telemetry.DefaultQueueCapacity.
const defaultQueueCapacity = 32;

/// A small, bounded, in-memory handoff between sample acquisition (reading
/// the adapter) and durable spooling (writing to disk) — the Dart mirror of
/// pkg/telemetry.AcquisitionQueue. It exists only to keep a momentary
/// spool-write stall off the acquisition loop; the spool file, not this
/// queue, is the actual durable backlog (see
/// docs/live-data-and-vehicle-mapping-plan.md's Phase 3 section).
///
/// [push] never blocks: a full queue drops the oldest still-queued sample
/// and counts the drop. All methods are synchronous (no `await` inside),
/// so — unlike Go, where two goroutines can genuinely race on the same
/// channel — two Dart calls into this queue can never interleave with each
/// other; Dart's single-isolate cooperative scheduling only yields at an
/// `await`, and there are none here. The real hazard this queue still has
/// to guard against is the same one Go's channel handoff has: a consumer
/// can synchronously [tryPop] an item and then `await` doing something with
/// it (e.g. a disk write) — during that `await`, the queue reads empty even
/// though the item isn't durably handled yet. [drained] closes that gap by
/// requiring the consumer to call [markHandled] only once its own
/// processing of a popped item has actually finished.
class AcquisitionQueue {
  final int capacity;
  final Queue<TelemetrySample> _queue = Queue<TelemetrySample>();
  int _overflowCount = 0;
  int _sent = 0;
  int _handled = 0;

  AcquisitionQueue({int? capacity}) : capacity = capacity != null && capacity > 0 ? capacity : defaultQueueCapacity;

  /// Adds sample to the queue. Returns true if accepted without dropping
  /// anything; if the queue was full, the oldest queued sample was dropped
  /// (and [overflowCount] incremented) to make room, and this returns
  /// false.
  bool push(TelemetrySample sample) {
    var queued = true;
    if (_queue.length >= capacity) {
      _queue.removeFirst();
      _overflowCount++;
      _handled++; // the dropped sample will never reach a consumer
      queued = false;
    }
    _queue.add(sample);
    _sent++;
    return queued;
  }

  /// Removes and returns the oldest queued sample, or null if empty. The
  /// caller must call [markHandled] once it has fully finished processing
  /// the returned sample.
  TelemetrySample? tryPop() {
    if (_queue.isEmpty) return null;
    return _queue.removeFirst();
  }

  /// Records that the consumer has fully finished processing one item
  /// previously returned by [tryPop] (durably appended, or otherwise
  /// disposed of).
  void markHandled() => _handled++;

  /// Number of samples currently queued (popped or not).
  int get depth => _queue.length;

  /// How many samples have been dropped because the queue was full.
  int get overflowCount => _overflowCount;

  /// Whether every sample ever pushed has since been fully accounted for —
  /// either evicted by a later push, or popped and marked handled. Unlike
  /// `depth == 0`, this is correct against the gap between a consumer
  /// popping a value and finishing whatever `await`-ed work it does with
  /// it — see the class doc comment.
  bool get drained => _handled >= _sent;
}
