import 'package:equatable/equatable.dart';

/// One scalar within MG1.adx's monitor reply body — mirrors
/// pkg/mhd.Field exactly (see pkg/mhd/livemonitor.go and
/// docs/mhd-live-monitor-v0-plan.md's field table).
class MhdField extends Equatable {
  final String name;
  final String title;
  final String units;
  final int byteOffset;
  final int sizeBits;
  final bool signed;

  /// The net multiplier equivalent to the Go reference's Conversion
  /// expression string (e.g. "X*0.0390625/3.6" -> 0.0390625/3.6).
  /// The Go side re-parses an arbitrary affine expression via
  /// pkg/expression; every one of MG1.adx's 19 fields is a simple
  /// scale, so this port precomputes the constant instead of
  /// embedding a general expression parser — a deliberate
  /// simplification, not a divergence in behavior.
  final double scale;

  const MhdField({
    required this.name,
    required this.title,
    required this.units,
    required this.byteOffset,
    required this.sizeBits,
    required this.signed,
    required this.scale,
  });

  @override
  List<Object?> get props => [name, title, units, byteOffset, sizeBits, signed, scale];
}

/// Every field MG1.adx's MONITORMACRO reply carries, in the file's own
/// declaration order (ascending byteOffset) — transcribed 1:1 from
/// pkg/mhd.Fields. Do not re-derive signedness/offsets/scale here if
/// the Go reference ever changes; copy it over instead, the same way
/// this table was produced.
const List<MhdField> mhdFieldTable = [
  MhdField(name: 'RPM', title: 'RPM', units: 'l/min', byteOffset: 0x00, sizeBits: 16, signed: false, scale: 1.0),
  MhdField(name: 'LOAD', title: 'Load', units: '%', byteOffset: 0x02, sizeBits: 16, signed: true, scale: 0.01),
  MhdField(
    name: 'BOOST',
    title: 'Boost',
    units: 'psi',
    byteOffset: 0x04,
    sizeBits: 16,
    signed: false,
    scale: 0.001133107328125,
  ),
  MhdField(
    name: 'BOOSTTARGET',
    title: 'Boost Target',
    units: 'psi',
    byteOffset: 0x06,
    sizeBits: 16,
    signed: false,
    scale: 0.0018129717,
  ),
  MhdField(
    name: 'BOOSTDEVIATION',
    title: 'Boost Deviation',
    units: 'psi',
    byteOffset: 0x08,
    sizeBits: 16,
    signed: true,
    scale: 0.0018129717,
  ),
  MhdField(
    name: 'BOOSTDEVGRAD',
    title: 'Boost Deviation Gradient',
    units: 'psi',
    byteOffset: 0x0A,
    sizeBits: 16,
    signed: true,
    scale: 0.0018129717,
  ),
  MhdField(
    name: 'ENGINETEMP',
    title: 'Engine Temp',
    units: '°C',
    byteOffset: 0x0C,
    sizeBits: 16,
    signed: true,
    scale: 0.01,
  ),
  MhdField(name: 'GEAR', title: 'Gear', units: '', byteOffset: 0x0E, sizeBits: 8, signed: false, scale: 1.0),
  MhdField(
    name: 'ETHANOLCONTENT',
    title: 'Ethanol Content (Active)',
    units: '%',
    byteOffset: 0x0F,
    sizeBits: 8,
    signed: false,
    scale: 1.0,
  ),
  MhdField(
    name: 'WGDISTRIBFAC',
    title: 'Distribution Factor',
    units: '-',
    byteOffset: 0x10,
    sizeBits: 16,
    signed: false,
    scale: 1 / 16384,
  ),
  MhdField(
    name: 'TURBOMASSFLOW',
    title: 'Air Mass Flow (Exhaust, new style)',
    units: 'g/s',
    byteOffset: 0x12,
    sizeBits: 16,
    signed: false,
    scale: 0.0390625 / 3.6,
  ),
  MhdField(
    name: 'TURBOMASSFLOW2',
    title: 'Air Mass Flow (Exhaust, old style)',
    units: 'g/s',
    byteOffset: 0x14,
    sizeBits: 16,
    signed: false,
    scale: 0.03125 / 3.6,
  ),
  MhdField(
    name: 'CMPRMASSFLOW',
    title: 'Air Mass Flow (Compressor, S58)',
    units: 'g/s',
    byteOffset: 0x16,
    sizeBits: 16,
    signed: false,
    scale: 0.0625 / 3.6,
  ),
  MhdField(
    name: 'CMPRMASSFLOW2',
    title: 'Air Mass Flow (Compressor, B58)',
    units: 'g/s',
    byteOffset: 0x18,
    sizeBits: 16,
    signed: false,
    scale: 0.03125 / 3.6,
  ),
  MhdField(
    name: 'BOOSTSETPOINTF',
    title: 'Boost Setpoint Factor',
    units: '-',
    byteOffset: 0x1A,
    sizeBits: 16,
    signed: false,
    scale: 1 / 8192,
  ),
  MhdField(name: 'SPEED', title: 'Speed', units: 'km/h', byteOffset: 0x1C, sizeBits: 16, signed: false, scale: 1.0),
  MhdField(
    name: 'AMBIENTTEMP',
    title: 'Ambient Temp',
    units: '°C',
    byteOffset: 0x1E,
    sizeBits: 16,
    signed: true,
    scale: 0.1,
  ),
  MhdField(
    name: 'INTAKEAIRTEMP',
    title: 'Intake Air Temp',
    units: '°C',
    byteOffset: 0x20,
    sizeBits: 16,
    signed: true,
    scale: 0.1,
  ),
  MhdField(
    name: 'MHDMAFCALC',
    title: 'MHD+ MAF',
    units: 'g/s',
    byteOffset: 0x22,
    sizeBits: 16,
    signed: false,
    scale: 0.03472225,
  ),
];
