import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/usecases/load_provisioning.dart';
import '../../domain/usecases/parse_provisioning_link.dart';
import '../../domain/usecases/save_provisioning.dart';
import 'provisioning_state.dart';

class ProvisioningCubit extends Cubit<ProvisioningState> {
  final SaveProvisioning _saveProvisioning;
  final LoadProvisioning _loadProvisioning;
  final ParseProvisioningLink _parseProvisioningLink;

  ProvisioningCubit({
    required SaveProvisioning saveProvisioning,
    required LoadProvisioning loadProvisioning,
    required ParseProvisioningLink parseProvisioningLink,
  })  : _saveProvisioning = saveProvisioning,
        _loadProvisioning = loadProvisioning,
        _parseProvisioningLink = parseProvisioningLink,
        super(const ProvisioningState());

  Future<void> load() async {
    final saved = await _loadProvisioning();
    emit(state.copyWith(
      relayUrl: saved?.relayUrl ?? '',
      apiKey: saved?.apiKey ?? '',
      loaded: true,
    ));
  }

  void updateRelayUrl(String value) => emit(state.copyWith(relayUrl: value));
  void updateApiKey(String value) => emit(state.copyWith(apiKey: value));

  /// Applies a scanned QR code — the same freebeamer://connect link
  /// format a tapped deep link carries, just delivered by camera
  /// instead of a tap. See DeepLinkListener for the tapped-link path,
  /// which bypasses ConnectScreen entirely and connects directly.
  Future<void> applyScannedQrCode(String raw) async {
    final payload = _parseProvisioningLink(raw);
    if (payload == null) {
      emit(state.copyWith(qrError: 'Unrecognized QR code'));
      return;
    }
    emit(state.copyWith(relayUrl: payload.relayUrl, apiKey: payload.apiKey, clearQrError: true));
    await _saveProvisioning(relayUrl: payload.relayUrl, apiKey: payload.apiKey);
  }

  Future<void> persist() async {
    if (state.relayUrl.isEmpty || state.apiKey.isEmpty) return;
    await _saveProvisioning(relayUrl: state.relayUrl, apiKey: state.apiKey);
  }
}
