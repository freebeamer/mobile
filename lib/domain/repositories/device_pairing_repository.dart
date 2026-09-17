import '../../data/models/device_pairing.dart';

/// Persists every device pairing this phone currently holds — plural,
/// unlike the old single relay URL + API key: a phone can be paired to
/// more than one tuning session over time, and each stays available for
/// one-tap reconnect (see the tuners panel) until explicitly forgotten.
abstract class IDevicePairingRepository {
  Future<void> save(DevicePairing pairing);
  Future<List<DevicePairing>> list();
  Future<void> remove(String clientId);
}
