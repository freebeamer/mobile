import 'dart:io';
import 'dart:typed_data';

import '../../core/logging/connection_log.dart';
import '../../core/net/socket_byte_reader.dart';
import '../../hsfz/frame.dart';
import 'doip_data_source.dart';

/// HSFZ transport (BMW F-series ENET, port 6801). Mirrors pkg/hsfz.Client.
///
/// Implements the same interface as the DoIP source so the MHD monitor
/// and repository don't care which protocol is underneath. HSFZ has no
/// routing activation; [activate] instead sends UDS TesterPresent and
/// waits for the ECU's reply, which both confirms the port speaks HSFZ
/// and that the car is awake. Addresses are 1 byte: tester 0xF4, DME 0x12.
class HsfzDataSourceImpl implements IDoipDataSource {
  Socket? _socket;
  SocketByteReader? _reader;
  int _sourceAddress = hsfzDefaultTesterAddress;
  int _target = hsfzDefaultDmeAddress;
  bool _ready = false;
  final IConnectionLog _log;

  HsfzDataSourceImpl({IConnectionLog log = const NoopConnectionLog()})
      : _log = log;

  @override
  int? get targetAddress => _ready ? _target : null;

  /// Overrides the 1-byte ECU address before [activate] (default 0x12).
  set target(int address) {
    if (address < 0 || address > 0xFF) {
      throw HsfzException(
          'HSFZ target address must fit one byte, got 0x${address.toRadixString(16)}');
    }
    _target = address;
  }

  @override
  Future<void> connect(String address, int port,
      {Duration timeout = const Duration(seconds: 2)}) async {
    await close();
    _log.log('hsfz',
        'dialing TCP $address:$port (timeout ${timeout.inMilliseconds}ms)');
    final started = DateTime.now();
    final Socket socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
    } catch (e) {
      _log.log('hsfz',
          'TCP dial FAILED after ${DateTime.now().difference(started).inMilliseconds}ms: $e');
      rethrow;
    }
    _log.log('hsfz',
        'TCP connected in ${DateTime.now().difference(started).inMilliseconds}ms');
    _socket = socket;
    _reader = SocketByteReader(socket, _log, HsfzException.new);
  }

  /// Sends TesterPresent and waits for the ECU. [sourceAddress] is only
  /// used if it fits one byte; DoIP-style 16-bit addresses (0x0E00) fall
  /// back to the HSFZ tester default 0xF4. [activationType] is unused.
  @override
  Future<int> activate(int sourceAddress, int activationType,
      {Duration timeout = const Duration(seconds: 2)}) async {
    _sourceAddress =
        sourceAddress <= 0xFF ? sourceAddress : hsfzDefaultTesterAddress;
    _log.log('hsfz',
        'probing ECU 0x${_hex2(_target)} from tester 0x${_hex2(_sourceAddress)} with TesterPresent');
    await _send(hsfzControlDiagnostic, [_sourceAddress, _target, 0x3E, 0x00]);
    var identified = false;
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw identified
            ? HsfzException(
                'HSFZ gateway answered but the ECU did not (ignition off?)',
                identified: true)
            : HsfzException('no HSFZ reply');
      }
      final int control;
      final Uint8List body;
      try {
        (control, body) = await _receive(remaining);
      } on HsfzException catch (e) {
        if (identified && e.message.contains('timed out')) {
          throw HsfzException(
              'HSFZ gateway answered but the ECU did not (ignition off?)',
              identified: true);
        }
        throw HsfzException(e.message, identified: identified);
      }
      if (!hsfzIsKnown(control)) {
        throw HsfzException(
            'not HSFZ (unknown control word 0x${control.toRadixString(16)})');
      }
      identified = true;
      if (hsfzIsError(control)) {
        throw HsfzException('HSFZ ${describeHsfzControl(control)}',
            identified: true);
      }
      if (control == hsfzControlDiagnostic &&
          body.length >= 2 &&
          body[0] == _target &&
          body[1] == _sourceAddress) {
        _ready = true;
        _log.log('hsfz',
            'ECU 0x${_hex2(_target)} answered: ${hex(body.sublist(2))}');
        return _target;
      }
    }
  }

  @override
  Future<Uint8List> sendDiagnostic(Uint8List request,
      {Duration timeout = const Duration(seconds: 2)}) async {
    if (!_ready) throw HsfzException('not activated; call activate first');
    _log.log('uds',
        'request 0x${_hex2(_sourceAddress)} -> 0x${_hex2(_target)}: ${hex(request)}');
    await _send(hsfzControlDiagnostic, [_sourceAddress, _target, ...request]);
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw HsfzException('timed out waiting for diagnostic response');
      }
      final (control, body) = await _receive(remaining);
      if (hsfzIsError(control)) {
        throw HsfzException('gateway ${describeHsfzControl(control)}',
            identified: true);
      }
      if (control != hsfzControlDiagnostic) continue; // ack echo, alive check
      if (body.length < 2) {
        throw HsfzException('diagnostic payload of ${body.length} byte(s)');
      }
      if (body[0] != _target || body[1] != _sourceAddress) {
        continue; // other ECU
      }
      final uds = Uint8List.sublistView(body, 2);
      if (uds.length >= 3 && uds[0] == 0x7F && uds[2] == 0x78) {
        continue; // response pending
      }
      _log.log('uds',
          'reply: ${hex(uds)}${uds.isNotEmpty && uds[0] == 0x7F ? '  <-- NEGATIVE RESPONSE' : ''}');
      return uds;
    }
  }

  @override
  Future<void> close() async {
    if (_socket != null) _log.log('hsfz', 'closing connection');
    await _reader?.close();
    await _socket?.close();
    _socket?.destroy();
    _socket = null;
    _reader = null;
    _ready = false;
  }

  Future<void> _send(int control, List<int> payload) async {
    final socket = _socket;
    if (socket == null) {
      throw HsfzException('not connected; call connect first');
    }
    final frame = packHsfzFrame(control, payload);
    _log.log('tx', 'hsfz ${hex(frame)}');
    socket.add(frame);
    await socket.flush();
  }

  Future<(int, Uint8List)> _receive(Duration timeout) async {
    final reader = _reader;
    if (reader == null) {
      throw HsfzException('not connected; call connect first');
    }
    final (length, control) =
        parseHsfzHeader(await reader.readExactly(hsfzHeaderSize, timeout));
    if (length > hsfzMaxPayloadLength) {
      throw HsfzException('message too large: $length byte(s)');
    }
    final body = await reader.readExactly(length, timeout);
    _log.log('rx', 'hsfz ${describeHsfzControl(control)}: ${hex(body)}');
    return (control, body);
  }
}

String _hex2(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
