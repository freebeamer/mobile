import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/data/datasources/hsfz_data_source.dart';
import 'package:freebeamer_mobile/hsfz/frame.dart';

/// Reads HSFZ frames from [socket] and hands each to [onFrame].
void serveFrames(
    Socket socket, void Function(int control, Uint8List body) onFrame) {
  var buffer = <int>[];
  socket.done.catchError((_) {});
  socket.listen((chunk) {
    buffer.addAll(chunk);
    while (buffer.length >= hsfzHeaderSize) {
      final (length, control) = parseHsfzHeader(
          Uint8List.fromList(buffer.sublist(0, hsfzHeaderSize)));
      if (buffer.length < hsfzHeaderSize + length) return;
      final body = Uint8List.fromList(
          buffer.sublist(hsfzHeaderSize, hsfzHeaderSize + length));
      buffer = buffer.sublist(hsfzHeaderSize + length);
      onFrame(control, body);
    }
  }, onError: (_) {});
}

/// A fake HSFZ gateway + DME. [ecuAnswers] false = gateway acks only.
Future<ServerSocket> fakeHsfzGateway({bool ecuAnswers = true}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    serveFrames(socket, (control, body) {
      socket.add(packHsfzFrame(hsfzControlAcknowledge, body));
      if (!ecuAnswers) return;
      final request = body.sublist(2);
      final reply = request.length == 2 && request[0] == 0x3E
          ? [0x7E, 0x00]
          : [0x7F, request[0], 0x78, 0x62, ...request]; // pending first
      if (reply[0] == 0x7F) {
        socket.add(packHsfzFrame(
            hsfzControlDiagnostic, [body[1], body[0], 0x7F, request[0], 0x78]));
        socket.add(packHsfzFrame(
            hsfzControlDiagnostic, [0x40, body[0], 0x62])); // other ECU
        socket.add(packHsfzFrame(
            hsfzControlDiagnostic, [body[1], body[0], 0x62, ...request]));
      } else {
        socket.add(
            packHsfzFrame(hsfzControlDiagnostic, [body[1], body[0], ...reply]));
      }
    });
  });
  return server;
}

void main() {
  test('frame layout matches pkg/hsfz', () {
    expect(packHsfzFrame(hsfzControlDiagnostic, [0xF4, 0x12, 0x3E, 0x00]),
        [0, 0, 0, 4, 0, 1, 0xF4, 0x12, 0x3E, 0x00]);
    expect(parseHsfzHeader(Uint8List.fromList([0, 0, 0, 4, 0, 2])),
        (4, hsfzControlAcknowledge));
  });

  test(
      'activate probes with TesterPresent; sendDiagnostic skips ack, pending and other ECUs',
      () async {
    final server = await fakeHsfzGateway();
    addTearDown(server.close);
    final client = HsfzDataSourceImpl();
    await client.connect('127.0.0.1', server.port);
    expect(await client.activate(0x0E00, 0),
        hsfzDefaultDmeAddress); // 16-bit source -> 0xF4
    final reply =
        await client.sendDiagnostic(Uint8List.fromList([0x2C, 0x88, 0x01]));
    expect(reply, [0x62, 0x2C, 0x88, 0x01]);
    await client.close();
  });

  test('a gateway whose ECU stays silent is reported as identified HSFZ',
      () async {
    final server = await fakeHsfzGateway(ecuAnswers: false);
    addTearDown(server.close);
    final client = HsfzDataSourceImpl();
    await client.connect('127.0.0.1', server.port);
    await expectLater(
      client.activate(0xF4, 0, timeout: const Duration(milliseconds: 300)),
      throwsA(isA<HsfzException>()
          .having((e) => e.identified, 'identified', true)
          .having((e) => e.message, 'message', contains('ignition'))),
    );
    await client.close();
  });

  test('a non-HSFZ service is not identified', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((s) {
      s.listen((_) {}, onError: (_) {});
      s.done.catchError((_) {});
      s.add(Uint8List.fromList('HTTP/1.0 400 Bad\r\n\r\n'.codeUnits));
    });
    final client = HsfzDataSourceImpl();
    await client.connect('127.0.0.1', server.port);
    await expectLater(
      client.activate(0xF4, 0, timeout: const Duration(milliseconds: 300)),
      throwsA(isA<HsfzException>()
          .having((e) => e.identified, 'identified', false)),
    );
    await client.close();
  });

  test('gateway error control words surface as HsfzException', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((socket) => serveFrames(
        socket, (control, body) => socket.add(packHsfzFrame(0x0043, body))));
    final client = HsfzDataSourceImpl();
    await client.connect('127.0.0.1', server.port);
    await expectLater(
      client.activate(0xF4, 0),
      throwsA(isA<HsfzException>().having(
          (e) => e.message, 'message', contains('incorrect target address'))),
    );
    await client.close();
  });
}
