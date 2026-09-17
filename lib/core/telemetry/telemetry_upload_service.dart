import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../core/error/exceptions.dart';
import '../../data/datasources/telemetry_local_data_source.dart';
import '../../data/datasources/telemetry_remote_data_source.dart';
import '../../data/models/telemetry_config.dart';
import '../../data/models/telemetry_sample.dart';
import '../../data/models/telemetry_session.dart' show telemetryVersion;
import 'acquisition_queue.dart';
import 'telemetry_upload_status.dart';

/// Bounds the delay between delivery retries — mirrors
/// pkg/telemetry.DefaultInitialBackoff/DefaultMaxBackoff. "Bounded
/// retries" means a bounded backoff delay, not a bounded attempt count:
/// TelemetryUploadService never gives up on a spooled sample, since
/// abandoning one would violate the never-silently-discard requirement in
/// docs/live-data-and-vehicle-mapping-plan.md's Phase 3 section.
const defaultInitialBackoff = Duration(seconds: 1);
const defaultMaxBackoff = Duration(seconds: 60);

/// How long a cached capability-negotiation result is trusted before
/// re-checking the relay — mirrors pkg/telemetry's negotiationCacheTTL.
const negotiationCacheTtl = Duration(minutes: 5);

/// How often the uploader checks the spool again after finding it empty,
/// and the granularity cancellable waits are polled at.
const idlePollInterval = Duration(milliseconds: 200);
const _cancelPollGranularity = Duration(milliseconds: 50);

/// A minimal async mutex serializing file operations against the same
/// spool file between the spool-writer and uploader loops — the Dart
/// analogue of pkg/telemetry.Spool's sync.Mutex. This is necessary, not
/// defensive: Dart's single-isolate cooperative scheduling only prevents
/// interleaving within a span of code with no `await`, and every
/// ITelemetryLocalDataSource method awaits real file I/O. Confirmed
/// directly on a real device during this feature's development: without
/// this lock, the uploader's rewrite() deleting an emptied spool file
/// could race with the spool-writer's concurrent readLines() (called via
/// pendingCount) between its exists-check and its read, throwing an
/// unhandled PathNotFoundException and crashing the app — the exact class
/// of concurrency bug pkg/telemetry.Spool's mutex exists to prevent,
/// missed here on the first pass because Dart's lack of OS threads made it
/// easy to assume file operations couldn't interleave the way Go's
/// goroutines obviously can. They do, once two loops both `await` on them.
class _AsyncMutex {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// The minimum staleness (delivery time minus the sample's own acquisition
/// timestamp) at which a delivered sample counts as catch-up rather than
/// live, for the given configured acquisition interval — mirrors
/// pkg/telemetry.CatchupThreshold exactly. Computed only from timestamps
/// the device itself produced, per docs/telemetry-v2-contract.md's warning
/// that network receipt can't prove freshness.
Duration catchupThreshold(Duration interval) {
  final threshold = interval * 2;
  const minimum = Duration(seconds: 2);
  return threshold < minimum ? minimum : threshold;
}

/// Drives sample acquisition/spool/upload for one streaming session —
/// abstracted so ConnectionCubit can be tested against a lightweight fake
/// instead of TelemetryUploadServiceImpl's real async loops and file/network
/// I/O, matching this codebase's interface + Impl convention (see e.g.
/// ITelemetryLocalDataSource).
abstract class ITelemetryUploadService {
  /// Starts the spool-writer and uploader loops for one session against
  /// config. A repeat call with the identical config is a no-op; a repeat
  /// call with a *different* config while still running throws — this
  /// should be unreachable in practice, since ConnectionCubit already
  /// prevents overlapping sessions, but turns any future violation of that
  /// invariant into a loud error instead of a silent credential leak
  /// across destinations.
  Future<void> start({required TelemetryConfig config, required Duration interval});

  /// Adds sample to the in-memory queue. Synchronous and non-blocking: a
  /// full queue drops the oldest queued sample (counted via [status],
  /// never silent). Must be called after [start].
  void enqueue(TelemetrySample sample);

  /// Requests both loops to stop and waits for them to actually finish.
  /// Any single in-flight HTTP request already started is allowed to
  /// finish rather than aborted mid-request (bounded by that request's own
  /// timeout) — a deliberate trade-off, not a bug. Does not wait for the
  /// spool to fully drain (no CLI-style --drain-timeout equivalent):
  /// unlike the CLI's bounded --count runs, a mobile session's stop is
  /// user- or backgrounding-driven with no natural finite endpoint to wait
  /// against, and anything undelivered stays safely spooled for the next
  /// session, matching this app's existing fire-and-forget-across-sessions
  /// design.
  Future<void> stop();

