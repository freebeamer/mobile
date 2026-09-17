import 'package:equatable/equatable.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/telemetry/destination_identity.dart';

/// The per-session configuration ITelemetryRepository.send needs:
/// where to upload, the device's current bearer token, and where to
/// buffer undelivered samples locally. Grouped into one value object
/// (rather than three loose parameters) since it's passed on every
/// sample during a streaming session.
///
/// [apiKey] is a short-lived device session token (see
/// AuthenticateDevice), not a permanent credential — it rotates every
/// re-authentication, which is exactly why [bufferPath] is scoped by
/// the device's stable client ID (see [destinationId] in
/// destination_identity.dart) rather than by this field: the buffer
/// must survive a session-token refresh untouched.
class TelemetryConfig extends Equatable {
  final String endpoint;
  final String apiKey;
  final String bufferPath;

  /// A one-time, human-readable explanation if [buildTelemetryConfig] just
  /// quarantined or redirected a buffer file for this destination; empty
  /// otherwise. Deliberately excluded from [props]/equality — it's a
  /// transient UI note, not part of this config's actual identity (two
  /// configs with the same endpoint/apiKey/bufferPath are the same
  /// destination regardless of when this notice was last non-empty).
  final String resolutionNotice;

  const TelemetryConfig(
      {required this.endpoint,
      required this.apiKey,
      required this.bufferPath,
      this.resolutionNotice = ''});

  /// Returns a copy with apiKey replaced — used to install a freshly
  /// refreshed session token mid-stream without touching endpoint or
  /// bufferPath (see TelemetryUploadService's reauthenticate retry).
  TelemetryConfig copyWith({String? apiKey}) => TelemetryConfig(
      endpoint: endpoint,
      apiKey: apiKey ?? this.apiKey,
      bufferPath: bufferPath,
      resolutionNotice: resolutionNotice);

  @override
  List<Object?> get props => [endpoint, apiKey, bufferPath];
}

/// Builds a TelemetryConfig with the standard on-device buffer file
/// location — the one piece of async platform lookup (path_provider)
/// every entry point that starts a session needs, factored out so the
/// tuners panel's reconnect path and the deep-link auto-connect path
/// don't each reimplement it.
///
/// The buffer path is scoped to this destination's fingerprint (see
/// [destinationId]/[resolveSpoolPath]) rather than one fixed filename, so
/// reprovisioning to a different relay/client can never flush old buffered
/// samples under the new destination's credentials — mirrors
/// pkg/telemetry.ResolveSpoolPath's use in cmd/freebeamer/command_mhd.go.
/// A pre-existing fixed-path buffer file from before this scoping existed
/// is quarantined once (renamed, never deleted), or a mismatched
/// already-destination-scoped file is left untouched and a sibling path
/// used instead; [TelemetryConfig.resolutionNotice] reports whichever of
/// those just happened, for one-time UI surfacing.
///
/// [clientId] (not [sessionToken]) is what scopes the buffer: a paired
/// device's clientId is stable for the pairing's whole lifetime, while
/// its session token rotates on every re-authentication — scoping by
/// the token would fragment one destination's buffer across every
/// reconnect, defeating the point of buffering at all.
Future<TelemetryConfig> buildTelemetryConfig(
    {required String endpoint,
    required String clientId,
    required String sessionToken}) async {
  final bufferDir = await getApplicationSupportDirectory();
  final id = destinationId(endpoint, clientId);
  final legacyPath = '${bufferDir.path}/mhd-buffer.jsonl';
  final resolved = await resolveSpoolPath(legacyPath, id);
  return TelemetryConfig(
      endpoint: endpoint,
      apiKey: sessionToken,
      bufferPath: resolved.path,
      resolutionNotice: resolved.notice);
}
