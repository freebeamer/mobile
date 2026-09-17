import 'dart:convert';

import '../../core/error/exceptions.dart';
import '../../domain/repositories/telemetry_repository.dart';
import '../datasources/telemetry_local_data_source.dart';
import '../datasources/telemetry_remote_data_source.dart';
import '../models/telemetry_config.dart';
import '../models/telemetry_sample.dart';

/// Mirrors pkg/telemetry.Uploader.Send/FlushBuffer exactly — see that
/// file's package doc for the full rationale (a client device on the
/// vehicle adapter's WiFi frequently can't also be on an
/// internet-providing WiFi at the same time).
class TelemetryRepositoryImpl implements ITelemetryRepository {
  final ITelemetryRemoteDataSource _remote;
  final ITelemetryLocalDataSource _local;

  TelemetryRepositoryImpl(this._remote, this._local);

  @override
  Future<int> negotiate({required TelemetryConfig config}) =>
      _remote.negotiate(endpoint: config.endpoint, apiKey: config.apiKey);

  @override
  Future<bool> send(
      {required TelemetrySample sample,
      required TelemetryConfig config}) async {
    if (config.endpoint.isNotEmpty) {
      try {
        await flushBuffer(config: config);
      } catch (_) {
        // Best-effort: _local.isEmpty below is what actually decides
        // whether the backlog is clear, not this call's own error.
      }
      if (await _local.isEmpty(config.bufferPath)) {
        try {
          await _remote.post(
              sample: sample, endpoint: config.endpoint, apiKey: config.apiKey);
          return true;
        } catch (_) {
          // fall through to buffering
        }
      }
    }
    await _local.append(sample, config.bufferPath);
    return false;
  }

  @override
  Future<void> flushBuffer({required TelemetryConfig config}) async {
    final lines = await _local.readLines(config.bufferPath);
    if (lines.isEmpty) return;

    var uploaded = 0;
    while (uploaded < lines.length) {
      TelemetrySample sample;
      try {
        sample = TelemetrySample.fromJson(
            jsonDecode(lines[uploaded]) as Map<String, dynamic>);
      } catch (_) {
        break; // Preserve unreadable/unsupported records for inspection.
      }
      try {
        await _remote.post(
            sample: sample, endpoint: config.endpoint, apiKey: config.apiKey);
      } catch (_) {
        break;
      }
      uploaded++;
    }

    await _local.rewrite(lines.sublist(uploaded), config.bufferPath);
    if (uploaded < lines.length) {
      throw TelemetryException(
          '${lines.length - uploaded} sample(s) still buffered');
    }
  }
}
