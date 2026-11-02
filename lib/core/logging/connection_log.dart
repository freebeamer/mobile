import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// One timestamped line in the connection log.
class LogEntry {
  final DateTime time;
  final String tag;
  final String message;
  const LogEntry(this.time, this.tag, this.message);

  @override
  String toString() {
    final t = time.toIso8601String();
    return '$t [$tag] $message';
  }
}

/// A diagnostic log of the adapter connection path: network interfaces,
/// socket dial, every DoIP frame sent/received (hex), and every error.
/// Exists so a failed connection on real hardware can be diagnosed after
/// the fact instead of from a one-line error banner.
///
/// Never log secrets (API keys) through this.
abstract class IConnectionLog {
  void log(String tag, String message);

  /// Snapshot of the in-memory entries, oldest first.
  List<LogEntry> get entries;

  /// Fires after every new entry or clear.
  Stream<void> get changes;

  /// Full log as plain text, for copying/sharing.
  String exportText();

  /// Path of the on-disk copy, or null if file logging isn't available.
  Future<String?> filePath();

  Future<void> clear();
}

/// Renders bytes as space-separated hex, truncated after [max] bytes.
String hex(List<int> bytes, {int max = 96}) {
  final shown = bytes.length > max ? bytes.sublist(0, max) : bytes;
  final s = shown.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  return bytes.length > max ? '$s … (${bytes.length} bytes)' : s;
}

/// Ring buffer in memory plus an append-only text file in the app's
/// documents directory (rotated to `.1` at [maxFileBytes]), so the log
/// survives an app crash or restart.
class ConnectionLogImpl implements IConnectionLog {
  final int capacity;
  final int maxFileBytes;
  final bool writeToFile;
  final Queue<LogEntry> _entries = Queue();
  final StreamController<void> _changes = StreamController.broadcast();
  Future<void> _fileChain = Future.value();
  File? _file;
  bool _fileFailed = false;

  ConnectionLogImpl({
    this.capacity = 3000,
    this.maxFileBytes = 2 * 1024 * 1024,
    this.writeToFile = true,
  });

  @override
  void log(String tag, String message) {
    final entry = LogEntry(DateTime.now(), tag, message);
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    // Also visible in `flutter logs` / `adb logcat`.
    // ignore: avoid_print
    print('FBLOG $entry');
    if (!_changes.isClosed) _changes.add(null);
    if (writeToFile && !_fileFailed) {
      // Serialized so appends never interleave or race rotation.
      _fileChain =
          _fileChain.then((_) => _append('$entry\n')).catchError((_) {});
    }
  }

  Future<File?> _resolveFile() async {
    if (_file != null) return _file;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/connection_log.txt');
      return _file;
    } catch (_) {
      _fileFailed = true;
      return null;
    }
  }

  Future<void> _append(String line) async {
    final file = await _resolveFile();
    if (file == null) return;
    try {
      if (await file.exists() && await file.length() > maxFileBytes) {
        await file.rename('${file.path}.1');
      }
      await file.writeAsString(line, mode: FileMode.append, flush: false);
    } catch (_) {
      // Logging must never break the connection path.
    }
  }

  @override
  List<LogEntry> get entries => List.unmodifiable(_entries);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  String exportText() => _entries.map((e) => e.toString()).join('\n');

  @override
  Future<String?> filePath() async => (await _resolveFile())?.path;

  @override
  Future<void> clear() async {
    _entries.clear();
    if (!_changes.isClosed) _changes.add(null);
    _fileChain = _fileChain.then((_) async {
      final file = await _resolveFile();
      if (file != null && await file.exists()) await file.writeAsString('');
    }).catchError((_) {});
    await _fileChain;
  }
}

/// Discards everything — the default where no log is injected (tests).
class NoopConnectionLog implements IConnectionLog {
  const NoopConnectionLog();
  @override
  void log(String tag, String message) {}
  @override
  List<LogEntry> get entries => const [];
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  String exportText() => '';
  @override
  Future<String?> filePath() async => null;
  @override
  Future<void> clear() async {}
}

/// Logs every non-loopback network interface and its addresses — answers
/// "is the phone actually on the adapter's subnet?" before dialing.
Future<void> logNetworkInterfaces(IConnectionLog log,
    {String? targetHost}) async {
  try {
    final interfaces = await NetworkInterface.list(
        includeLoopback: false, type: InternetAddressType.any);
    if (interfaces.isEmpty) {
      log.log('net', 'no non-loopback network interfaces found');
    }
    for (final iface in interfaces) {
      final addrs = iface.addresses.map((a) => a.address).join(', ');
      log.log('net', 'interface ${iface.name}: $addrs');
    }
    final target =
        targetHost == null ? null : InternetAddress.tryParse(targetHost);
    if (target != null && target.type == InternetAddressType.IPv4) {
      final onSubnet = interfaces.expand((i) => i.addresses).any((a) =>
          a.type == InternetAddressType.IPv4 &&
          _same24(a.rawAddress, target.rawAddress));
      log.log(
          'net',
          onSubnet
              ? 'an interface is on the same /24 as $targetHost'
              : 'WARNING: no interface on the same /24 as $targetHost — '
                  'is the phone joined to the adapter WiFi?');
    }
  } catch (e) {
    log.log('net', 'could not list network interfaces: $e');
  }
}

bool _same24(Uint8List a, Uint8List b) =>
    a.length == 4 &&
    b.length == 4 &&
    a[0] == b[0] &&
    a[1] == b[1] &&
    a[2] == b[2];