  /// The current pipeline state — queue/spool depth, upload state,
  /// catch-up progress, measured acquisition rate, drop counts.
  TelemetryUploadStatus get status;
}

/// Continuously drains a durable on-disk spool over HTTP via the injected
/// ITelemetryRemoteDataSource, with cached capability negotiation and
/// bounded-delay retry/backoff, while a separate loop drains a small
/// bounded in-memory AcquisitionQueue into that same spool — the Dart
/// mirror of pkg/telemetry.UploaderService (see that file's doc comment
/// for the full architecture rationale). No Isolate: the work being
/// decoupled from acquisition is I/O-bound (HTTP/file awaits), so two
/// independent async loops on the main isolate already achieve the
/// decoupling, as long as the acquisition loop itself only ever calls the
/// synchronous [enqueue].
class TelemetryUploadServiceImpl implements ITelemetryUploadService {
  final ITelemetryRemoteDataSource _remote;
  final ITelemetryLocalDataSource _local;

  TelemetryUploadServiceImpl(this._remote, this._local);

  AcquisitionQueue? _queue;
  final _fileLock = _AsyncMutex();
  TelemetryConfig? _config;
  Duration _interval = const Duration(milliseconds: 200);
  bool _running = false;
  bool _stopRequested = false;
  Future<void>? _writerLoop;
  Future<void>? _uploaderLoop;

  TelemetryUploadStatus _status = const TelemetryUploadStatus();
  @override
  TelemetryUploadStatus get status => _status;

  int? _negotiatedVersion;
  DateTime? _negotiatedAt;

  // Rolling window of recent acquisition timestamps, for a measured (not
  // configured) acquisition rate — mirrors pkg/telemetry.Status.RecordAcquired.
  static const _rateWindow = 20;
  final List<DateTime> _acquiredAt = [];

  /// Starts the spool-writer and uploader loops for one session against
  /// config. A repeat call with the identical config is a no-op; a repeat
  /// call with a *different* config while still running throws — this
  /// should be unreachable in practice, since ConnectionCubit already
  /// prevents overlapping sessions, but turns any future violation of that
  /// invariant into a loud error instead of a silent credential leak
  /// across destinations.
  @override
  Future<void> start(
      {required TelemetryConfig config, required Duration interval}) async {
    if (_running) {
      if (_config != config) {
        throw StateError(
            'TelemetryUploadService already running for a different destination');
      }
      return;
    }
    _running = true;
    _stopRequested = false;
    _config = config;
    _interval = interval;
    _queue = AcquisitionQueue();
    _status = const TelemetryUploadStatus();
    _negotiatedVersion = null;
    _negotiatedAt = null;
    _writerLoop = _runSpoolWriter();
    _uploaderLoop = _runUploader();
  }

  /// Adds sample to the in-memory queue. Synchronous and non-blocking: a
  /// full queue drops the oldest queued sample (counted via the status,
  /// never silent). Must be called after [start].
  @override
  void enqueue(TelemetrySample sample) {
    final queue = _queue;
    if (queue == null) {
      throw StateError('TelemetryUploadService.enqueue called before start()');
    }
    queue.push(sample);
    _acquiredAt.add(DateTime.now());
    if (_acquiredAt.length > _rateWindow) {
      _acquiredAt.removeAt(0);
    }
    _status = _status.copyWith(
        queueDepth: queue.depth,
        queueDroppedCount: queue.overflowCount,
        acquisitionRateHz: _measuredRateHz());
  }

  double _measuredRateHz() {
    if (_acquiredAt.length < 2) return 0;
    final span =
        _acquiredAt.last.difference(_acquiredAt.first).inMicroseconds / 1e6;
    if (span <= 0) return 0;
    return (_acquiredAt.length - 1) / span;
  }

  /// Requests both loops to stop and waits for them to actually finish.
  /// Any single in-flight HTTP request already started is allowed to
  /// finish rather than aborted mid-request (bounded by that request's own
  /// timeout) — a deliberate trade-off, not a bug.
  @override
  Future<void> stop() async {
    if (!_running) return;
    _stopRequested = true;
    await Future.wait([
      if (_writerLoop != null) _writerLoop!,
      if (_uploaderLoop != null) _uploaderLoop!,
    ]);
    _running = false;
    _status = _status.copyWith(uploadState: TelemetryUploadState.stopped);
  }

  Future<void> _runSpoolWriter() async {
    final queue = _queue!;
    final config = _config!;
    while (true) {
      final sample = queue.tryPop();
      if (sample == null) {
        if (_stopRequested) return;
        await Future.delayed(_cancelPollGranularity);
        continue;
      }
      try {
        final wrote = await _fileLock
            .run(() => _local.append(sample, config.bufferPath));
        if (!wrote) {
          _status = _status.copyWith(
              spoolDroppedCount: _status.spoolDroppedCount + 1);
        }
      } catch (e) {
        _status = _status.copyWith(lastError: 'spool: $e');
      } finally {
        queue.markHandled();
      }
      final pending =
          await _fileLock.run(() => _local.pendingCount(config.bufferPath));
      _status = _status.copyWith(
          queueDepth: queue.depth,
          queueDroppedCount: queue.overflowCount,
          spoolPending: pending);
    }
  }

