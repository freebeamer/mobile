import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/data/datasources/telemetry_local_data_source.dart';
import 'package:freebeamer_mobile/data/models/telemetry_sample.dart';

void main() {
  late Directory tempDir;
  late String path;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('telemetry_local_test_');
    path = '${tempDir.path}/buffer.jsonl';
  });
  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('isEmpty is true when the file does not exist yet', () async {
    final dataSource = TelemetryLocalDataSourceImpl();
    expect(await dataSource.isEmpty(path), isTrue);
  });

  test('append then readLines round trips in order', () async {
    final dataSource = TelemetryLocalDataSourceImpl();
    for (final id in ['a', 'b', 'c']) {
      await dataSource.append(
        TelemetrySample(deviceId: id, timestamp: DateTime.now(), values: const {}),
        path,
      );
    }

    expect(await dataSource.isEmpty(path), isFalse);
    final lines = await dataSource.readLines(path);
    expect(lines, hasLength(3));
    expect(TelemetrySample.fromJson(_decode(lines[0])).deviceId, 'a');
    expect(TelemetrySample.fromJson(_decode(lines[1])).deviceId, 'b');
    expect(TelemetrySample.fromJson(_decode(lines[2])).deviceId, 'c');
  });

  test('rewrite with an empty list deletes the file', () async {
    final dataSource = TelemetryLocalDataSourceImpl();
    await dataSource.append(TelemetrySample(deviceId: 'a', timestamp: DateTime.now(), values: const {}), path);
    await dataSource.rewrite(const [], path);

    expect(await dataSource.isEmpty(path), isTrue);
    expect(File(path).existsSync(), isFalse);
  });

  test('rewrite replaces the file contents', () async {
    final dataSource = TelemetryLocalDataSourceImpl();
    await dataSource.append(TelemetrySample(deviceId: 'a', timestamp: DateTime.now(), values: const {}), path);
    await dataSource.append(TelemetrySample(deviceId: 'b', timestamp: DateTime.now(), values: const {}), path);

    final lines = await dataSource.readLines(path);
    await dataSource.rewrite([lines[1]], path);

    final remaining = await dataSource.readLines(path);
    expect(remaining, hasLength(1));
    expect(TelemetrySample.fromJson(_decode(remaining[0])).deviceId, 'b');
  });
}

Map<String, dynamic> _decode(String line) => jsonDecode(line) as Map<String, dynamic>;
