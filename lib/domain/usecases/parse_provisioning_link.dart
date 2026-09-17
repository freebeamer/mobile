import '../../data/models/provisioning_payload.dart';

/// Parses a freebeamer://connect?... provisioning link — whether it
/// arrived as a scanned QR code or a tapped deep link, both are the
/// same string here. Pure logic (no I/O, no repository dependency) —
/// kept as its own use case anyway for consistency with this app's
/// layering: presentation code calls use cases, never data-layer
/// models directly.
class ParseProvisioningLink {
  ProvisioningPayload? call(String raw) => ProvisioningPayload.tryParse(raw);
}
