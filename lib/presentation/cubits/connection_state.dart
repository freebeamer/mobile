import 'package:equatable/equatable.dart';

import '../../core/telemetry/telemetry_upload_status.dart';
import '../../data/models/mhd_value.dart';

enum ConnectionStatus { idle, connecting, streaming, stopped, error }

class VehicleConnectionState extends Equatable {
  final ConnectionStatus status;
  final List<MhdValue> values;

  /// A DoIP/vehicle-connection failure — distinct from [recordingError],
  /// which is a delivery/spool problem the session can otherwise keep
  /// running through.
  final String? connectionError;

  /// The most recent delivery/spool error surfaced by the
  /// TelemetryUploadService, if any ('' to clear). Unlike
  /// [connectionError], this does not by itself mean streaming has
  /// stopped — see [uploadState].
  final String? recordingError;

  final int queuedSamples;
  final int backlogCount;
  final int droppedQueueSamples;
  final int droppedSpoolSamples;
  final TelemetryUploadState uploadState;
  final DateTime? lastFreshSampleAt;
  final double acquisitionRateHz;
  final double catchupProgress;
  final bool catchupInProgress;

  const VehicleConnectionState({
    this.status = ConnectionStatus.idle,
    this.values = const [],
    this.connectionError,
    this.recordingError,
    this.queuedSamples = 0,
    this.backlogCount = 0,
    this.droppedQueueSamples = 0,
    this.droppedSpoolSamples = 0,
    this.uploadState = TelemetryUploadState.idle,
    this.lastFreshSampleAt,
    this.acquisitionRateHz = 0,
    this.catchupProgress = 0,
    this.catchupInProgress = false,
  });

  VehicleConnectionState copyWith({
    ConnectionStatus? status,
    List<MhdValue>? values,
    String? connectionError,
    bool clearConnectionError = false,
    String? recordingError,
    bool clearRecordingError = false,
    int? queuedSamples,
    int? backlogCount,
    int? droppedQueueSamples,
    int? droppedSpoolSamples,
    TelemetryUploadState? uploadState,
    DateTime? lastFreshSampleAt,
    double? acquisitionRateHz,
    double? catchupProgress,
    bool? catchupInProgress,
  }) {
    return VehicleConnectionState(
      status: status ?? this.status,
      values: values ?? this.values,
      connectionError: clearConnectionError ? null : (connectionError ?? this.connectionError),
      recordingError: clearRecordingError ? null : (recordingError ?? this.recordingError),
      queuedSamples: queuedSamples ?? this.queuedSamples,
      backlogCount: backlogCount ?? this.backlogCount,
      droppedQueueSamples: droppedQueueSamples ?? this.droppedQueueSamples,
      droppedSpoolSamples: droppedSpoolSamples ?? this.droppedSpoolSamples,
      uploadState: uploadState ?? this.uploadState,
      lastFreshSampleAt: lastFreshSampleAt ?? this.lastFreshSampleAt,
      acquisitionRateHz: acquisitionRateHz ?? this.acquisitionRateHz,
      catchupProgress: catchupProgress ?? this.catchupProgress,
      catchupInProgress: catchupInProgress ?? this.catchupInProgress,
    );
  }

  /// Populates the telemetry-pipeline fields from a TelemetryUploadStatus
  /// snapshot — the Cubit calls this once per read-loop iteration rather
  /// than each field being set individually.
  VehicleConnectionState withUploadStatus(TelemetryUploadStatus upload) {
    return copyWith(
      queuedSamples: upload.queueDepth,
      backlogCount: upload.spoolPending,
      droppedQueueSamples: upload.queueDroppedCount,
      droppedSpoolSamples: upload.spoolDroppedCount,
      uploadState: upload.uploadState,
      lastFreshSampleAt: upload.lastFreshSampleAt,
      acquisitionRateHz: upload.acquisitionRateHz,
      catchupProgress: upload.catchupProgress,
      catchupInProgress: upload.catchupInProgress,
      recordingError: upload.lastError,
      clearRecordingError: upload.lastError == null,
    );
  }

  @override
  List<Object?> get props => [
        status,
        values,
        connectionError,
        recordingError,
        queuedSamples,
        backlogCount,
        droppedQueueSamples,
        droppedSpoolSamples,
        uploadState,
        lastFreshSampleAt,
        acquisitionRateHz,
        catchupProgress,
        catchupInProgress,
      ];
}
