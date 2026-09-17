import 'package:equatable/equatable.dart';

/// What a [TelemetryUploadService] is currently doing — the Dart mirror of
/// pkg/telemetry.UploadState.
enum TelemetryUploadState { idle, uploading, backingOff, stopped }

/// A point-in-time, read-only view of an acquisition + spool + upload
/// pipeline's state — the Dart mirror of pkg/telemetry.StatusSnapshot.
class TelemetryUploadStatus extends Equatable {
  final int queueDepth;
  final int queueDroppedCount;
  final int spoolPending;
  final int spoolDroppedCount;
  final TelemetryUploadState uploadState;
  final DateTime? lastFreshSampleAt;
  final String? lastError;

  /// Measured from actual inter-sample acquisition timestamps, never
  /// derived from the configured sample interval.
  final double acquisitionRateHz;

  final bool catchupInProgress;
  final double catchupProgress; // 0..1, meaningful only if catchupInProgress
  final int catchupPending;

  const TelemetryUploadStatus({
    this.queueDepth = 0,
    this.queueDroppedCount = 0,
    this.spoolPending = 0,
    this.spoolDroppedCount = 0,
    this.uploadState = TelemetryUploadState.idle,
    this.lastFreshSampleAt,
    this.lastError,
    this.acquisitionRateHz = 0,
    this.catchupInProgress = false,
    this.catchupProgress = 0,
    this.catchupPending = 0,
  });

  TelemetryUploadStatus copyWith({
    int? queueDepth,
    int? queueDroppedCount,
    int? spoolPending,
    int? spoolDroppedCount,
    TelemetryUploadState? uploadState,
    DateTime? lastFreshSampleAt,
    String? lastError,
    bool clearError = false,
    double? acquisitionRateHz,
    bool? catchupInProgress,
    double? catchupProgress,
    int? catchupPending,
  }) {
    return TelemetryUploadStatus(
      queueDepth: queueDepth ?? this.queueDepth,
      queueDroppedCount: queueDroppedCount ?? this.queueDroppedCount,
      spoolPending: spoolPending ?? this.spoolPending,
      spoolDroppedCount: spoolDroppedCount ?? this.spoolDroppedCount,
      uploadState: uploadState ?? this.uploadState,
      lastFreshSampleAt: lastFreshSampleAt ?? this.lastFreshSampleAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
      acquisitionRateHz: acquisitionRateHz ?? this.acquisitionRateHz,
      catchupInProgress: catchupInProgress ?? this.catchupInProgress,
      catchupProgress: catchupProgress ?? this.catchupProgress,
      catchupPending: catchupPending ?? this.catchupPending,
    );
  }

  @override
  List<Object?> get props => [
        queueDepth,
        queueDroppedCount,
        spoolPending,
        spoolDroppedCount,
        uploadState,
        lastFreshSampleAt,
        lastError,
        acquisitionRateHz,
        catchupInProgress,
        catchupProgress,
        catchupPending,
      ];
}
