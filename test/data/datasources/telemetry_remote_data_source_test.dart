import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/core/error/exceptions.dart';
import 'package:freebeamer_mobile/data/datasources/telemetry_remote_data_source.dart';
import 'package:freebeamer_mobile/data/models/telemetry_sample.dart';

Future<HttpServer> _startServer(Future<void> Function(HttpRequest request) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

String _urlOf(HttpServer server) => 'http://${server.address.address}:${server.port}';

void main() {
  test('post delivers the sample as JSON with the expected wire shape', () async {
    Map<String, dynamic>? received;
    final server = await _startServer((request) async {
      final body = await utf8.decoder.bind(request).join();
      received = jsonDecode(body) as Map<String, dynamic>;
      request.response.statusCode = 200;
      await request.response.close();
    });
    addTearDown(server.close);

    final dataSource = TelemetryRemoteDataSourceImpl();
    final sample = TelemetrySample(
      deviceId: 'device-1',
      timestamp: DateTime.utc(2026, 9, 16),
      values: const {'RPM': 800},
    );
    await dataSource.post(sample: sample, endpoint: _urlOf(server), apiKey: '');

    expect(received, isNotNull);
    expect(received!['device_id'], 'device-1');
    expect(received!['values'], {'RPM': 800});
  });

  test('post sets Authorization header when apiKey is set', () async {
    String? gotAuth;
    final server = await _startServer((request) async {
      gotAuth = request.headers.value('authorization');
      request.response.statusCode = 200;
      await request.response.close();
    });
    addTearDown(server.close);

    final dataSource = TelemetryRemoteDataSourceImpl();
    await dataSource.post(
      sample: TelemetrySample(deviceId: 'device-1', timestamp: DateTime.now(), values: const {}),
      endpoint: _urlOf(server),
      apiKey: 'fh_live_test-key',
    );

    expect(gotAuth, 'Bearer fh_live_test-key');
  });

  test('post omits Authorization header when apiKey is empty', () async {
    bool sawAuthHeader = false;
    final server = await _startServer((request) async {
      sawAuthHeader = request.headers.value('authorization') != null;
      request.response.statusCode = 200;
      await request.response.close();
    });
    addTearDown(server.close);

    final dataSource = TelemetryRemoteDataSourceImpl();
    await dataSource.post(
      sample: TelemetrySample(deviceId: 'device-1', timestamp: DateTime.now(), values: const {}),
      endpoint: _urlOf(server),
      apiKey: '',
    );

    expect(sawAuthHeader, isFalse);
  });

  test('post throws TelemetryException on a non-2xx response', () async {
    final server = await _startServer((request) async {
      request.response.statusCode = 401;
      await request.response.close();
    });
    addTearDown(server.close);

    final dataSource = TelemetryRemoteDataSourceImpl();
    expect(
      () => dataSource.post(
        sample: TelemetrySample(deviceId: 'device-1', timestamp: DateTime.now(), values: const {}),
        endpoint: _urlOf(server),
        apiKey: '',
      ),
      throwsA(isA<TelemetryException>()),
    );
  });

  test('post throws when the endpoint is unreachable', () async {
    final dataSource = TelemetryRemoteDataSourceImpl();
    expect(
      () => dataSource.post(
        sample: TelemetrySample(deviceId: 'device-1', timestamp: DateTime.now(), values: const {}),
        endpoint: 'http://127.0.0.1:1',
        apiKey: '',
        timeout: const Duration(milliseconds: 300),
      ),
      throwsA(anything),
    );
  });
}
