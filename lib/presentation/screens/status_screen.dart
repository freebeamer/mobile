import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/di/service_locator.dart';
import '../../core/telemetry/telemetry_upload_status.dart';
import '../../data/models/device_pairing.dart';
import '../../domain/usecases/logout_device.dart';
import '../cubits/connection_cubit.dart';
import '../cubits/connection_state.dart';

/// Shows connection/streaming status and the last-seen field values —
/// a client-side sanity check, not a dashboard. Gauges/charts/history
/// are the desktop app's (or a future web dashboard's) job.
class StatusScreen extends StatefulWidget {
  final DevicePairing pairing;
  final String host;
  final int port;
  final String deviceId;

  const StatusScreen({
    super.key,
    required this.pairing,
    required this.host,
    required this.port,
    required this.deviceId,
  });

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> with WidgetsBindingObserver {
  late final ConnectionCubit _cubit;
  final LogoutDevice _logoutDevice = sl<LogoutDevice>();

  @override
  void initState() {
    super.initState();
    _cubit = sl<ConnectionCubit>();
    WidgetsBinding.instance.addObserver(this);
    // The phone must stay joined to the adapter's WiFi for the whole
    // session regardless of app state; this only keeps the screen
    // itself from sleeping. See mobile/README.md's "Background
    // operation" section for why background/headless streaming is out
    // of scope — didChangeAppLifecycleState below is what actually
    // enforces that, by stopping the session once the app is no longer
    // in the foreground.
    WakelockPlus.enable();
    _cubit.start(
      pairing: widget.pairing,
      address: widget.host,
      port: widget.port,
      deviceId: widget.deviceId,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _cubit.stop();
    }
  }

  /// Leaving this screen "logs out" of the tuning session — the relay
  /// session token is revoked (best-effort; see LogoutDevice), but the
  /// device's DevicePairing itself is untouched, so the tuners panel
  /// still offers one-tap reconnect afterward without rescanning.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cubit.stop();
    final sessionToken = _cubit.currentSessionToken;
    if (sessionToken != null && sessionToken.isNotEmpty) {
      unawaited(_logoutDevice(
          relayUrl: widget.pairing.relayUrl, sessionToken: sessionToken));
    }
    _cubit.close();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.host}:${widget.port}')),
        body: BlocBuilder<ConnectionCubit, VehicleConnectionState>(
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusBanner(state: state),
                  const SizedBox(height: 4),
                  _TelemetryStatusLine(state: state),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      children: state.values
                          .map(
                            (v) => ListTile(
                              dense: true,
                              title: Text(v.field.title),
                              trailing: Text('${v.value.toStringAsFixed(2)} ${v.field.units}'),
                            ),
                          )
                          .toList(),
                    ),
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

class _StatusBanner extends StatelessWidget {
  final VehicleConnectionState state;
  const _StatusBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final String label = switch (state.status) {
      ConnectionStatus.idle => 'Idle',
      ConnectionStatus.connecting => 'Connecting…',
      ConnectionStatus.streaming => switch (state.uploadState) {
          TelemetryUploadState.uploading => 'Streaming (live)',
          TelemetryUploadState.idle => 'Streaming (live)',
          TelemetryUploadState.backingOff =>
            'Streaming (buffered — no connection to relay)',
          TelemetryUploadState.stopped => 'Streaming (buffered)',
        },
      ConnectionStatus.stopped => 'Stopped',
      ConnectionStatus.error => 'Error: ${state.connectionError ?? 'unknown'}',
    };
    return Text(label, style: Theme.of(context).textTheme.titleMedium);
  }
}

/// Reports the telemetry pipeline's own state — queue/backlog depth,
/// catch-up progress, and the age of the last freshly-delivered sample —
/// separately from the connection banner above, since these two can
/// legitimately disagree (e.g. still connected to the vehicle while the
/// relay is unreachable).
class _TelemetryStatusLine extends StatelessWidget {
  final VehicleConnectionState state;
  const _TelemetryStatusLine({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.status != ConnectionStatus.streaming) return const SizedBox.shrink();
    final parts = <String>[
      '${state.acquisitionRateHz.toStringAsFixed(1)}Hz',
      if (state.backlogCount > 0) 'backlog ${state.backlogCount}',
      if (state.catchupInProgress)
        'catching up ${(state.catchupProgress * 100).toStringAsFixed(0)}%',
      if (state.lastFreshSampleAt != null)
        'last fresh ${DateTime.now().difference(state.lastFreshSampleAt!).inSeconds}s ago',
      if (state.droppedQueueSamples > 0 || state.droppedSpoolSamples > 0)
        'dropped ${state.droppedQueueSamples + state.droppedSpoolSamples}',
      if (state.recordingError != null) 'error: ${state.recordingError}',
    ];
    return Text(parts.join(' · '), style: Theme.of(context).textTheme.bodySmall);
  }
}