  Future<void> _runUploader() async {
    final config = _config!;
    var backoff = defaultInitialBackoff;
    final threshold = catchupThreshold(_interval);
    var catchingUp = false;
    var catchupStart = 0;

    while (!_stopRequested) {
      final lines =
          await _fileLock.run(() => _local.readLines(config.bufferPath));
      final startPending = lines.length;
      _status = _status.copyWith(
          spoolPending: startPending, uploadState: TelemetryUploadState.uploading);

      if (lines.isEmpty) {
        _status = _status.copyWith(uploadState: TelemetryUploadState.idle);
        if (!await _cancellableDelay(idlePollInterval)) return;
        continue;
      }

      var delivered = 0;
      String? failure;
      for (; delivered < lines.length; delivered++) {
        if (_stopRequested) break; // leave the rest spooled; don't start a new request
        TelemetrySample sample;
        try {
          sample = TelemetrySample.fromJson(
              jsonDecode(lines[delivered]) as Map<String, dynamic>);
        } catch (e) {
          failure = 'unreadable record: $e';
          break;
        }
        try {
          final deliveredAt = await _deliver(sample);
          final catchup = deliveredAt.difference(sample.timestamp) > threshold;
          if (catchup && !catchingUp) {
            catchingUp = true;
            catchupStart = startPending;
          }
          if (!catchup) {
            _status = _status.copyWith(lastFreshSampleAt: deliveredAt);
          }
        } catch (e) {
          failure = e.toString();
          break;
        }
      }

      // Re-read the file's current tail rather than reusing the stale
      // `lines` snapshot before rewriting: the spool-writer may have
      // appended a new sample while the deliveries above were in flight
      // (deliberately not covered by _fileLock, since those are network
      // calls). Removing exactly `delivered` entries from the *current*
      // front preserves any such concurrent append — mirrors
      // pkg/telemetry.Spool.Drain's identical fix for the identical race.
      final newPending = await _fileLock.run(() async {
        final current = await _local.readLines(config.bufferPath);
        final done = delivered > current.length ? current.length : delivered;
        await _local.rewrite(current.sublist(done), config.bufferPath);
        return current.length - done;
      });

      if (catchingUp) {
        final progress = catchupStart > 0
            ? (1 - newPending / catchupStart).clamp(0.0, 1.0)
            : 1.0;
        _status = _status.copyWith(
            catchupInProgress: newPending > 0,
            catchupProgress: progress,
            catchupPending: newPending);
        if (newPending == 0) catchingUp = false;
      } else {
        _status = _status.copyWith(
            catchupInProgress: false, catchupProgress: 0, catchupPending: newPending);
      }

      if (_stopRequested) return;

      if (failure != null) {
        _status = _status.copyWith(
            lastError: failure,
            uploadState: TelemetryUploadState.backingOff,
            spoolPending: newPending);
        if (!await _cancellableDelay(backoff)) return;
        backoff = _nextBackoff(backoff);
        continue;
      }

      _status = _status.copyWith(clearError: true, spoolPending: newPending);
      backoff = defaultInitialBackoff;
    }
  }

  Future<DateTime> _deliver(TelemetrySample sample) async {
    sample.validate();
    await _negotiateIfNeeded(sample);
    await _remote.post(
        sample: sample,
        endpoint: _config!.endpoint,
        apiKey: _config!.apiKey);
    return DateTime.now();
  }

  Future<void> _negotiateIfNeeded(TelemetrySample sample) async {
    if (sample.version != telemetryVersion) {
      return; // legacy samples: post() doesn't negotiate either.
    }
    final negotiatedAt = _negotiatedAt;
    if (_negotiatedVersion == telemetryVersion &&
        negotiatedAt != null &&
        DateTime.now().difference(negotiatedAt) < negotiationCacheTtl) {
      return;
    }
    final version = await _remote.negotiate(
        endpoint: _config!.endpoint, apiKey: _config!.apiKey);
    _negotiatedVersion = version;
    _negotiatedAt = DateTime.now();
    if (version != telemetryVersion) {
      throw TelemetryException('relay cannot preserve v2 sample identity');
    }
  }

  /// Waits for duration with jitter (+/-20%), applied for backoff, or
  /// plainly for the idle poll — checking [_stopRequested] every
  /// [_cancelPollGranularity] so [stop] doesn't have to wait out a long
  /// backoff. Returns false if the wait was cut short by a stop request.
  Future<bool> _cancellableDelay(Duration duration) async {
    final jitterFactor = (Random().nextDouble() * 0.4) - 0.2; // +/-20%
    final jittered = Duration(
        milliseconds:
            (duration.inMilliseconds * (1 + jitterFactor)).round());
    final wait = jittered.isNegative ? duration : jittered;
    final deadline = DateTime.now().add(wait);
    while (DateTime.now().isBefore(deadline)) {
      if (_stopRequested) return false;
      final remaining = deadline.difference(DateTime.now());
      await Future.delayed(
          remaining < _cancelPollGranularity ? remaining : _cancelPollGranularity);
    }
    return !_stopRequested;
  }

  Duration _nextBackoff(Duration current) {
    final next = current * 2;
    return next > defaultMaxBackoff ? defaultMaxBackoff : next;
  }
}
