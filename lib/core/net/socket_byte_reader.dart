import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../logging/connection_log.dart';

/// Buffers bytes from a Socket's stream so exact byte counts can be
/// awaited with a timeout — dart:io's Socket is a Stream<Uint8List>,
/// not the blocking-read abstraction Go's net.Conn (and pkg/doip's
/// io.ReadFull-based receive) relies on, so this exists purely to
/// bridge that gap. Shared by the DoIP and HSFZ data sources.
class SocketByteReader {
  // A plain Uint8List reassigned on every read/write, rather than a
  // BytesBuilder: BytesBuilder.toBytes()'s clear-on-read semantics
  // turned out not to behave as assumed (caught by
  // test/data/datasources/doip_data_source_test.dart, which read a
  // stale duplicate of the first message) — this avoids relying on
  // that ambiguity at all.
  Uint8List _buffer = Uint8List(0);
  final List<Completer<void>> _waiters = [];
  StreamSubscription<Uint8List>? _subscription;
  Object? _error;
  bool _done = false;

  final IConnectionLog _log;

  /// Bytes received but not yet consumed — for diagnostics.
  Uint8List get pending => _buffer;

  /// Builds the protocol's own exception type for read failures.
  final Exception Function(String message) _makeError;

  SocketByteReader(Socket socket, this._log, this._makeError) {
    _subscription = socket.listen(
      (chunk) {
        _buffer = Uint8List.fromList([..._buffer, ...chunk]);
        _wake();
      },
      onError: (Object error) {
        _log.log('rx', 'socket error: ${error.runtimeType}: $error');
        _error = error;
        _wake();
      },
      onDone: () {
        _log.log('rx',
            'remote closed the connection (${_buffer.length} unread byte(s))');
        _done = true;
        _wake();
      },
    );
  }

  void _wake() {
    final waiters = List<Completer<void>>.from(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Future<Uint8List> readExactly(int n, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_buffer.length < n) {
      if (_error != null) throw _makeError('socket error: $_error');
      if (_done) throw _makeError('connection closed while reading');
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw _makeError('timed out reading from socket');
      }
      final waiter = Completer<void>();
      _waiters.add(waiter);
      try {
        await waiter.future.timeout(remaining);
      } on TimeoutException {
        _waiters.remove(waiter);
        throw _makeError('timed out reading from socket');
      }
    }
    final result = Uint8List.sublistView(_buffer, 0, n);
    _buffer = Uint8List.sublistView(_buffer, n);
    return result;
  }

  Future<void> close() async {
    await _subscription?.cancel();
  }
}
