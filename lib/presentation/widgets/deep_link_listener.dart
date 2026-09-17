import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../data/models/telemetry_config.dart';
import '../../domain/usecases/listen_for_deep_links.dart';
import '../../domain/usecases/parse_provisioning_link.dart';
import '../../domain/usecases/save_provisioning.dart';
import '../screens/status_screen.dart';

/// The default MHD/ENET adapter address, per MHD's own guide — used
/// whenever a deep link doesn't specify host/port itself, since a
/// customer's link only needs to carry what's specific to *them*
/// (their relay URL and API key), not the adapter address every
/// customer's own vehicle already has by convention.
const _defaultAdapterHost = '192.168.4.1';
const _defaultAdapterPort = 13400;

/// Listens for freebeamer://connect deep links for the app's whole
/// lifetime (cold start and while running) and, on a valid one,
/// navigates straight to StatusScreen and starts streaming
/// immediately — the "customer taps a link, it just connects" flow.
/// Wraps `child` (the normal app content) rather than replacing it, so
/// manual entry via ConnectScreen still works as a fallback.
class DeepLinkListener extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const DeepLinkListener({super.key, required this.child, required this.navigatorKey});

  @override
  State<DeepLinkListener> createState() => _DeepLinkListenerState();
}

class _DeepLinkListenerState extends State<DeepLinkListener> {
  final ListenForDeepLinks _listenForDeepLinks = sl<ListenForDeepLinks>();
  final ParseProvisioningLink _parseProvisioningLink = sl<ParseProvisioningLink>();
  final SaveProvisioning _saveProvisioning = sl<SaveProvisioning>();
  StreamSubscription<Uri>? _subscription;

  // package:app_links delivers the link that cold-started the app
  // through *both* getInitialLink() and linkStream — a documented
  // quirk of the underlying platform channel, not a one-off. Without
  // this guard, a cold start fires two concurrent connect() attempts
  // against the shared IDoipDataSource singleton, corrupting both.
  String? _lastHandledLink;

  @override
  void initState() {
    super.initState();
    _handleInitialLink();
    _subscription = _listenForDeepLinks.stream().listen(_handleLink);
  }

  Future<void> _handleInitialLink() async {
    final uri = await _listenForDeepLinks.initialLink();
    if (uri != null) await _handleLink(uri);
  }

  Future<void> _handleLink(Uri uri) async {
    if (uri.toString() == _lastHandledLink) return;
    _lastHandledLink = uri.toString();

    final payload = _parseProvisioningLink(uri.toString());
    if (payload == null) return;

    await _saveProvisioning(relayUrl: payload.relayUrl, apiKey: payload.apiKey);
    final telemetryConfig = await buildTelemetryConfig(endpoint: payload.relayUrl, apiKey: payload.apiKey);

    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => StatusScreen(
          host: payload.adapterHost ?? _defaultAdapterHost,
          port: payload.adapterPort ?? _defaultAdapterPort,
          deviceId: 'flutter-${DateTime.now().millisecondsSinceEpoch}',
          telemetryConfig: telemetryConfig,
        ),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
