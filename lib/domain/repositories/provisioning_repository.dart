import '../../data/models/provisioning_payload.dart';

/// Persists the relay URL + client API key a device was provisioned
/// with (see docs/freebeamer-relay-v0-plan.md's QR-provisioning flow),
/// so a session doesn't have to be re-entered by hand every launch.
abstract class IProvisioningRepository {
  Future<void> save({required String relayUrl, required String apiKey});
  Future<ProvisioningPayload?> load();
  Future<void> clear();
}
