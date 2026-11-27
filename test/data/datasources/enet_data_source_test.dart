import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/data/datasources/doip_data_source.dart';
import 'package:freebeamer_mobile/data/datasources/enet_data_source.dart';
import 'package:freebeamer_mobile/data/datasources/hsfz_data_source.dart';
import 'package:freebeamer_mobile/doip/frame.dart';
import 'package:freebeamer_mobile/doip/payload_types.dart';

import 'hsfz_data_source_test.dart' show fakeHsfzGateway;

/// A fake DoIP entity answering routing activation as 0x0010; silent for
/// anything else (e.g. an HSFZ probe), like a real entity would be.
Future<ServerSocket> fakeDoipEntity() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    socket.done.catchError((_) {});
    final buffer = <int>[];
    socket.listen((chunk) {
      buffer.addAll(chunk);
      if (buffer.length < headerSize) return;
      final DoipHeader header;
      try {
        header = parseHeader(Uint8List.fromList(buffer.sublist(0, headerSize)));
      } on DoipException {
        return; // not DoIP (e.g. an HSFZ probe): ignore it, as a real entity would
      }
      if (header.payloadType != payloadRoutingActivationRequest) return;
      if (buffer.length < headerSize + header.payloadLength) return;
      final body =
          buffer.sublist(headerSize, headerSize + header.payloadLength);
      socket.add(packMessage(
          protocolVersion2012,
          payloadRoutingActivationResponse,
          Uint8List.fromList(
              [body[0], body[1], 0x00, 0x10, routingSuccess, 0, 0, 0, 0])));
    }, onError: (_) {});
  });
  return server;
}

Future<ServerSocket> junkService() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((s) {
    s.listen((_) {}, onError: (_) {});
    s.done.catchError((_) {});
    s.add(Uint8List.fromList('HTTP/1.0 400 Bad\r\n\r\n'.codeUnits));
  });
  return server;
}

/// A localhost port with nothing listening.
Future<int> closedPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

EnetDataSourceImpl enet({List<int>? sweep, bool scan = true}) =>
    EnetDataSourceImpl(
      doip: DoipDataSourceImpl(),
      hsfz: HsfzDataSourceImpl(),
      scan: EnetScanOptions(
        knownPorts: const [],
        sweepPorts: sweep ?? const [],
        sweepTimeout: const Duration(milliseconds: 200),
        enabled: scan,
      ),
    );

const probe = Duration(milliseconds: 300);

void main() {
  test('HSFZ on the requested port: no scan', () async {
    final server = await fakeHsfzGateway();
    addTearDown(server.close);
    final link = enet();
    await link.connect('127.0.0.1', server.port);
    expect(
        await link.activate(0x0E00, activationDefault, timeout: probe), 0x12);
    expect(link.protocol, EnetProtocol.hsfz);
    expect(link.scanned, isFalse);
    expect(await link.sendDiagnostic(Uint8List.fromList([0x2C, 0x88, 0x01])),
        [0x62, 0x2C, 0x88, 0x01]);
    await link.close();
  });

  test('falls back to the sweep when the requested port is closed', () async {
    final server = await fakeHsfzGateway();
    addTearDown(server.close);
    final link = enet(sweep: [await closedPort(), server.port]);
    await link.connect('127.0.0.1', await closedPort());
    expect(
        await link.activate(0x0E00, activationDefault, timeout: probe), 0x12);
    expect(link.activePort, server.port);
    expect(link.scanned, isTrue);
    await link.close();
  });

  test('detects DoIP after the HSFZ probe gets no answer', () async {
    final server = await fakeDoipEntity();
    addTearDown(server.close);
    final link = enet();
    await link.connect('127.0.0.1', server.port);
    expect(
        await link.activate(0x0E00, activationDefault, timeout: probe), 0x0010);
    expect(link.protocol, EnetProtocol.doip);
    await link.close();
  });

  test('reports the open ports when nothing answers', () async {
    final junk = await junkService();
    addTearDown(junk.close);
    final link = enet(sweep: [junk.port]);
    await link.connect('127.0.0.1', await closedPort());
    await expectLater(
      link.activate(0x0E00, activationDefault, timeout: probe),
      throwsA(isA<DoipException>().having((e) => e.message, 'message',
          contains('open port(s) [${junk.port}]'))),
    );
  });

  test('an HSFZ gateway with a silent ECU is named in the error', () async {
    final server = await fakeHsfzGateway(ecuAnswers: false);
    addTearDown(server.close);
    final link = enet(scan: false);
    await link.connect('127.0.0.1', server.port);
    await expectLater(
      link.activate(0x0E00, activationDefault, timeout: probe),
      throwsA(isA<DoipException>()
          .having((e) => e.message, 'message', contains('speaks hsfz but'))),
    );
  });

  test('scanning disabled: only the requested port is tried', () async {
    final server = await fakeHsfzGateway();
    addTearDown(server.close);
    final link = enet(sweep: [server.port], scan: false);
    await link.connect('127.0.0.1', await closedPort());
    await expectLater(link.activate(0x0E00, activationDefault, timeout: probe),
        throwsA(isA<DoipException>()));
  });

  test('skip ports are never probed', () async {
    final server = await fakeHsfzGateway();
    addTearDown(server.close);
    final link = EnetDataSourceImpl(
      doip: DoipDataSourceImpl(),
      hsfz: HsfzDataSourceImpl(),
      scan: EnetScanOptions(
          knownPorts: const [],
          sweepPorts: [server.port],
          skipPorts: {server.port}),
    );
    await link.connect('127.0.0.1', await closedPort());
    await expectLater(link.activate(0x0E00, activationDefault, timeout: probe),
        throwsA(isA<DoipException>()));
  });
}
