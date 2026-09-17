import 'dart:convert';
import 'dart:typed_data';

import 'package:freebeamer_mobile/core/error/exceptions.dart';
import 'package:freebeamer_mobile/data/datasources/device_auth_remote_data_source.dart';
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

  /// Simulates the relay rejecting the current session token: the next
  /// N post()/negotiate() calls throw TelemetryAuthException instead of
  /// the normal shouldFail/negotiateError logic, regardless of apiKey —
  /// a real test asserting the retry actually installed a *new* token
  /// should check the apiKey seen on the call that finally succeeds via
  /// [postedApiKeys].
  int authFailuresRemaining = 0;
  final List<String> postedApiKeys = [];

  @override
  Future<int> negotiate(
      {required String endpoint,
      required String apiKey,
      Duration timeout = const Duration(seconds: 5)}) async {
    negotiateCalls++;
    if (delay != null) await Future.delayed(delay!());
    if (authFailuresRemaining > 0) {
      authFailuresRemaining--;
      throw TelemetryAuthException('simulated 401');
    }
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
    if (authFailuresRemaining > 0) {
      authFailuresRemaining--;
      throw TelemetryAuthException('simulated 401');
    }
    if (shouldFail != null && shouldFail!(sample)) {
      throw TelemetryException('simulated failure');
    }
    postedIds.add(sample.deviceId);
    postedApiKeys.add(apiKey);
    posted.add(sample);
  }
}

/// A fake IDeviceAuthRemoteDataSource — every call is a scripted return
/// value/error, no real HTTP.
class FakeDeviceAuthRemoteDataSource implements IDeviceAuthRemoteDataSource {
  PairResult Function()? pairResult;
  Object? pairError;
  Uint8List challengeNonce = Uint8List.fromList(List.filled(32, 7));
  Object? challengeError;
  String Function()? sessionTokenFor;
  Object? sessionError;
  int logoutCalls = 0;
  String? lastSessionClientId;
  Uint8List? lastSignature;

  @override
  Future<PairResult> pair({
    required String relayUrl,
    required String pairingToken,
    required Uint8List publicKey,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (pairError != null) throw pairError!;
    return pairResult?.call() ??
        const PairResult(clientId: 'client-1', displayName: 'Test Client');
  }

  @override
  Future<Uint8List> challenge({
    required String relayUrl,
    required String clientId,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (challengeError != null) throw challengeError!;
    return challengeNonce;
  }

  @override
  Future<String> createSession({
    required String relayUrl,
    required String clientId,
    required Uint8List signature,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    lastSessionClientId = clientId;
    lastSignature = signature;
    if (sessionError != null) throw sessionError!;
    return sessionTokenFor?.call() ?? 'session-token';
  }

  @override
  Future<void> logout({
    required String relayUrl,
    required String sessionToken,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    logoutCalls++;
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
