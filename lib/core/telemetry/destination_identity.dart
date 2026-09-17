import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Returns a short, stable fingerprint of a relay endpoint + API key pair.
/// It identifies which destination a spool file was written for, without
/// persisting the raw endpoint/key anywhere on disk — see
/// [resolveSpoolPath]. Mirrors pkg/telemetry.DestinationID exactly (same
/// input encoding, same hash, same truncation) and the relay's own existing
/// practice of storing only a SHA-256 hash of a client's API key, never the
/// key itself.
String destinationId(String endpoint, String apiKey) {
  final bytes = utf8.encode('$endpoint\x00$apiKey');
  return sha256.convert(bytes).toString().substring(0, 16);
}

class _SpoolIdentity {
  final String destinationId;
  const _SpoolIdentity(this.destinationId);
  Map<String, dynamic> toJson() => {'destination_id': destinationId};
  factory _SpoolIdentity.fromJson(Map<String, dynamic> json) =>
      _SpoolIdentity(json['destination_id'] as String);
}

String _identitySidecarPath(String bufferPath) => '$bufferPath.identity.json';

Future<_SpoolIdentity?> _readIdentity(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  return _SpoolIdentity.fromJson(json);
}

Future<void> _writeIdentity(String path, _SpoolIdentity identity) async {
  await File(path).writeAsString(jsonEncode(identity.toJson()));
}

/// Returns a sibling of bufferPath scoped to destinationId, e.g.
/// "mhd-buffer.jsonl" -> "mhd-buffer.<id>.jsonl". Pure string manipulation
/// (no package:path dependency) — bufferPath is always a plain file path
/// this app itself constructed (see buildTelemetryConfig), never
/// user-supplied, so POSIX '/' splitting is sufficient on every platform
/// this app targets.
String _destinationSpoolPath(String bufferPath, String destinationId) {
  final lastSlash = bufferPath.lastIndexOf('/');
  final dir = lastSlash < 0 ? '' : bufferPath.substring(0, lastSlash + 1);
  final base = lastSlash < 0 ? bufferPath : bufferPath.substring(lastSlash + 1);
  final dot = base.lastIndexOf('.');
  final stem = dot <= 0 ? base : base.substring(0, dot);
  final ext = dot <= 0 ? '' : base.substring(dot);
  return '$dir$stem.$destinationId$ext';
}

/// The result of [resolveSpoolPath]: the path to actually use as the
/// buffer/spool file, and a human-readable, one-time explanation of a
/// quarantine or redirect if either happened (empty otherwise).
class ResolvedSpoolPath {
  final String path;
  final String notice;
  const ResolvedSpoolPath(this.path, this.notice);
}

/// Ensures bufferPath is safe to use as a spool file for destinationId (from
/// [destinationId]), so a device reprovisioned to a new relay/client
/// destination can never have its old buffered samples flushed under the
/// new destination's credentials — see
/// docs/live-data-and-vehicle-mapping-plan.md's Phase 3 "isolate spool data
/// by relay/client destination" requirement. Mirrors
/// pkg/telemetry.ResolveSpoolPath's three cases exactly:
///
/// - No sidecar exists and bufferPath is empty/absent, or the sidecar's
///   destination matches: bufferPath is used as-is (writing/refreshing the
///   sidecar to record the current destination).
/// - No sidecar exists but bufferPath already has content (predates
///   destination tracking, provenance unrecoverable): that file is
///   quarantined once, renamed to bufferPath + ".legacy-unknown-destination"
///   (never deleted), and a fresh file is started at bufferPath bound to the
///   current destination.
/// - A sidecar exists and names a different destination (a real
///   reprovisioning): the mismatched file and its sidecar are left
///   untouched, and a destination-specific sibling path is used instead.
Future<ResolvedSpoolPath> resolveSpoolPath(
    String bufferPath, String destinationId) async {
  final sidecarPath = _identitySidecarPath(bufferPath);
  final existing = await _readIdentity(sidecarPath);

  if (existing != null) {
    if (existing.destinationId == destinationId) {
      return ResolvedSpoolPath(bufferPath, '');
    }
    final altPath = _destinationSpoolPath(bufferPath, destinationId);
    await _writeIdentity(
        _identitySidecarPath(altPath), _SpoolIdentity(destinationId));
    return ResolvedSpoolPath(altPath,
        'buffer file "$bufferPath" belongs to a different relay/client destination; using "$altPath" instead (neither file is deleted)');
  }

  var notice = '';
  final file = File(bufferPath);
  if (await file.exists() && await file.length() > 0) {
    final quarantine = '$bufferPath.legacy-unknown-destination';
    await file.rename(quarantine);
    notice =
        'existing buffer file "$bufferPath" has unknown destination provenance (predates destination tracking); preserved as "$quarantine", starting a new buffer';
  }

  await _writeIdentity(sidecarPath, _SpoolIdentity(destinationId));
  return ResolvedSpoolPath(bufferPath, notice);
}
