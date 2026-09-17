import 'package:equatable/equatable.dart';

/// The relay URL + client API key (and, optionally, the adapter's own
/// host/port) a `freebeamer-relay client add` deep link encodes. One
/// format, two delivery paths: scanned as a QR code, or tapped as an
/// actual link (SMS, email, a webpage) — both hand the app the exact
/// same `freebeamer://connect?...` URI, so both go through tryParse
/// identically. See docs/freebeamer-relay-v0-plan.md.
///
/// `freebeamer://` is a custom URI scheme, not an HTTPS Android App
/// Link / iOS Universal Link — it works today without a verified
/// domain (this project's real domain isn't live yet), but a raw
/// custom scheme isn't auto-linkified by every SMS/email/messaging
/// client the way a real https:// link is. Once a real domain exists,
/// the intended upgrade is switching this scheme to
/// `https://<domain>/connect` (same query parameters) with the
/// platform-specific App Link/Universal Link verification files
/// hosted there — see mobile/README.md.
class ProvisioningPayload extends Equatable {
  static const scheme = 'freebeamer';
  static const linkHost = 'connect';

  final String relayUrl;
  final String apiKey;
  final String? adapterHost;
  final int? adapterPort;

  const ProvisioningPayload({
    required this.relayUrl,
    required this.apiKey,
    this.adapterHost,
    this.adapterPort,
  });

  /// The deep link this payload round-trips through — what
  /// `freebeamer-relay client add` prints and what a QR code encodes.
  Uri toUri() {
    return Uri(
      scheme: scheme,
      host: linkHost,
      queryParameters: {
        'relay_url': relayUrl,
        'api_key': apiKey,
        if (adapterHost != null) 'host': adapterHost,
        if (adapterPort != null) 'port': adapterPort.toString(),
      },
    );
  }

  /// Parses a freebeamer://connect?... deep link (from a clicked link,
  /// a scanned QR code encoding the same URI, or an Android
  /// `am start -d` intent during testing). Returns null for anything
  /// else — a scanned QR unrelated to FreeBeamer, or a malformed link,
  /// is an expected case, not exceptional.
  static ProvisioningPayload? tryParse(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != scheme || uri.host != linkHost) {
      return null;
    }
    final relayUrl = uri.queryParameters['relay_url'];
    final apiKey = uri.queryParameters['api_key'];
    if (relayUrl == null || relayUrl.isEmpty) return null;
    if (apiKey == null || apiKey.isEmpty) return null;

    return ProvisioningPayload(
      relayUrl: relayUrl,
      apiKey: apiKey,
      adapterHost: uri.queryParameters['host'],
      adapterPort: int.tryParse(uri.queryParameters['port'] ?? ''),
    );
  }

  @override
  List<Object?> get props => [relayUrl, apiKey, adapterHost, adapterPort];
}
