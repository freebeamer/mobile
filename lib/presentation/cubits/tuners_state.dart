import 'package:equatable/equatable.dart';

import '../../data/models/device_pairing.dart';

class TunersState extends Equatable {
  final List<DevicePairing> pairings;
  final bool loaded;
  final bool busy;
  final String? error;
  final String? qrError;

  const TunersState({
    this.pairings = const [],
    this.loaded = false,
    this.busy = false,
    this.error,
    this.qrError,
  });

  TunersState copyWith({
    List<DevicePairing>? pairings,
    bool? loaded,
    bool? busy,
    String? error,
    bool clearError = false,
    String? qrError,
    bool clearQrError = false,
  }) {
    return TunersState(
      pairings: pairings ?? this.pairings,
      loaded: loaded ?? this.loaded,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      qrError: clearQrError ? null : (qrError ?? this.qrError),
    );
  }

  @override
  List<Object?> get props => [pairings, loaded, busy, error, qrError];
}
