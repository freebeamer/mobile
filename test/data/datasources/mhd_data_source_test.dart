import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/core/error/exceptions.dart';
import 'package:freebeamer_mobile/data/datasources/doip_data_source.dart';
import 'package:freebeamer_mobile/data/datasources/mhd_data_source.dart';
import 'package:freebeamer_mobile/data/models/mhd_field.dart';
import 'package:freebeamer_mobile/data/models/mhd_value.dart';

// Same raw/want values pkg/mhd/livemonitor_test.go uses, so this test
// is a direct Dart/Go decode-logic parity check, not an independently
// invented fixture.
final Map<String, int> _rawValues = {
  'RPM': 2500,
  'LOAD': -500,
  'BOOST': 10000,
  'BOOSTTARGET': 20000,
  'BOOSTDEVIATION': -1000,
  'BOOSTDEVGRAD': 500,
  'ENGINETEMP': -1000,
  'GEAR': 3,
  'ETHANOLCONTENT': 85,
  'WGDISTRIBFAC': 16384,
  'TURBOMASSFLOW': 3600,
  'TURBOMASSFLOW2': 3600,
  'CMPRMASSFLOW': 3600,
  'CMPRMASSFLOW2': 3600,
  'BOOSTSETPOINTF': 8192,
  'SPEED': 120,
  'AMBIENTTEMP': -250,
  'INTAKEAIRTEMP': 400,
  'MHDMAFCALC': 2000,
};

final Map<String, double> _wantValues = {
  'RPM': 2500,
  'LOAD': -500 * 0.01,
  'BOOST': 10000 * 0.001133107328125,
  'BOOSTTARGET': 20000 * 0.0018129717,
  'BOOSTDEVIATION': -1000 * 0.0018129717,
  'BOOSTDEVGRAD': 500 * 0.0018129717,
  'ENGINETEMP': -1000 * 0.01,
  'GEAR': 3,
  'ETHANOLCONTENT': 85,
  'WGDISTRIBFAC': 16384.0 / 16384,
  'TURBOMASSFLOW': 3600 * 0.0390625 / 3.6,
  'TURBOMASSFLOW2': 3600 * 0.03125 / 3.6,
  'CMPRMASSFLOW': 3600 * 0.0625 / 3.6,
  'CMPRMASSFLOW2': 3600 * 0.03125 / 3.6,
  'BOOSTSETPOINTF': 8192.0 / 8192,
  'SPEED': 120,
  'AMBIENTTEMP': -250.0 / 10,
  'INTAKEAIRTEMP': 400.0 / 10,
  'MHDMAFCALC': 2000 * 0.03472225,
};

Uint8List _buildMonitorReply() {
  final reply = Uint8List(monitorReplyLength);
  reply.setRange(0, monitorReplyHeader.length, monitorReplyHeader);
  final body = ByteData.sublistView(reply, monitorReplyHeader.length);
  for (final field in mhdFieldTable) {
    final raw = _rawValues[field.name]!;
    switch (field.sizeBits) {
      case 8:
        body.setInt8(field.byteOffset, raw);
        break;
      case 16:
        body.setInt16(field.byteOffset, raw, Endian.little);
        break;
    }
  }
  return reply;
}

class _FakeDoipDataSource implements IDoipDataSource {
  Uint8List? nextReply;
  int? _targetAddress;

  @override
  int? get targetAddress => _targetAddress;

  @override
  Future<void> connect(String address, int port, {Duration timeout = const Duration(seconds: 2)}) async {}

  @override
  Future<int> activate(int sourceAddress, int activationType, {Duration timeout = const Duration(seconds: 2)}) async {
    _targetAddress = 0x1234;
    return _targetAddress!;
  }

  @override
  Future<Uint8List> sendDiagnostic(Uint8List request, {Duration timeout = const Duration(seconds: 2)}) async {
    expect(request, equals(monitorRequest));
    return nextReply!;
  }

  @override
  Future<void> close() async {}
}

void main() {
  group('decodeMonitorReply', () {
    test('matches the Go reference field-by-field', () {
      final reply = _buildMonitorReply();
      final values = decodeMonitorReply(reply);
      expect(values.length, mhdFieldTable.length);

      for (final v in values) {
        expect(v.raw, _rawValues[v.field.name], reason: v.field.name);
        expect(v.value, closeTo(_wantValues[v.field.name]!, 1e-9), reason: v.field.name);
      }

      final load = mhdValueByName(values, 'LOAD');
      expect(load, isNotNull);
      expect(load!.raw, -500);
      expect(mhdValueByName(values, 'NOT_A_FIELD'), isNull);
    });

    test('rejects the wrong length', () {
      expect(() => decodeMonitorReply(Uint8List(monitorReplyLength - 1)), throwsA(isA<MhdException>()));
    });

    test('rejects a mismatched header', () {
      final reply = _buildMonitorReply();
      reply[0] = 0x7F;
      expect(() => decodeMonitorReply(reply), throwsA(isA<MhdException>()));
    });
  });

  group('MhdDataSourceImpl', () {
    test('readMonitor sends monitorRequest and decodes the reply', () async {
      final fakeDoip = _FakeDoipDataSource()..nextReply = _buildMonitorReply();
      final mhd = MhdDataSourceImpl(fakeDoip);

      final values = await mhd.readMonitor();
      final rpm = mhdValueByName(values, 'RPM');
      expect(rpm, isNotNull);
      expect(rpm!.raw, 2500);
    });
  });
}
