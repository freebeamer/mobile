import 'dart:typed_data';

import '../../core/error/exceptions.dart';
import '../models/mhd_field.dart';
import '../models/mhd_value.dart';
import 'doip_data_source.dart';

/// MG1.adx's fixed 3-byte monitor request: UDS service 0x2C
/// (DynamicallyDefineDataIdentifier) with sub-parameters 0x88 0x01.
/// Mirrors pkg/mhd.MonitorRequest.
final Uint8List monitorRequest = Uint8List.fromList([0x2C, 0x88, 0x01]);

/// The fixed 2-byte prefix identifying a monitor reply. Mirrors
/// pkg/mhd.MonitorReplyHeader.
final Uint8List monitorReplyHeader = Uint8List.fromList([0x6C, 0x88]);

/// The number of data bytes following monitorReplyHeader. Mirrors
/// pkg/mhd.MonitorReplyBodyLength.
const int monitorReplyBodyLength = 36;

/// A full monitor reply's total length: header + body. Mirrors
/// pkg/mhd.MonitorReplyLength. final, not const: monitorReplyHeader is
/// a Uint8List (Uint8List.fromList isn't a const constructor), so its
/// .length isn't a compile-time constant.
final int monitorReplyLength = monitorReplyHeader.length + monitorReplyBodyLength;

/// Decodes one MhdField's raw integer value from body (the bytes
/// following monitorReplyHeader), little-endian per MG1.adx's
/// lsbfirst="1". Mirrors pkg/mhd.Field.decodeRaw.
int _decodeRawField(MhdField field, ByteData body, int bodyLength) {
  final end = field.byteOffset + field.sizeBits ~/ 8;
  if (end > bodyLength) {
    throw MhdException(
      'field ${field.name}: offset ${field.byteOffset}+${field.sizeBits ~/ 8} '
      'byte(s) exceeds body length $bodyLength',
    );
  }
  switch (field.sizeBits) {
    case 8:
      return field.signed ? body.getInt8(field.byteOffset) : body.getUint8(field.byteOffset);
    case 16:
      return field.signed
          ? body.getInt16(field.byteOffset, Endian.little)
          : body.getUint16(field.byteOffset, Endian.little);
    default:
      throw MhdException('field ${field.name}: unsupported size ${field.sizeBits} bits');
  }
}

/// Decodes a full monitor reply (as returned by
/// IDoipDataSource.sendDiagnostic for monitorRequest) into one
/// MhdValue per mhdFieldTable entry, in table order. Mirrors
/// pkg/mhd.DecodeMonitorReply. A pure function (no I/O), kept separate
/// from IMhdDataSource so it's directly unit-testable without a mock
/// socket.
List<MhdValue> decodeMonitorReply(Uint8List reply) {
  if (reply.length != monitorReplyLength) {
    throw MhdException('monitor reply length = ${reply.length}, want $monitorReplyLength');
  }
  for (var i = 0; i < monitorReplyHeader.length; i++) {
    if (reply[i] != monitorReplyHeader[i]) {
      throw MhdException(
        'monitor reply header mismatch at byte $i: got 0x${reply[i].toRadixString(16)}, '
        'want 0x${monitorReplyHeader[i].toRadixString(16)}',
      );
    }
  }
  final body = Uint8List.sublistView(reply, monitorReplyHeader.length);
  final bodyView = ByteData.sublistView(body);

  final values = <MhdValue>[];
  for (final field in mhdFieldTable) {
    final raw = _decodeRawField(field, bodyView, body.length);
    values.add(MhdValue(field: field, raw: raw, value: raw * field.scale));
  }
  return values;
}

/// The MHD-specific live-monitor exchange on top of IDoipDataSource:
/// send monitorRequest, decode the reply. Mirrors pkg/mhd.Monitor.
abstract class IMhdDataSource {
  Future<List<MhdValue>> readMonitor({Duration timeout = const Duration(seconds: 1)});
}

class MhdDataSourceImpl implements IMhdDataSource {
  final IDoipDataSource _doip;
  MhdDataSourceImpl(this._doip);

  @override
  Future<List<MhdValue>> readMonitor({Duration timeout = const Duration(seconds: 1)}) async {
    final reply = await _doip.sendDiagnostic(monitorRequest, timeout: timeout);
    return decodeMonitorReply(reply);
  }
}
