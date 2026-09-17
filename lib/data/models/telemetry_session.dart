import 'dart:math';
import 'package:equatable/equatable.dart';

const telemetryVersion = 2;
const mg1CatalogId = 'mhd.mg1.monitor';
const mg1CatalogVersion = 1;
const maxTelemetrySequence = 9007199254740991;

/// Operator-supplied identity only; never evidence of validated compatibility.
class VehicleClaim extends Equatable {
  final String label;
  final String ecuFamily;
  final String software;
  const VehicleClaim(
      {required this.label, this.ecuFamily = '', this.software = ''});
  Map<String, dynamic> toJson() => {
        'label': label,
        if (ecuFamily.isNotEmpty) 'ecu_family': ecuFamily,
        if (software.isNotEmpty) 'software': software,
      };
  factory VehicleClaim.fromJson(Map<String, dynamic> json) => VehicleClaim(
        label: json['label'] as String,
        ecuFamily: json['ecu_family'] as String? ?? '',
        software: json['software'] as String? ?? '',
      );
  @override
  List<Object?> get props => [label, ecuFamily, software];
}

class TelemetrySession extends Equatable {
  final String id;
  final String catalogId;
  final int catalogVersion;
  final VehicleClaim? vehicle;
  const TelemetrySession(
      {required this.id,
      this.catalogId = mg1CatalogId,
      this.catalogVersion = mg1CatalogVersion,
      this.vehicle});
  factory TelemetrySession.create() {
    final random = Random.secure();
    return TelemetrySession(
        id: List.generate(16,
                (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join());
  }
  Map<String, dynamic> toJson() => {
        'id': id,
        'catalog_id': catalogId,
        'catalog_version': catalogVersion,
        if (vehicle != null) 'vehicle': vehicle!.toJson(),
      };
  factory TelemetrySession.fromJson(Map<String, dynamic> json) =>
      TelemetrySession(
        id: json['id'] as String,
        catalogId: json['catalog_id'] as String,
        catalogVersion: json['catalog_version'] as int,
        vehicle: json['vehicle'] == null
            ? null
            : VehicleClaim.fromJson(json['vehicle'] as Map<String, dynamic>),
      );
  @override
  List<Object?> get props => [id, catalogId, catalogVersion, vehicle];
}
