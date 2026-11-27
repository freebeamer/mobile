import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/logging/connection_log.dart';
import '../../doip/frame.dart';
import '../../doip/payload_types.dart';
import '../../hsfz/frame.dart';
import 'doip_data_source.dart';
import 'hsfz_data_source.dart';

enum EnetProtocol { hsfz, doip }

/// Settings for the fallback port scanner. Defaults mirror pkg/enet.
class EnetScanOptions {
  /// Ports tried, in order, after the requested one fails.
  final List<int> knownPorts;

  /// Ports never probed. 5377 is MHD's own channel to its adapter
  /// (observed 2026-11-27): not the car, and our frames could disturb it.
  final Set<int> skipPorts;

  /// Ports swept for open TCP services (null = 1-65535).
  final List<int>? sweepPorts;
  final Duration sweepTimeout;
  final int sweepConcurrency;
  final Duration sweepDeadline;

  /// Turns the whole fallback off: only the requested port is tried.
  final bool enabled;

  const EnetScanOptions({
    this.knownPorts = const [
      hsfzDefaultTcpPort,
      defaultTcpPort,
      hsfzControlPort
    ],
    this.skipPorts = const {5377},
    this.sweepPorts,
    this.sweepTimeout = const Duration(milliseconds: 400),
    this.sweepConcurrency = 64,
    this.sweepDeadline = const Duration(seconds: 90),
    this.enabled = true,
  });
}

/// Connects to a BMW ENET endpoint without the caller knowing the
/// protocol or port. Mirrors pkg/enet.Connect.
///
/// [connect] only records host and port. [activate] then tries the
/// requested port (HSFZ first, or DoIP first on 13400); if no ECU
/// answers it tries the other known ENET ports, then sweeps the host for
/// open TCP ports and probes each. The first port where an ECU answers
/// becomes the active link, and every later call goes to it.
class EnetDataSourceImpl implements IDoipDataSource {
  final IDoipDataSource _doip;
  final HsfzDataSourceImpl _hsfz;
  final IConnectionLog _log;
  final EnetScanOptions scan;

  String? _host;
  int _port = hsfzDefaultTcpPort;
  Duration _dialTimeout = const Duration(seconds: 2);
  IDoipDataSource? _active;

  /// What the last successful [activate] found.
  EnetProtocol? protocol;
  int? activePort;
  bool scanned = false;

  EnetDataSourceImpl({
    required IDoipDataSource doip,
    required HsfzDataSourceImpl hsfz,
    IConnectionLog log = const NoopConnectionLog(),
    this.scan = const EnetScanOptions(),
  })  : _doip = doip,
        _hsfz = hsfz,
        _log = log;

  @override
  int? get targetAddress => _active?.targetAddress;

  @override
  Future<void> connect(String address, int port,
      {Duration timeout = const Duration(seconds: 2)}) async {
    await close();
    _host = address;
    _port = port;
    _dialTimeout = timeout;
  }

  @override
  Future<int> activate(int sourceAddress, int activationType,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final host = _host;
    if (host == null) throw DoipException('not connected; call connect first');
    final failures = <String>[];
    final identified = <String>[];
    final tried = <int>{};

    Future<int?> tryPort(int port) async {
      tried.add(port);
      final order = port == defaultTcpPort
          ? [EnetProtocol.doip, EnetProtocol.hsfz]
          : [EnetProtocol.hsfz, EnetProtocol.doip];
      for (final p in order) {
        final source = p == EnetProtocol.hsfz ? _hsfz : _doip;
        try {
          await source.connect(host, port, timeout: _dialTimeout);
          final target = await source.activate(sourceAddress, activationType,
              timeout: timeout);
          _active = source;
          protocol = p;
          activePort = port;
          _log.log('enet',
              'connected: ${p.name} on port $port, target 0x${target.toRadixString(16)}');
          return target;
        } catch (e) {
          await source.close();
          final message = e is HsfzException
              ? e.message
              : e is DoipException
                  ? e.message
                  : '$e';
          _log.log('enet', 'port $port ${p.name}: $message');
          failures.add('port $port ${p.name}: $message');
          final spokeIt = (e is HsfzException && e.identified) ||
              (e is DoipException &&
                  e.message.startsWith('routing activation denied'));
          if (spokeIt) {
            identified.add('port $port speaks ${p.name} but: $message');
          }
          if (e is SocketException && _isRefused(e)) break; // nothing listening
        }
      }
      return null;
    }

    scanned = false;
    _log.log('enet', 'trying $host:$_port (auto-detect)');
    final direct = await tryPort(_port);
    if (direct != null) return direct;
    if (!scan.enabled) throw _notFound(host, identified, failures, null);

    scanned = true;
    for (final port in scan.knownPorts) {
      if (tried.contains(port)) continue;
      _log.log('enet', 'fallback: trying known ENET port $port');
      final target = await tryPort(port);
      if (target != null) return target;
    }

    _log.log('enet', 'fallback: sweeping $host for open TCP ports');
    final open = await _sweep(host, tried);
    _log.log('enet', 'sweep found ${open.length} open port(s): $open');
    for (final port in open) {
      final target = await tryPort(port);
      if (target != null) return target;
    }
    throw _notFound(host, identified, failures, open);
  }

  @override
  Future<Uint8List> sendDiagnostic(Uint8List request,
      {Duration timeout = const Duration(seconds: 2)}) {
    final active = _active;
    if (active == null) {
      throw DoipException('not activated; call activate first');
    }
    return active.sendDiagnostic(request, timeout: timeout);
  }

  @override
  Future<void> close() async {
    await _active?.close();
    _active = null;
    protocol = null;
    activePort = null;
  }

  Future<List<int>> _sweep(String host, Set<int> tried) async {
    final ports = (scan.sweepPorts ?? List<int>.generate(65535, (i) => i + 1))
        .where((p) => !tried.contains(p) && !scan.skipPorts.contains(p))
        .toList();
    final open = <int>[];
    final deadline = DateTime.now().add(scan.sweepDeadline);
    var next = 0;
    var checked = 0;
    Future<void> worker() async {
      while (next < ports.length) {
        if (DateTime.now().isAfter(deadline)) return;
        final port = ports[next++];
        try {
          final socket =
              await Socket.connect(host, port, timeout: scan.sweepTimeout);
          socket.destroy();
          open.add(port);
        } catch (_) {
          // closed or filtered
        }
        if (++checked % 5000 == 0) {
          _log.log('enet', 'sweep: $checked/${ports.length} ports checked');
        }
      }
    }

    await Future.wait(List.generate(scan.sweepConcurrency, (_) => worker()));
    if (next < ports.length) {
      _log.log('enet',
          'sweep stopped at the ${scan.sweepDeadline.inSeconds}s deadline');
    }
    open.sort();
    return open;
  }

  Exception _notFound(String host, List<String> identified,
      List<String> failures, List<int>? open) {
    final parts = [
      'no HSFZ or DoIP diagnostic service found on $host',
      ...identified,
      if (failures.isNotEmpty) failures.first,
      open == null
          ? 'fallback scan disabled'
          : 'sweep found open port(s) $open, none answered as HSFZ or DoIP',
    ];
    return DoipException(parts.join('; '));
  }

  static bool _isRefused(SocketException e) =>
      const {111, 61, 10061}.contains(e.osError?.errorCode) ||
      e.message.toLowerCase().contains('refused');
}
