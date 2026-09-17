import 'package:equatable/equatable.dart';

import 'mhd_field.dart';

/// One MhdField decoded from a monitor reply: its raw integer value
/// and that value after applying field.scale. Mirrors pkg/mhd.Value.
class MhdValue extends Equatable {
  final MhdField field;
  final int raw;
  final double value;

  const MhdValue({required this.field, required this.raw, required this.value});

  @override
  List<Object?> get props => [field, raw, value];
}

/// Returns the first value in values whose field.name matches name, or
/// null if none does. Mirrors pkg/mhd.ByName.
MhdValue? mhdValueByName(List<MhdValue> values, String name) {
  for (final value in values) {
    if (value.field.name == name) return value;
  }
  return null;
}
