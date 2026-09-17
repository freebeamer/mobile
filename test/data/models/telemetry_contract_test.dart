import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/data/models/telemetry_sample.dart';
import 'package:freebeamer_mobile/data/models/telemetry_session.dart';

void main() {
  for (final name in ['v2', 'legacy']) {
    test('shared $name fixture round trips', () {
      final json = jsonDecode(File('testdata/public/telemetry/$name.json')
          .readAsStringSync()) as Map<String, dynamic>;
      expect(TelemetrySample.fromJson(json).toJson(), json);
    });
  }
  for (final entry in <String, void Function(Map<String, dynamic>)>{
    'version': (json) => json['version'] = 3,
    'catalog': (json) => json['session']['catalog_version'] = 2,
    'sequence': (json) => json.remove('sequence'),
    'overflow': (json) => json['sequence'] = maxTelemetrySequence + 1,
    'legacy identity': (json) => json.remove('version'),
    'unknown channel': (json) => json['values']['NOPE'] = 1,
  }.entries) {
    test('rejects ${entry.key}', () {
      final json = jsonDecode(
              File('testdata/public/telemetry/v2.json').readAsStringSync())
          as Map<String, dynamic>;
      entry.value(json);
      expect(() => TelemetrySample.fromJson(json), throwsFormatException);
    });
  }
  test('new sessions have independent identities', () {
    expect(TelemetrySession.create().id, isNot(TelemetrySession.create().id));
  });
}
