import 'dart:convert';

import 'package:freebeamer_mobile/core/error/exceptions.dart';
import 'package:freebeamer_mobile/data/datasources/telemetry_local_data_source.dart';
import 'package:freebeamer_mobile/data/datasources/telemetry_remote_data_source.dart';
import 'package:freebeamer_mobile/data/models/telemetry_sample.dart';

/// Shared, reusable test doubles for the telemetry data layer — promoted
/// out of telemetry_repository_impl_test.dart (where they were originally
/// private) so telemetry_upload_service_test.dart and other tests that sit
/// on the same two interfaces don't reimplement them. Mirrors the Go side's
/// own reusable httptest.Server-based helpers in pkg/telemetry/uploader_test.go.

/// An in-memory fake ITelemetryRemoteDataSource. [shouldFail] decides
/// whether post() throws for a given sample; [negotiateVersion]/
/// [negotiateError] control negotiate()'s result; [delay], if set, is
/// awaited before either call returns — used to simulate a slow relay.
class FakeRemoteDataSource implements ITelemetryRemoteDataSource {
  final List<String> postedIds = [];
  final List<TelemetrySample> posted = [];
  bool Function(TelemetrySample sample)? shouldFail;
  int negotiateVersion = 2;
  Object? negotiateError;
  int negotiateCalls = 0;
  Duration Function()? delay;

  @override
  Future<int> negotiate(
      {required String endpoint,
      required String apiKey,
      Duration timeout = const Duration(seconds: 5)}) async {
    negotiateCalls++;
    if (delay != null) await Future.delayed(delay!());
    if (negotiateError != null) throw negotiateError!;
    return negotiateVersion;
  }

  @override
  Future<void> post({
    required TelemetrySample sample,
    required String endpoint,
    required String apiKey,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (delay != null) await Future.delayed(delay!());
    if (shouldFail != null && shouldFail!(sample)) {
      throw TelemetryException('simulated failure');
    }
    postedIds.add(sample.deviceId);
    posted.add(sample);
  }
}

/// An in-memory fake ITelemetryLocalDataSource, keyed by path — a plain
/// list of JSON lines standing in for a real file, enforcing the same
/// byte-cap/overflow-policy contract as TelemetryLocalDataSourceImpl.
class FakeLocalDataSource implements ITelemetryLocalDataSource {
  final Map<String, List<String>> byPath = {};

  @override
  Future<bool> isEmpty(String path) async =>
      (byPath[path] ?? const []).isEmpty;

  @override
  Future<bool> append(TelemetrySample sample, String path,
      {int maxBytes = defaultSpoolMaxBytes,
      SpoolOverflowPolicy onFull = SpoolOverflowPolicy.drop}) async {
    final lines = byPath[path] ??= [];
    final line = jsonEncode(sample.toJson());
    final currentSize =
        lines.fold<int>(0, (sum, l) => sum + utf8.encode(l).length + 1);
    if (currentSize + utf8.encode(line).length + 1 > maxBytes) {
      if (onFull == SpoolOverflowPolicy.stop) {
        throw SpoolFullException('fake spool full');
      }
      return false;
    }
    lines.add(line);
    return true;
  }

  @override
  Future<List<String>> readLines(String path) async =>
      List.unmodifiable(byPath[path] ?? const []);

  @override
  Future<int> pendingCount(String path) async =>
      (byPath[path] ?? const []).length;

  @override
  Future<void> rewrite(List<String> lines, String path) async {
    byPath[path] = List.of(lines);
  }
}
