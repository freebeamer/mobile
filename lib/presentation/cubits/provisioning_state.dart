import 'package:equatable/equatable.dart';

class ProvisioningState extends Equatable {
  final String relayUrl;
  final String apiKey;
  final bool loaded;
  final String? qrError;

  const ProvisioningState({
    this.relayUrl = '',
    this.apiKey = '',
    this.loaded = false,
    this.qrError,
  });

  ProvisioningState copyWith({
    String? relayUrl,
    String? apiKey,
    bool? loaded,
    String? qrError,
    bool clearQrError = false,
  }) {
    return ProvisioningState(
      relayUrl: relayUrl ?? this.relayUrl,
      apiKey: apiKey ?? this.apiKey,
      loaded: loaded ?? this.loaded,
      qrError: clearQrError ? null : (qrError ?? this.qrError),
    );
  }

  @override
  List<Object?> get props => [relayUrl, apiKey, loaded, qrError];
}
