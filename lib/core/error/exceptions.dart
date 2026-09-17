/// Thrown by the MHD data layer (decoding a monitor reply) — mirrors
/// pkg/mhd's error cases. DoipException (protocol/transport errors)
/// lives in doip/frame.dart alongside the codec it belongs to.
class MhdException implements Exception {
  final String message;
  MhdException(this.message);
  @override
  String toString() => 'MhdException: $message';
}

/// Thrown by the telemetry data layer (relay upload) — mirrors
/// pkg/telemetry's error cases.
class TelemetryException implements Exception {
  final String message;
  TelemetryException(this.message);
  @override
  String toString() => 'TelemetryException: $message';
}

/// Thrown by ITelemetryLocalDataSource.append when the spool is at its byte
/// cap and configured to refuse further writes — mirrors
/// pkg/telemetry.ErrSpoolFull under Spool's OverflowStop policy.
class SpoolFullException implements Exception {
  final String message;
  SpoolFullException(this.message);
  @override
  String toString() => 'SpoolFullException: $message';
}
