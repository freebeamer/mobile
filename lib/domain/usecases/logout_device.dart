import '../../data/datasources/device_auth_remote_data_source.dart';

/// Ends the current relay session for a device — revokes sessionToken
/// server-side immediately, best-effort (see
/// IDeviceAuthRemoteDataSource.logout). Deliberately does *not* touch
/// the device's stored DevicePairing: logging out of a tuning session
/// keeps the reconnection key on the device, so the tuners panel can
/// still offer one-tap reconnect afterward. See ForgetDevice for the
/// separate, actually-destructive "unpair" action.
class LogoutDevice {
  final IDeviceAuthRemoteDataSource _remote;
  LogoutDevice(this._remote);

  Future<void> call({required String relayUrl, required String sessionToken}) {
    return _remote.logout(relayUrl: relayUrl, sessionToken: sessionToken);
  }
}
