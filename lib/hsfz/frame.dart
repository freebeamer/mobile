// Mirrors pkg/hsfz (core): BMW's HSFZ diagnostic framing used by
// F-series ENET on port 6801. See pkg/hsfz/hsfz.go for the evidence
// (MHD's WiFi-ENET adapter refused DoIP on 13400 but MHD's own app was
// connected to 192.168.4.1:6801) and what is still unconfirmed.
//
// Frame: uint32 length (payload bytes), uint16 control word, payload.
// Diagnostic payload: source address, target address, UDS bytes.
import 'dart:typed_data';

const int hsfzDefaultTcpPort = 6801;
const int hsfzControlPort = 6811;
const int hsfzDefaultTesterAddress = 0xF4;
const int hsfzDefaultDmeAddress = 0x12;

const int hsfzHeaderSize = 6;
const int hsfzMaxPayloadLength = 64 * 1024;

const int hsfzControlDiagnostic = 0x0001;
const int hsfzControlAcknowledge = 0x0002;
const int hsfzControlAliveCheck = 0x0012;

bool hsfzIsError(int control) => control >= 0x0040 && control <= 0x0045;

/// Whether [control] is a control word HSFZ peers send; used to tell an
/// HSFZ gateway from some unrelated service during port scanning.
bool hsfzIsKnown(int control) =>
    const {
      hsfzControlDiagnostic,
      hsfzControlAcknowledge,
      0x0011,
      hsfzControlAliveCheck,
      0x0013
    }.contains(control) ||
    hsfzIsError(control);

String describeHsfzControl(int control) {
  switch (control) {
    case hsfzControlDiagnostic:
      return 'diagnostic';
    case hsfzControlAcknowledge:
      return 'acknowledge';
    case hsfzControlAliveCheck:
      return 'alive check';
    case 0x0040:
      return 'error: incorrect tester address';
    case 0x0041:
      return 'error: incorrect control word';
    case 0x0042:
      return 'error: incorrect format';
    case 0x0043:
      return 'error: incorrect target address';
    case 0x0044:
      return 'error: message too large';
    case 0x0045:
      return 'error: diagnostic application not ready';
    default:
      return 'control word 0x${control.toRadixString(16).padLeft(4, '0')}';
  }
}

class HsfzException implements Exception {
  final String message;

  /// True when the peer did speak HSFZ (sent at least one valid frame),
  /// so the port is right even though the exchange failed.
  final bool identified;
  HsfzException(this.message, {this.identified = false});
  @override
  String toString() => 'HsfzException: $message';
}

Uint8List packHsfzFrame(int control, List<int> payload) {
  final frame = Uint8List(hsfzHeaderSize + payload.length);
  final view = ByteData.sublistView(frame);
  view.setUint32(0, payload.length, Endian.big);
  view.setUint16(4, control, Endian.big);
  frame.setRange(hsfzHeaderSize, frame.length, payload);
  return frame;
}

/// Returns (payload length, control word).
(int, int) parseHsfzHeader(Uint8List raw) {
  if (raw.length != hsfzHeaderSize) {
    throw HsfzException(
        'invalid header: expected $hsfzHeaderSize bytes, got ${raw.length}');
  }
  final view = ByteData.sublistView(raw);
  return (view.getUint32(0, Endian.big), view.getUint16(4, Endian.big));
}
