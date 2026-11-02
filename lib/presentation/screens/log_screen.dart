import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/service_locator.dart';
import '../../core/logging/connection_log.dart';

/// Shows the diagnostic connection log live, with copy-all and clear.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final IConnectionLog _log = sl<IConnectionLog>();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<void>? _sub;
  String? _path;

  @override
  void initState() {
    super.initState();
    _sub = _log.changes.listen((_) {
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
    _log.filePath().then((p) {
      if (mounted) setState(() => _path = p);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _log.exportText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Log copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _log.entries;
    final errorColor = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection log'),
        actions: [
          IconButton(
              tooltip: 'Copy all',
              icon: const Icon(Icons.copy),
              onPressed: _copy),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await _log.clear();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_path != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text('Saved to $_path',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text('No log entries yet. Try connecting.'))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final bad = e.message.contains('FAILED') ||
                          e.message.contains('WARNING') ||
                          e.message.contains('NEGATIVE') ||
                          e.message.contains('error');
                      final time = e.time.toIso8601String().substring(11, 23);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: SelectableText(
                          '$time [${e.tag}] ${e.message}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: bad ? errorColor : null,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
