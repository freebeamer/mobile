import 'package:equatable/equatable.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/telemetry/destination_identity.dart';

/// The per-session configuration ITelemetryRepository.send needs:
/// where to upload, the client's API key, and where to buffer
/// undelivered samples locally. Grouped into one value object (rather
/// than three loose parameters) since it's passed on every sample
/// during a streaming session.
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

  @override
  List<Object?> get props => [endpoint, apiKey, bufferPath];
}

/// Builds a TelemetryConfig with the standard on-device buffer file
/// location — the one piece of async platform lookup (path_provider)
/// every entry point that starts a session needs, factored out so
/// ConnectScreen's manual-entry path and the deep-link auto-connect
/// path don't each reimplement it.
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
Future<TelemetryConfig> buildTelemetryConfig({required String endpoint, required String apiKey}) async {
  final bufferDir = await getApplicationSupportDirectory();
  final id = destinationId(endpoint, apiKey);
  final legacyPath = '${bufferDir.path}/mhd-buffer.jsonl';
  final resolved = await resolveSpoolPath(legacyPath, id);
  return TelemetryConfig(
      endpoint: endpoint,
      apiKey: apiKey,
      bufferPath: resolved.path,
      resolutionNotice: resolved.notice);
}
