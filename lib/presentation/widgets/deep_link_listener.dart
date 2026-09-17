import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../data/models/device_pairing.dart';
import '../../domain/usecases/listen_for_deep_links.dart';
import '../../domain/usecases/pair_device.dart';
import '../../domain/usecases/parse_provisioning_link.dart';
import '../screens/status_screen.dart';

/// The default MHD/ENET adapter address, per MHD's own guide — used
/// whenever a deep link doesn't specify host/port itself, since a
/// customer's link only needs to carry what's specific to *them*
/// (their relay URL and pairing token), not the adapter address every
/// customer's own vehicle already has by convention.
const _defaultAdapterHost = '192.168.4.1';
const _defaultAdapterPort = 13400;

/// Listens for freebeamer://connect deep links for the app's whole
/// lifetime (cold start and while running) and, on a valid one, pairs
/// the device (see PairDevice) and navigates straight to StatusScreen
/// to start streaming immediately — the "customer taps a link, it just
/// connects" flow. Wraps `child` (the normal app content) rather than
/// replacing it, so the tuners panel's manual scan/paste path still
/// works as a fallback (and is what surfaces a proper error if pairing
/// fails here — see _handleLink's silent-drop below).
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
  final PairDevice _pairDevice = sl<PairDevice>();
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

    DevicePairing pairing;
    try {
      pairing = await _pairDevice(payload);
    } catch (_) {
      // Already used/expired, or the relay was unreachable: the user
      // can still retry via the tuners panel's paste field, which
      // surfaces a proper error message.
      return;
    }

    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => StatusScreen(
          pairing: pairing,
          host: payload.adapterHost ?? _defaultAdapterHost,
          port: payload.adapterPort ?? _defaultAdapterPort,
          deviceId: 'flutter-${DateTime.now().millisecondsSinceEpoch}',
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
