import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/error/exceptions.dart';
import '../models/telemetry_sample.dart';
import '../models/telemetry_session.dart';

/// Delivers one TelemetrySample to a FreeBeamer relay's
/// POST /v1/telemetry. Mirrors pkg/telemetry.Uploader's post method
/// exactly — same JSON body shape, same Authorization header
/// convention. Throws TelemetryException (or lets a network exception
/// propagate) on any non-2xx response or failed request; the caller
/// (ITelemetryRepository) decides what that means (fall back to
/// buffering), matching pkg/telemetry.Uploader.Send's own division of
/// responsibility.
abstract class ITelemetryRemoteDataSource {
  Future<int> negotiate(
      {required String endpoint,
      required String apiKey,
      Duration timeout = const Duration(seconds: 5)});

  Future<void> post({
    required TelemetrySample sample,
    required String endpoint,
    required String apiKey,
    Duration timeout = const Duration(seconds: 5),
  });
}

class TelemetryRemoteDataSourceImpl implements ITelemetryRemoteDataSource {
  final http.Client _client;
  TelemetryRemoteDataSourceImpl({http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<int> negotiate(
      {required String endpoint,
      required String apiKey,
      Duration timeout = const Duration(seconds: 5)}) async {
    if (endpoint.isEmpty) return telemetryVersion;
    final uri = Uri.parse(endpoint);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        !uri.path.endsWith('/telemetry')) {
      throw const FormatException(
          'Capability check requires an HTTP(S) /telemetry endpoint');
    }
    final capabilitiesUri = uri.replace(
        path:
            '${uri.path.substring(0, uri.path.length - '/telemetry'.length)}/capabilities',
        query: '',
        fragment: '');
    final request = http.Request('GET', capabilitiesUri)
      ..followRedirects = false;
    if (apiKey.isNotEmpty) request.headers['Authorization'] = 'Bearer $apiKey';
    final response = await (() async {
      final stream = await _client.send(request);
      final bytes = <int>[];
      await for (final chunk in stream.stream) {
        bytes.addAll(chunk);
        if (bytes.length > 64 * 1024) {
          throw const FormatException('Capabilities response too large');
        }
      }
      return http.Response.bytes(bytes, stream.statusCode);
    })()
        .timeout(timeout);
    if (response.statusCode == 404 || response.statusCode == 405) return 1;
    if (response.statusCode != 200) {
      throw TelemetryException(
          'capability check: status ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final versions = body['telemetry_versions'] as List<dynamic>;
    final catalogs = body['catalogs'] as List<dynamic>? ?? [];
    final compatibleCatalog = catalogs.any((entry) =>
        entry is Map &&
        entry['id'] == mg1CatalogId &&
        entry['version'] == mg1CatalogVersion);
    if (versions.contains(telemetryVersion) && compatibleCatalog) {
      return telemetryVersion;
    }
    if (versions.contains(1)) return 1;
    throw TelemetryException('relay offers no compatible contract/catalog');
  }

  @override
  Future<void> post({
    required TelemetrySample sample,
    required String endpoint,
    required String apiKey,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    sample.validate();
    if (sample.version == telemetryVersion &&
        await negotiate(endpoint: endpoint, apiKey: apiKey, timeout: timeout) !=
            telemetryVersion) {
      throw TelemetryException('relay cannot preserve v2 sample identity');
    }
    final request = http.Request('POST', Uri.parse(endpoint))
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(sample.toJson());
    if (apiKey.isNotEmpty) request.headers['Authorization'] = 'Bearer $apiKey';
    final response = await (() async {
      final response = await _client.send(request);
      await response.stream.drain<void>();
      return response;
    })()
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TelemetryException('upload failed: status ${response.statusCode}');
    }
  }
}
