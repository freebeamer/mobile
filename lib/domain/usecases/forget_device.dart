import '../repositories/device_pairing_repository.dart';

/// Permanently deletes a stored DevicePairing — unlike LogoutDevice,
/// this is the destructive "unpair" action: afterward the device has
/// no way to reconnect without a brand new pairing link.
class ForgetDevice {
  final IDevicePairingRepository _repository;
  ForgetDevice(this._repository);

  Future<void> call(String clientId) => _repository.remove(clientId);
}
