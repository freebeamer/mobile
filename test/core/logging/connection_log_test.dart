import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/core/logging/connection_log.dart';
import 'package:freebeamer_mobile/data/datasources/doip_data_source.dart';
import 'package:freebeamer_mobile/doip/frame.dart';
import 'package:freebeamer_mobile/doip/payload_types.dart';

void main() {
  test('hex renders and truncates', () {
    expect(hex([0x00, 0xAB, 0x10]), '00 ab 10');
    expect(hex(List.filled(5, 1), max: 2), '01 01 … (5 bytes)');
  });

  test('ring buffer keeps only the newest entries', () {
    final log = ConnectionLogImpl(capacity: 2, writeToFile: false);
    log.log('a', '1');
    log.log('a', '2');
    log.log('a', '3');
    expect(log.entries.map((e) => e.message), ['2', '3']);
    expect(log.exportText(), contains('[a] 3'));
  });

  test('a refused TCP dial is logged as FAILED', () async {
    // Bind then close to get a port nothing is listening on.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final log = ConnectionLogImpl(writeToFile: false);
    final client = DoipDataSourceImpl(log: log);
    await expectLater(
        client.connect(InternetAddress.loopbackIPv4.address, port),
        throwsA(isA<SocketException>()));
    expect(log.exportText(), contains('TCP dial FAILED'));
  });

  test('a silent server logs the activation frame and the receive timeout',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) => socket.listen((_) {})); // never replies
    addTearDown(server.close);

    final log = ConnectionLogImpl(writeToFile: false);
    final client = DoipDataSourceImpl(log: log);
    addTearDown(client.close);
    await client.connect(InternetAddress.loopbackIPv4.address, server.port);
    await expectLater(
        client.activate(0x0E00, activationDefault,
            timeout: const Duration(milliseconds: 200)),
        throwsA(isA<DoipException>()));

    final text = log.exportText();
    expect(text, contains('TCP connected'));
    // Routing activation request: 02 fd 00 05 00 00 00 07 0e 00 00 ...
    expect(
        text, contains('[tx] type 0x0005: 02 fd 00 05 00 00 00 07 0e 00 00'));
    expect(text, contains('receive FAILED'));
  });

  test('a reply that is not DoIP is shown as unparsed bytes', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {
      socket.listen((_) {
        // e.g. an HSFZ-style or otherwise foreign 8-byte header.
        socket.add(Uint8List.fromList([0, 0, 0, 2, 0, 0x12, 0xAA, 0xBB]));
      });
    });
    addTearDown(server.close);

    final log = ConnectionLogImpl(writeToFile: false);
    final client = DoipDataSourceImpl(log: log);
    addTearDown(client.close);
    await client.connect(InternetAddress.loopbackIPv4.address, server.port);
    await expectLater(client.activate(0x0E00, activationDefault),
        throwsA(isA<DoipException>()));
    expect(log.exportText(),
        contains('bytes received but unparsed: 00 00 00 02 00 12 aa bb'));
  });
}
