import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:freebeamer_mobile/data/datasources/telemetry_remote_data_source.dart';
import 'package:freebeamer_mobile/data/datasources/telemetry_local_data_source.dart';
import 'package:freebeamer_mobile/data/repositories/telemetry_repository_impl.dart';
import 'package:freebeamer_mobile/data/models/telemetry_config.dart';
import 'package:freebeamer_mobile/data/models/telemetry_sample.dart';

void main() {
  final cases = jsonDecode(
      File('testdata/public/telemetry/capabilities.json')
          .readAsStringSync()) as List;
  for (final testCase in cases) {
    test('shared negotiation ${testCase['name']}', () async {
      final remote =
          TelemetryRemoteDataSourceImpl(client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/prefix/v1/capabilities');
        expect(request.headers['Authorization'], 'Bearer key');
        expect(request.followRedirects, isFalse);
        return http.Response(
            jsonEncode(testCase['body']), testCase['status'] as int);
      }));
      final result = remote.negotiate(
          endpoint: 'https://relay.example/prefix/v1/telemetry', apiKey: 'key');
      if (testCase['version'] == 0) {
        await expectLater(result, throwsA(anything));
      } else {
        expect(await result, testCase['version']);
      }
    });
  }
  test(
      'v2 offline buffer survives legacy relay, failure and repository restart',
      () async {
    final dir = Directory.systemTemp.createTempSync('telemetry-v2-');
    addTearDown(() => dir.deleteSync(recursive: true));
    var compatible = false;
    var failPost = true;
    final requests = <Map<String, dynamic>>[];
    final remote =
        TelemetryRemoteDataSourceImpl(client: MockClient((request) async {
      if (request.method == 'GET') {
        return compatible
            ? http.Response(jsonEncode(cases.first['body']), 200)
            : http.Response('', 404);
      }
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('', failPost ? 503 : 202);
    }));
    final config = TelemetryConfig(
        endpoint: 'https://relay.example/v1/telemetry',
        apiKey: '',
        bufferPath: '${dir.path}/buffer.jsonl');
    final original = jsonDecode(
            File('testdata/public/telemetry/v2.json').readAsStringSync())
        as Map<String, dynamic>;
    final repo =
        TelemetryRepositoryImpl(remote, TelemetryLocalDataSourceImpl());
    expect(
        await repo.send(
            sample: TelemetrySample.fromJson(original), config: config),
        isFalse);
    expect(requests, isEmpty);
    compatible = true;
    await expectLater(repo.flushBuffer(config: config), throwsA(anything));
    failPost = false;
    final restarted =
        TelemetryRepositoryImpl(remote, TelemetryLocalDataSourceImpl());
    await restarted.flushBuffer(config: config);
    expect(requests, [original, original]);
    expect(await TelemetryLocalDataSourceImpl().isEmpty(config.bufferPath),
        isTrue);
  });
  test('malformed buffered record is preserved', () async {
    final dir = Directory.systemTemp.createTempSync('telemetry-invalid-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/buffer.jsonl')
      ..writeAsStringSync('{invalid}\n');
    final remote = TelemetryRemoteDataSourceImpl(
        client: MockClient((_) async => http.Response('', 202)));
    final repo =
        TelemetryRepositoryImpl(remote, TelemetryLocalDataSourceImpl());
    await expectLater(
        repo.flushBuffer(
            config: TelemetryConfig(
                endpoint: 'https://relay.example/v1/telemetry',
                apiKey: '',
                bufferPath: file.path)),
        throwsA(anything));
    expect(file.readAsStringSync(), '{invalid}\n');
  });
}
