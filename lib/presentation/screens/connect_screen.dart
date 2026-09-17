import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/di/service_locator.dart';
import '../../data/models/telemetry_config.dart';
import '../cubits/provisioning_cubit.dart';
import '../cubits/provisioning_state.dart';
import 'status_screen.dart';

/// Adapter IP entry + relay provisioning (QR scan or manual entry) —
/// the only setup screen this app has for v0.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final ProvisioningCubit _provisioningCubit;
  final _hostController = TextEditingController(text: '192.168.4.1');
  final _portController = TextEditingController(text: '13400');
  final _relayUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _provisioningCubit = sl<ProvisioningCubit>()..load();
  }

  @override
  void dispose() {
    _provisioningCubit.close();
    _hostController.dispose();
    _portController.dispose();
    _relayUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (result != null) {
      await _provisioningCubit.applyScannedQrCode(result);
    }
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 13400;
    final provisioning = _provisioningCubit.state;

    await _provisioningCubit.persist();

    final telemetryConfig = await buildTelemetryConfig(endpoint: provisioning.relayUrl, apiKey: provisioning.apiKey);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatusScreen(
          host: host,
          port: port,
          deviceId: 'flutter-${DateTime.now().millisecondsSinceEpoch}',
          telemetryConfig: telemetryConfig,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _provisioningCubit,
      child: Scaffold(
        appBar: AppBar(title: const Text('Connect')),
        body: BlocListener<ProvisioningCubit, ProvisioningState>(
          listenWhen: (previous, current) =>
              previous.relayUrl != current.relayUrl || previous.apiKey != current.apiKey,
          listener: (context, state) {
            // Sync external changes (initial load, a QR scan) into
            // the persistent controllers without fighting the user's
            // own typing — onChanged below pushes local edits the
            // other direction, into the Cubit.
            if (_relayUrlController.text != state.relayUrl) {
              _relayUrlController.text = state.relayUrl;
            }
            if (_apiKeyController.text != state.apiKey) {
              _apiKeyController.text = state.apiKey;
            }
          },
          child: BlocBuilder<ProvisioningCubit, ProvisioningState>(
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
                    const SizedBox(height: 16),
                    TextField(
                      controller: _relayUrlController,
                      decoration: const InputDecoration(labelText: 'Relay upload URL'),
                      onChanged: _provisioningCubit.updateRelayUrl,
                    ),
                    TextField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(labelText: 'API key'),
                      obscureText: true,
                      onChanged: _provisioningCubit.updateApiKey,
                    ),
                    if (state.qrError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          state.qrError!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _scanQr,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan provisioning QR code'),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(onPressed: _connect, child: const Text('Connect')),
                  ],
                ),
              );
            },
          ),
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
