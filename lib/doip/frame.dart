// Mirrors pkg/doip/frame.go: DoIP's fixed 8-byte generic header
// (protocol version, its bitwise complement, payload type, payload
// length), pack/parse. See pkg/doip/doip.go's package doc for the
// evidence this is built from (jacobschaer/python-doipclient's actual
// source) and docs/mhd-live-monitor-v0-plan.md for the full writeup.
import 'dart:typed_data';

const int headerSize = 8;

/// Purely a sanity guard against a malformed/corrupted length field —
/// mirrors pkg/doip's maxPayloadLength exactly.
const int maxPayloadLength = 64 * 1024;

class DoipException implements Exception {
  final String message;
  DoipException(this.message);
  @override
  String toString() => 'DoipException: $message';
}

class DoipHeader {
  final int protocolVersion;
  final int payloadType;
  final int payloadLength;
  const DoipHeader(this.protocolVersion, this.payloadType, this.payloadLength);
}

/// Renders one complete DoIP message: the 8-byte generic header
/// followed by payload. Mirrors pkg/doip/frame.go's packMessage.
Uint8List packMessage(int protocolVersion, int payloadType, Uint8List payload) {
  final message = Uint8List(headerSize + payload.length);
  final view = ByteData.sublistView(message);
  message[0] = protocolVersion;
  message[1] = 0xFF ^ protocolVersion;
  view.setUint16(2, payloadType, Endian.big);
  view.setUint32(4, payload.length, Endian.big);
  message.setRange(headerSize, headerSize + payload.length, payload);
  return message;
}

/// Decodes a DoIP generic header from its fixed 8 bytes, validating
/// the protocol version's self-check byte. Mirrors
/// pkg/doip/frame.go's parseHeader.
DoipHeader parseHeader(Uint8List raw) {
  if (raw.length != headerSize) {
    throw DoipException('invalid generic header: expected $headerSize bytes, got ${raw.length}');
  }
  final protocolVersion = raw[0];
  final inverse = raw[1];
  if (inverse != (0xFF ^ protocolVersion) & 0xFF) {
    throw DoipException(
      'invalid generic header: protocol version 0x${protocolVersion.toRadixString(16)} '
      'inverse byte mismatch (got 0x${inverse.toRadixString(16)})',
    );
  }
  final view = ByteData.sublistView(raw);
  return DoipHeader(protocolVersion, view.getUint16(2, Endian.big), view.getUint32(4, Endian.big));
}
