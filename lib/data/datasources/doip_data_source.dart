import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/logging/connection_log.dart';
import '../../doip/frame.dart';
import '../../doip/payload_types.dart';

/// Low-level DoIP transport: TCP dial, routing activation, and
/// diagnostic messaging over one connection. Mirrors pkg/doip.Client
/// exactly (pkg/doip/client.go) — same framing, same dynamic
/// target-address discovery from the routing activation response, same
/// error conditions. See docs/mhd-live-monitor-v0-plan.md for the
/// protocol evidence this is built from.
abstract class IDoipDataSource {
  /// Opens a TCP connection to address:port without yet performing
  /// routing activation — call activate next.
  Future<void> connect(String address, int port, {Duration timeout = const Duration(seconds: 2)});

  /// Performs DoIP routing activation. Returns the responding entity's
  /// own logical address, which is also remembered as the default
  /// diagnostic target (see targetAddress).
  Future<int> activate(int sourceAddress, int activationType, {Duration timeout = const Duration(seconds: 2)});

  /// The diagnostic target address activate() discovered, or null if
  /// activate() hasn't succeeded yet.
  int? get targetAddress;

  /// Sends a raw UDS request to the current target address and
  /// returns the UDS response bytes.
  Future<Uint8List> sendDiagnostic(Uint8List request, {Duration timeout = const Duration(seconds: 2)});

  Future<void> close();
}

class DoipDataSourceImpl implements IDoipDataSource {
  Socket? _socket;
  _SocketByteReader? _reader;
  int _sourceAddress = 0;
  int? _targetAddress;
  final IConnectionLog _log;

  DoipDataSourceImpl({IConnectionLog log = const NoopConnectionLog()}) : _log = log;

  @override
  int? get targetAddress => _targetAddress;

  @override
  Future<void> connect(String address, int port, {Duration timeout = const Duration(seconds: 2)}) async {
    // Defensive: this instance is a GetIt singleton (one app, one
    // vehicle connection at a time), so a second connect() call before
    // close() should replace the old connection cleanly rather than
    // leak its socket/reader while silently overwriting the fields
    // in-flight readers/writers still reference.
    await close();
    _log.log('doip', 'dialing TCP $address:$port (timeout ${timeout.inMilliseconds}ms)');
    final started = DateTime.now();
    final Socket socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
    } catch (e) {
      final ms = DateTime.now().difference(started).inMilliseconds;
      _log.log('doip', 'TCP dial FAILED after ${ms}ms: ${e.runtimeType}: $e');
      rethrow;
    }
    final ms = DateTime.now().difference(started).inMilliseconds;
    try {
      _log.log('doip',
          'TCP connected in ${ms}ms: local ${socket.address.address}:${socket.port} -> remote ${socket.remoteAddress.address}:${socket.remotePort}');
    } catch (_) {
      _log.log('doip', 'TCP connected in ${ms}ms');
    }
    _socket = socket;
    _reader = _SocketByteReader(socket, _log);
    _targetAddress = null;
  }

  @override
  Future<int> activate(
    int sourceAddress,
    int activationType, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    _sourceAddress = sourceAddress;
    _log.log('doip',
        'routing activation: source 0x${_hex4(sourceAddress)}, type 0x${activationType.toRadixString(16).padLeft(2, '0')}');
    final payload = ByteData(7);
    payload.setUint16(0, sourceAddress, Endian.big);
    payload.setUint8(2, activationType);
    // bytes 3..6 are the reserved field and stay zero.
    await _send(payloadRoutingActivationRequest, payload.buffer.asUint8List());

    final (type, body) = await _receive(timeout);
    if (type != payloadRoutingActivationResponse) {
      throw DoipException(
        'unexpected payload type: got 0x${type.toRadixString(16)}, '
        'want RoutingActivationResponse (0x${payloadRoutingActivationResponse.toRadixString(16)})',
      );
    }
    if (body.length < 9) {
      throw DoipException('routing activation response too short (${body.length} byte(s))');
    }
    final responderAddress = ByteData.sublistView(body).getUint16(2, Endian.big);
    final code = body[4];
    _log.log('doip',
        'routing activation response: client 0x${_hex4(ByteData.sublistView(body).getUint16(0, Endian.big))}, '
        'responder 0x${_hex4(responderAddress)}, code 0x${code.toRadixString(16).padLeft(2, '0')} (${describeRoutingCode(code)})');
    if (code != routingSuccess && code != routingSuccessConfirmationRequired) {
      throw DoipException('routing activation denied: ${describeRoutingCode(code)}');
    }
    _targetAddress = responderAddress;
    _log.log('doip', 'diagnostic target set to responder 0x${_hex4(responderAddress)}');
    return responderAddress;
  }

  @override
  Future<Uint8List> sendDiagnostic(Uint8List request, {Duration timeout = const Duration(seconds: 2)}) async {
    final target = _targetAddress;
    if (target == null) {
      throw DoipException('no target address set; call activate first');
    }
    final payload = BytesBuilder();
    final addresses = ByteData(4);
    addresses.setUint16(0, _sourceAddress, Endian.big);
    addresses.setUint16(2, target, Endian.big);
    payload.add(addresses.buffer.asUint8List());
    payload.add(request);
    _log.log('uds', 'request 0x${_hex4(_sourceAddress)} -> 0x${_hex4(target)}: ${hex(request)}');
    await _send(payloadDiagnosticMessage, payload.toBytes());

    final deadline = DateTime.now().add(timeout);
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw DoipException('timed out waiting for diagnostic response');
      }
      final (type, body) = await _receive(remaining);
      switch (type) {
        case payloadDiagnosticMessagePositiveAck:
          // Just a DoIP-level receipt confirmation; the actual UDS
          // reply (if any) is a separate DiagnosticMessage that
          // follows.
          continue;
        case payloadDiagnosticMessageNegativeAck:
          if (body.length < 5) {
            throw DoipException('malformed diagnostic negative acknowledgement');
          }
          throw DoipException(
            'diagnostic message negative acknowledgement: code 0x${body[4].toRadixString(16)}',
          );
        case payloadDiagnosticMessage:
          if (body.length < 4) {
            throw DoipException('malformed diagnostic message');
          }
          final view = ByteData.sublistView(body);
          _log.log('uds',
              'reply from 0x${_hex4(view.getUint16(0, Endian.big))} to 0x${_hex4(view.getUint16(2, Endian.big))}: ${hex(body.sublist(4))}'
              '${body.length > 4 && body[4] == 0x7F ? '  <-- NEGATIVE RESPONSE' : ''}');
          return Uint8List.sublistView(body, 4);
        default:
          // Unrelated DoIP traffic (e.g. an alive check request);
          // ignore and keep waiting for our own response.
          continue;
      }
    }
  }

  @override
  Future<void> close() async {
    if (_socket != null) _log.log('doip', 'closing connection');
    await _reader?.close();
    await _socket?.close();
    _socket = null;
    _reader = null;
    _targetAddress = null;
  }

  Future<void> _send(int payloadType, Uint8List payload) async {
    final socket = _socket;
    if (socket == null) {
      throw DoipException('not connected; call connect first');
    }
    final frame = packMessage(protocolVersion2012, payloadType, payload);
    _log.log('tx', 'type 0x${_hex4(payloadType)}: ${hex(frame)}');
    try {
      socket.add(frame);
      await socket.flush();
    } catch (e) {
      _log.log('tx', 'send FAILED: ${e.runtimeType}: $e');
      rethrow;
    }
  }

  Future<(int, Uint8List)> _receive(Duration timeout) async {
    final reader = _reader;
    if (reader == null) {
      throw DoipException('not connected; call connect first');
    }
    Uint8List rawHeader = Uint8List(0);
    final DoipHeader header;
    final Uint8List body;
    try {
      rawHeader = await reader.readExactly(headerSize, timeout);
      header = parseHeader(rawHeader);
      if (header.payloadLength > maxPayloadLength) {
        throw DoipException('message too large: ${header.payloadLength} byte(s)');
      }
      body = await reader.readExactly(header.payloadLength, timeout);
    } catch (e) {
      _log.log('rx',
          'receive FAILED: $e (bytes received but unparsed: ${hex([...rawHeader, ...reader.pending])})');
      rethrow;
    }
    _log.log('rx', 'type 0x${_hex4(header.payloadType)}: ${hex([...rawHeader, ...body])}');
    if (header.payloadType == payloadGenericNegativeAck) {
      final code = body.isNotEmpty ? body[0] : 0;
      throw DoipException('generic negative acknowledgement, code 0x${code.toRadixString(16)}');
    }
    return (header.payloadType, body);
  }
}

