import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/core/telemetry/destination_identity.dart';

void main() {
  test('destinationId is stable and distinct per endpoint/apiKey', () {
    final a1 = destinationId('https://relay.example/v1/telemetry', 'key-a');
    final a2 = destinationId('https://relay.example/v1/telemetry', 'key-a');
    expect(a1, a2);
    final b = destinationId('https://relay.example/v1/telemetry', 'key-b');
    expect(a1, isNot(b));
    final c = destinationId('https://other.example/v1/telemetry', 'key-a');
    expect(a1, isNot(c));
  });

  late Directory tempDir;
  setUp(() => tempDir = Directory.systemTemp.createTempSync('spool-identity'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  test('resolveSpoolPath on a first run uses bufferPath as-is', () async {
    final bufferPath = '${tempDir.path}/mhd-buffer.jsonl';
    final id = destinationId('https://relay.example/v1/telemetry', 'key-a');

    final resolved = await resolveSpoolPath(bufferPath, id);
    expect(resolved.path, bufferPath);
    expect(resolved.notice, isEmpty);
    expect(File('$bufferPath.identity.json').existsSync(), isTrue);
  });

  test('resolveSpoolPath reuses the file for a matching destination',
      () async {
    final bufferPath = '${tempDir.path}/mhd-buffer.jsonl';
    final id = destinationId('https://relay.example/v1/telemetry', 'key-a');
    await resolveSpoolPath(bufferPath, id);
    File(bufferPath).writeAsStringSync('{"device_id":"a"}\n');

    final resolved = await resolveSpoolPath(bufferPath, id);
    expect(resolved.path, bufferPath);
    expect(resolved.notice, isEmpty);
    expect(File(bufferPath).readAsStringSync(), '{"device_id":"a"}\n');
  });

  test('resolveSpoolPath quarantines a pre-existing unknown-provenance file',
      () async {
    final bufferPath = '${tempDir.path}/mhd-buffer.jsonl';
    File(bufferPath).writeAsStringSync('{"device_id":"old"}\n');
    final id = destinationId('https://relay.example/v1/telemetry', 'key-a');

    final resolved = await resolveSpoolPath(bufferPath, id);
    expect(resolved.path, bufferPath);
    expect(resolved.notice, isNotEmpty);
    final quarantine = File('$bufferPath.legacy-unknown-destination');
    expect(quarantine.existsSync(), isTrue);
    expect(quarantine.readAsStringSync(), '{"device_id":"old"}\n');
    expect(File(bufferPath).existsSync(), isFalse);
  });

  test('resolveSpoolPath redirects on a destination mismatch without touching the original',
      () async {
    final bufferPath = '${tempDir.path}/mhd-buffer.jsonl';
    final oldId = destinationId('https://relay.example/v1/telemetry', 'old-key');
    final newId = destinationId('https://relay.example/v1/telemetry', 'new-key');

    await resolveSpoolPath(bufferPath, oldId);
    File(bufferPath).writeAsStringSync('{"device_id":"old-client"}\n');

    final resolved = await resolveSpoolPath(bufferPath, newId);
    expect(resolved.path, isNot(bufferPath));
    expect(resolved.notice, isNotEmpty);
    expect(File(bufferPath).readAsStringSync(), '{"device_id":"old-client"}\n');
    expect(File(resolved.path).existsSync(), isFalse);

    // Resolving again for the same new destination is stable (same alt
    // path every time).
    final again = await resolveSpoolPath(bufferPath, newId);
    expect(again.path, resolved.path);
  });
}
