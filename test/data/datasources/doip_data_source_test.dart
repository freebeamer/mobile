import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/data/datasources/doip_data_source.dart';
import 'package:freebeamer_mobile/doip/frame.dart';
import 'package:freebeamer_mobile/doip/payload_types.dart';

/// Buffers one accepted connection's incoming bytes so the mock
/// server can await exact message boundaries — mirrors
/// pkg/doip/client_test.go's own mock-server helpers.
class _MockConnReader {
  final Socket socket;
  // A plain Uint8List reassigned on every read/write, not a
  // BytesBuilder — see the matching comment on the production
  // _SocketByteReader in lib/data/datasources/doip_data_source.dart
  // for why.
  Uint8List _buffer = Uint8List(0);
  final List<Completer<void>> _waiters = [];

  _MockConnReader(this.socket) {
    socket.listen((chunk) {
      _buffer = Uint8List.fromList([..._buffer, ...chunk]);
      final waiters = List<Completer<void>>.from(_waiters);
      _waiters.clear();
      for (final w in waiters) {
        if (!w.isCompleted) w.complete();
      }
    });
  }

  Future<Uint8List> _readExactly(int n) async {
    while (_buffer.length < n) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future.timeout(const Duration(seconds: 2));
    }
    final result = Uint8List.sublistView(_buffer, 0, n);
    _buffer = Uint8List.sublistView(_buffer, n);
    return result;
  }

  Future<(int, Uint8List)> readMessage() async {
    final header = parseHeader(await _readExactly(headerSize));
    final body = await _readExactly(header.payloadLength);
    return (header.payloadType, body);
  }
}

Future<ServerSocket> _startMockServer(Future<void> Function(Socket socket) handler) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) => handler(socket));
  return server;
}

void main() {
  test('activate and sendDiagnostic round trip against a mock DoIP server', () async {
    const responderAddress = 0x1234;
    final monitorReply = Uint8List.fromList([0x6C, 0x88, ...List.filled(34, 0)]);

    final server = await _startMockServer((socket) async {
      final reader = _MockConnReader(socket);

      final (activationType, activationBody) = await reader.readMessage();
      expect(activationType, payloadRoutingActivationRequest);
      final clientAddress = ByteData.sublistView(activationBody).getUint16(0, Endian.big);

      final activationResponse = ByteData(9);
      activationResponse.setUint16(0, clientAddress, Endian.big);
      activationResponse.setUint16(2, responderAddress, Endian.big);
      activationResponse.setUint8(4, routingSuccess);
      socket.add(
        packMessage(protocolVersion2012, payloadRoutingActivationResponse, activationResponse.buffer.asUint8List()),
      );

      final (diagType, diagBody) = await reader.readMessage();
      expect(diagType, payloadDiagnosticMessage);
      final source = ByteData.sublistView(diagBody).getUint16(0, Endian.big);
      final target = ByteData.sublistView(diagBody).getUint16(2, Endian.big);
      expect(target, responderAddress);
      expect(diagBody.sublist(4), equals([0x2C, 0x88, 0x01]));

      final ack = ByteData(5);
      ack.setUint16(0, responderAddress, Endian.big);
      ack.setUint16(2, source, Endian.big);
      socket.add(packMessage(protocolVersion2012, payloadDiagnosticMessagePositiveAck, ack.buffer.asUint8List()));

      final reply = BytesBuilder();
      final replyHeader = ByteData(4);
      replyHeader.setUint16(0, responderAddress, Endian.big);
      replyHeader.setUint16(2, source, Endian.big);
      reply.add(replyHeader.buffer.asUint8List());
      reply.add(monitorReply);
      socket.add(packMessage(protocolVersion2012, payloadDiagnosticMessage, reply.toBytes()));
    });
    addTearDown(server.close);

    final client = DoipDataSourceImpl();
    await client.connect(InternetAddress.loopbackIPv4.address, server.port);
    addTearDown(client.close);

    final target = await client.activate(0x0E00, activationDefault);
    expect(target, responderAddress);
    expect(client.targetAddress, responderAddress);

    final reply = await client.sendDiagnostic(Uint8List.fromList([0x2C, 0x88, 0x01]));
    expect(reply, equals(monitorReply));
  });

  test('activate throws on a denied response', () async {
    final server = await _startMockServer((socket) async {
      final reader = _MockConnReader(socket);
      final (_, body) = await reader.readMessage();
      final clientAddress = ByteData.sublistView(body).getUint16(0, Endian.big);
      final response = ByteData(9);
      response.setUint16(0, clientAddress, Endian.big);
      response.setUint16(2, 0, Endian.big);
      response.setUint8(4, routingDeniedUnsupportedActivationType);
      socket.add(packMessage(protocolVersion2012, payloadRoutingActivationResponse, response.buffer.asUint8List()));
    });
    addTearDown(server.close);

    final client = DoipDataSourceImpl();
    await client.connect(InternetAddress.loopbackIPv4.address, server.port);
    addTearDown(client.close);

    expect(() => client.activate(0x0E00, activationDefault), throwsA(isA<DoipException>()));
  });

  test('sendDiagnostic without activate first throws', () async {
    final server = await _startMockServer((socket) async {});
    addTearDown(server.close);

    final client = DoipDataSourceImpl();
    await client.connect(InternetAddress.loopbackIPv4.address, server.port);
    addTearDown(client.close);

    expect(
      () => client.sendDiagnostic(Uint8List.fromList([0x2C, 0x88, 0x01])),
      throwsA(isA<DoipException>()),
    );
  });

  test('connect to an unreachable address throws', () async {
    final client = DoipDataSourceImpl();
    expect(
      () => client.connect('127.0.0.1', 1, timeout: const Duration(milliseconds: 300)),
      throwsA(anything),
    );
  });
}