/// Buffers bytes from a Socket's stream so exact byte counts can be
/// awaited with a timeout — dart:io's Socket is a Stream<Uint8List>,
/// not the blocking-read abstraction Go's net.Conn (and pkg/doip's
/// io.ReadFull-based receive) relies on, so this exists purely to
/// bridge that gap.
class _SocketByteReader {
  // A plain Uint8List reassigned on every read/write, rather than a
  // BytesBuilder: BytesBuilder.toBytes()'s clear-on-read semantics
  // turned out not to behave as assumed (caught by
  // test/data/datasources/doip_data_source_test.dart, which read a
  // stale duplicate of the first message) — this avoids relying on
  // that ambiguity at all.
  Uint8List _buffer = Uint8List(0);
  final List<Completer<void>> _waiters = [];
  StreamSubscription<Uint8List>? _subscription;
  Object? _error;
  bool _done = false;

  final IConnectionLog _log;

  /// Bytes received but not yet consumed — for diagnostics.
  Uint8List get pending => _buffer;

  _SocketByteReader(Socket socket, this._log) {
    _subscription = socket.listen(
      (chunk) {
        _buffer = Uint8List.fromList([..._buffer, ...chunk]);
        _wake();
      },
      onError: (Object error) {
        _log.log('rx', 'socket error: ${error.runtimeType}: $error');
        _error = error;
        _wake();
      },
      onDone: () {
        _log.log('rx', 'remote closed the connection (${_buffer.length} unread byte(s))');
        _done = true;
        _wake();
      },
    );
  }

  void _wake() {
    final waiters = List<Completer<void>>.from(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Future<Uint8List> readExactly(int n, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_buffer.length < n) {
      if (_error != null) throw DoipException('socket error: $_error');
      if (_done) throw DoipException('connection closed while reading');
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw DoipException('timed out reading from socket');
      }
      final waiter = Completer<void>();
      _waiters.add(waiter);
      try {
        await waiter.future.timeout(remaining);
      } on TimeoutException {
        _waiters.remove(waiter);
        throw DoipException('timed out reading from socket');
      }
    }
    final result = Uint8List.sublistView(_buffer, 0, n);
    _buffer = Uint8List.sublistView(_buffer, n);
    return result;
  }

  Future<void> close() async {
    await _subscription?.cancel();
  }
}

String _hex4(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();
