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

/// Thrown specifically for a 401 from the relay's device-facing
/// endpoints (POST /v1/telemetry, GET /v1/capabilities) — signals an
/// expired or revoked device session token, distinct from any other
/// delivery failure, so TelemetryUploadService can attempt exactly one
/// silent re-authentication instead of backing off and retrying
/// forever with the same now-invalid token.
class TelemetryAuthException extends TelemetryException {
  TelemetryAuthException(super.message);
}

/// Thrown by IDeviceAuthRemoteDataSource (pairing, challenge/session,
/// logout) — a distinct failure domain from TelemetryException's
/// delivery/negotiation concerns, since callers (the tuners panel, the
/// deep-link listener) surface these with different messaging (e.g. "this
/// pairing link was already used or has expired" vs. a generic upload
/// failure).
class DeviceAuthException implements Exception {
  final String message;
  DeviceAuthException(this.message);
  @override
  String toString() => 'DeviceAuthException: $message';
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
