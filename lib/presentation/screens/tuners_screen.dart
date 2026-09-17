import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/di/service_locator.dart';
import '../../data/models/device_pairing.dart';
import '../cubits/tuners_cubit.dart';
import '../cubits/tuners_state.dart';
import 'status_screen.dart';

/// The app's home screen: every tuning session this phone has ever
/// paired with (tap to reconnect — no rescanning needed, see
/// ConnectionCubit/AuthenticateDevice), plus scanning or pasting a new
/// single-use pairing link to add one. Adapter IP entry is the only
/// other setup this app has for v0.
class TunersScreen extends StatefulWidget {
  const TunersScreen({super.key});

  @override
  State<TunersScreen> createState() => _TunersScreenState();
}

class _TunersScreenState extends State<TunersScreen> {
  late final TunersCubit _cubit;
  final _hostController = TextEditingController(text: '192.168.4.1');
  final _portController = TextEditingController(text: '13400');
  final _linkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cubit = sl<TunersCubit>()..load();
  }

  @override
  void dispose() {
    _cubit.close();
    _hostController.dispose();
    _portController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (result != null) await _consume(result);
  }

  Future<void> _consume(String raw) async {
    final pairing = await _cubit.consumeLink(raw);
    if (pairing == null) return;
    _linkController.clear();
    if (mounted) _connect(pairing);
  }

  void _connect(DevicePairing pairing) {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 13400;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatusScreen(
          pairing: pairing,
          host: host,
          port: port,
          deviceId: 'flutter-${DateTime.now().millisecondsSinceEpoch}',
        ),
      ),
    );
  }

  Future<void> _forget(DevicePairing pairing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this tuner?'),
        content: Text(
            '${pairing.displayName.isNotEmpty ? pairing.displayName : pairing.clientId} will need a new pairing link to reconnect.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _cubit.forget(pairing.clientId);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        appBar: AppBar(title: const Text('FreeBeamer')),
        body: BlocBuilder<TunersCubit, TunersState>(
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(labelText: 'Adapter IP'),
                  ),
                  TextField(
                    controller: _portController,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 20),
                  Text('Tuners', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (!state.loaded)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (state.pairings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                          'No saved tuners yet. Scan or paste a pairing link below to connect for the first time.'),
                    )
                  else
                    ...state.pairings.map(
                      (pairing) => Card(
                        child: ListTile(
                          title: Text(pairing.displayName.isNotEmpty
                              ? pairing.displayName
                              : pairing.clientId),
                          subtitle: Text(pairing.relayUrl),
                          onTap: () => _connect(pairing),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Forget',
                            onPressed: () => _forget(pairing),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(state.error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  if (state.qrError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(state.qrError!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  OutlinedButton.icon(
                    onPressed: state.busy ? null : _scanQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan pairing QR code'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _linkController,
                    decoration: const InputDecoration(labelText: 'Or paste a pairing link'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed:
                        state.busy ? null : () => _consume(_linkController.text.trim()),
                    child: state.busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Pair'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QrScanScreen extends StatelessWidget {
  const _QrScanScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR code')),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            Navigator.of(context).pop(barcodes.first.rawValue);
          }
        },
      ),
    );
  }
}
