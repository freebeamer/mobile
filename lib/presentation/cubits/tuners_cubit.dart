import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/device_pairing.dart';
import '../../domain/usecases/forget_device.dart';
import '../../domain/usecases/list_device_pairings.dart';
import '../../domain/usecases/pair_device.dart';
import '../../domain/usecases/parse_provisioning_link.dart';
import 'tuners_state.dart';

/// Drives the tuners panel: the list of saved device pairings, and
/// redeeming a new pairing link (scanned or pasted) to add one.
/// Reconnecting to an existing pairing and logging out of an active
/// session are ConnectionCubit's/StatusScreen's job instead (see their
/// own doc comments) — this Cubit only manages the saved-pairings list
/// itself.
class TunersCubit extends Cubit<TunersState> {
  final ListDevicePairings _listDevicePairings;
  final PairDevice _pairDevice;
  final ForgetDevice _forgetDevice;
  final ParseProvisioningLink _parseProvisioningLink;

  TunersCubit({
    required ListDevicePairings listDevicePairings,
    required PairDevice pairDevice,
    required ForgetDevice forgetDevice,
    required ParseProvisioningLink parseProvisioningLink,
  })  : _listDevicePairings = listDevicePairings,
        _pairDevice = pairDevice,
        _forgetDevice = forgetDevice,
        _parseProvisioningLink = parseProvisioningLink,
        super(const TunersState());

  Future<void> load() async {
    final pairings = await _listDevicePairings();
    emit(state.copyWith(pairings: pairings, loaded: true));
  }

  /// Redeems a scanned/pasted freebeamer://connect link. Returns the
  /// new DevicePairing on success (so the caller can navigate straight
  /// into it) or null, having emitted an error/qrError for display.
  Future<DevicePairing?> consumeLink(String raw) async {
    final payload = _parseProvisioningLink(raw);
    if (payload == null) {
      emit(state.copyWith(qrError: 'Unrecognized QR code or link'));
      return null;
    }
    emit(state.copyWith(busy: true, clearError: true, clearQrError: true));
    try {
      final pairing = await _pairDevice(payload);
      await load();
      return pairing;
    } catch (_) {
      emit(state.copyWith(
          error:
              'Could not pair — the link may be expired or already used.'));
      return null;
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  Future<void> forget(String clientId) async {
    await _forgetDevice(clientId);
    await load();
  }
}
