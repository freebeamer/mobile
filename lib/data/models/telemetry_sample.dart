import 'dart:convert';
import 'package:equatable/equatable.dart';

import 'mhd_value.dart';
import 'mhd_field.dart';
import 'telemetry_session.dart';

/// One MHD monitor reading, tagged with when it was taken and which
/// device read it. Mirrors pkg/telemetry.Sample's JSON shape exactly
/// (device_id, timestamp, values) — this is the wire contract with
/// the FreeBeamer relay, not a Dart-idiomatic reinterpretation of it.
class TelemetrySample extends Equatable {
  final int version;
  final TelemetrySession? session;
  final int? sequence;
  final DateTime? receivedAt;
  final String deviceId;
  final DateTime timestamp;
  final Map<String, double> values;

  const TelemetrySample(
      {required this.deviceId,
      required this.timestamp,
      required this.values,
      this.version = 0,
      this.session,
      this.sequence,
      this.receivedAt});

  /// Mirrors pkg/telemetry.NewSample.
  factory TelemetrySample.fromMhdValues({
    required String deviceId,
    required DateTime timestamp,
    required List<MhdValue> values,
    TelemetrySession? session,
    int? sequence,
  }) {
    final map = <String, double>{for (final v in values) v.field.name: v.value};
    return TelemetrySample(
        deviceId: deviceId,
        timestamp: timestamp,
        values: map,
        version: session == null ? 0 : telemetryVersion,
        session: session,
        sequence: sequence);
  }

  Map<String, dynamic> toJson() => {
        if (version != 0) 'version': version,
        if (session != null) 'session': session!.toJson(),
        if (sequence != null) 'sequence': sequence,
        if (receivedAt != null)
          'received_at': receivedAt!.toUtc().toIso8601String(),
        'device_id': deviceId,
        // Dart's DateTime only carries microsecond precision (Go's
        // time.Time can carry nanoseconds), so this is a valid but
        // lower-precision RFC3339 string than the Go side might
        // produce — the relay's JSON decoding accepts either.
        'timestamp': timestamp.toUtc().toIso8601String(),
        'values': values,
      };

  factory TelemetrySample.fromJson(Map<String, dynamic> json) {
    final rawValues = (json['values'] as Map<String, dynamic>?) ?? const {};
    final sample = TelemetrySample(
      version: json['version'] as int? ?? 0,
      session: json['session'] == null
          ? null
          : TelemetrySession.fromJson(json['session'] as Map<String, dynamic>),
      sequence: json['sequence'] as int?,
      receivedAt: json['received_at'] == null
          ? null
          : DateTime.parse(json['received_at'] as String),
      deviceId: json['device_id'] as String? ?? '',
      timestamp: DateTime.parse(json['timestamp'] as String),
      values: rawValues
          .map((key, value) => MapEntry(key, (value as num).toDouble())),
    );
    sample.validate();
    return sample;
  }

  void validate() {
    if (version == 0 || version == 1) {
      if (session != null || sequence != null) {
        throw const FormatException('Legacy sample with v2 identity');
      }
      return;
    }
    if (version != telemetryVersion) {
      throw const FormatException('Unsupported telemetry version');
    }
    int size(String text) => utf8.encode(text).length;
    final identity = session;
    if (deviceId.trim().isEmpty ||
        size(deviceId) > 256 ||
        timestamp.toUtc() == DateTime.utc(1)) {
      throw const FormatException('Invalid device or timestamp');
    }
    if (identity == null ||
        identity.id.trim().isEmpty ||
        size(identity.id) > 128 ||
        identity.catalogId != mg1CatalogId ||
        identity.catalogVersion != mg1CatalogVersion) {
      throw const FormatException('Invalid session/catalog');
    }
    if (sequence == null || sequence! < 0 || sequence! > maxTelemetrySequence) {
      throw const FormatException('Invalid sequence');
    }
    final vehicle = identity.vehicle;
    if (vehicle != null &&
        (vehicle.label.trim().isEmpty ||
            size(vehicle.label) > 256 ||
            size(vehicle.ecuFamily) > 128 ||
            size(vehicle.software) > 128)) {
      throw const FormatException('Invalid vehicle claim');
    }
    if (values.isEmpty ||
        values.entries.any((entry) =>
            !entry.value.isFinite ||
            !mhdFieldTable.any((field) => field.name == entry.key))) {
      throw const FormatException('Invalid channel values');
    }
  }

  @override
  List<Object?> get props =>
      [deviceId, timestamp, values, version, session, sequence, receivedAt];
}
