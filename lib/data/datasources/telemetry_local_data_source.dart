import 'dart:convert';
import 'dart:io';

import '../../core/error/exceptions.dart';
import '../models/telemetry_sample.dart';

/// Default byte cap for a spool file, used when [ITelemetryLocalDataSource.append]
/// isn't given an explicit maxBytes — mirrors pkg/telemetry.DefaultSpoolMaxBytes,
/// but smaller (20 MiB vs Go's 50 MiB) since mobile storage is more
/// quota-constrained.
const defaultSpoolMaxBytes = 20 * 1024 * 1024;

/// What [ITelemetryLocalDataSource.append] does once a spool file reaches
/// its byte cap — mirrors pkg/telemetry.OverflowPolicy.
enum SpoolOverflowPolicy {
  /// Drop the new sample and keep recording; append returns false.
  drop,

  /// Refuse the new sample with a [SpoolFullException]; the caller decides
  /// whether that means stopping acquisition entirely.
  stop,
}

/// A small ordered on-disk queue of undelivered TelemetrySamples, one
/// JSON object per line (oldest first) at a given file path — the
/// same JSON-Lines approach pkg/telemetry.Uploader uses (see
/// pkg/telemetry/uploader.go), so buffering *behavior*, not just wire
/// format, matches the Go reference exactly. Deliberately a plain
/// file rather than sqflite/Hive: the data need is a small ordered
/// queue, not a queryable store.
abstract class ITelemetryLocalDataSource {
  Future<bool> isEmpty(String path);

  /// Appends sample to path, one JSON object per line. Once the file would
  /// exceed maxBytes, behavior follows onFull: [SpoolOverflowPolicy.drop]
  /// counts the drop and returns false without writing;
  /// [SpoolOverflowPolicy.stop] throws [SpoolFullException] without
  /// writing. Returns true if the sample was actually written.
  Future<bool> append(TelemetrySample sample, String path,
      {int maxBytes = defaultSpoolMaxBytes,
      SpoolOverflowPolicy onFull = SpoolOverflowPolicy.drop});

  /// Every currently buffered sample's raw JSON line, oldest first.
  /// Malformed lines are the caller's concern to skip (mirrors
  /// pkg/telemetry.Uploader.FlushBuffer dropping malformed lines
  /// rather than blocking forever).
  Future<List<String>> readLines(String path);

  /// The number of samples currently buffered at path — mirrors
  /// pkg/telemetry.Spool.Pending.
  Future<int> pendingCount(String path);

  /// Replaces the buffer file's contents with exactly lines (deletes
  /// the file entirely if lines is empty).
  Future<void> rewrite(List<String> lines, String path);
}

class TelemetryLocalDataSourceImpl implements ITelemetryLocalDataSource {
  @override
  Future<bool> isEmpty(String path) async {
    final file = File(path);
    if (!await file.exists()) return true;
    return (await file.length()) == 0;
  }

  @override
  Future<bool> append(TelemetrySample sample, String path,
      {int maxBytes = defaultSpoolMaxBytes,
      SpoolOverflowPolicy onFull = SpoolOverflowPolicy.drop}) async {
    final file = File(path);
    final line = '${jsonEncode(sample.toJson())}\n';
    final currentSize = await file.exists() ? await file.length() : 0;
    if (currentSize + utf8.encode(line).length > maxBytes) {
      if (onFull == SpoolOverflowPolicy.stop) {
        throw SpoolFullException('spool at $path is full ($maxBytes bytes)');
      }
      return false;
    }
    await file.writeAsString(line, mode: FileMode.append, flush: true);
    return true;
  }

  @override
  Future<List<String>> readLines(String path) async {
    final file = File(path);
    if (!await file.exists()) return const [];
    final content = await file.readAsString();
    return content.split('\n').where((line) => line.isNotEmpty).toList();
  }

  @override
  Future<int> pendingCount(String path) async => (await readLines(path)).length;

  @override
  Future<void> rewrite(List<String> lines, String path) async {
    final file = File(path);
    if (lines.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString('${lines.join('\n')}\n');
  }
}
