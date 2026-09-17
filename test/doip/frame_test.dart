import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/doip/frame.dart';
import 'package:freebeamer_mobile/doip/payload_types.dart';

void main() {
  test('packMessage round trip matches the Go reference byte-for-byte', () {
    final payload = Uint8List.fromList([0x2C, 0x88, 0x01]);
    final message = packMessage(protocolVersion2012, payloadDiagnosticMessage, payload);
    final want = Uint8List.fromList([0x02, 0xFD, 0x80, 0x01, 0x00, 0x00, 0x00, 0x03, 0x2C, 0x88, 0x01]);
    expect(message, equals(want));

    final header = parseHeader(Uint8List.sublistView(message, 0, headerSize));
    expect(header.protocolVersion, protocolVersion2012);
    expect(header.payloadType, payloadDiagnosticMessage);
    expect(header.payloadLength, payload.length);
  });

  test('parseHeader rejects a bad inverse byte', () {
    final raw = Uint8List(headerSize);
    raw[0] = protocolVersion2012;
    raw[1] = 0x00; // should be 0xFD
    expect(() => parseHeader(raw), throwsA(isA<DoipException>()));
  });

  test('packMessage with an empty payload matches the Go reference', () {
    final message = packMessage(protocolVersion2012, payloadAliveCheckRequest, Uint8List(0));
    final want = Uint8List.fromList([0x02, 0xFD, 0x00, 0x07, 0x00, 0x00, 0x00, 0x00]);
    expect(message, equals(want));
  });

  test('describeRoutingCode matches the Go reference', () {
    expect(describeRoutingCode(routingSuccess), 'success');
    expect(describeRoutingCode(routingDeniedUnsupportedActivationType), 'denied: unsupported activation type');
    expect(describeRoutingCode(0x99), 'unknown response code 0x99');
  });
}
