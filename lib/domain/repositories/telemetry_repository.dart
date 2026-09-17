import '../../data/models/telemetry_config.dart';
import '../../data/models/telemetry_sample.dart';

/// Delivers TelemetrySamples to a FreeBeamer relay, falling back to a
/// local buffer when delivery isn't currently possible. Mirrors
/// pkg/telemetry.Uploader's contract exactly — see
/// pkg/telemetry/uploader.go's package doc for why the fallback
/// exists (a client device on the vehicle adapter's WiFi frequently
/// can't also be on an internet-providing WiFi at the same time).
abstract class ITelemetryRepository {
  Future<int> negotiate({required TelemetryConfig config});

  /// Delivers sample live if config.endpoint is reachable and no
  /// backlog remains ahead of it (any existing backlog is drained
  /// first, in order); otherwise sample is buffered at
  /// config.bufferPath. Returns true if delivered live.
  Future<bool> send(
      {required TelemetrySample sample, required TelemetryConfig config});

  /// Attempts to upload every sample currently buffered at
  /// config.bufferPath, in order, stopping at the first delivery
  /// failure so ordering and at-least-once delivery are preserved.
  /// Throws if any samples remain buffered afterward.
  Future<void> flushBuffer({required TelemetryConfig config});
}
