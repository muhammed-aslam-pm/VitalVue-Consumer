import 'package:equatable/equatable.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../session/band_session_service.dart';

abstract class BandMonitorState extends Equatable {
  final bool isSyncing;
  final int syncRemaining;

  const BandMonitorState({
    this.isSyncing = false,
    this.syncRemaining = 0,
  });
}

/// App just launched — idle.
class BandIdleState extends BandMonitorState {
  const BandIdleState({
    super.isSyncing,
    super.syncRemaining,
  });

  @override
  List<Object?> get props => [isSyncing, syncRemaining];
}

/// BLE scan is active, listing nearby JStyle devices.
class BandScanningState extends BandMonitorState {
  final List<ScanResult> results;
  const BandScanningState({
    this.results = const [],
    super.isSyncing,
    super.syncRemaining,
  });

  BandScanningState copyWith({
    List<ScanResult>? results,
    bool? isSyncing,
    int? syncRemaining,
  }) =>
      BandScanningState(
        results: results ?? this.results,
        isSyncing: isSyncing ?? this.isSyncing,
        syncRemaining: syncRemaining ?? this.syncRemaining,
      );

  @override
  List<Object?> get props => [results, isSyncing, syncRemaining];
}

/// Attempting to connect to a device.
class BandConnectingState extends BandMonitorState {
  final String deviceName;
  const BandConnectingState(
    this.deviceName, {
    super.isSyncing,
    super.syncRemaining,
  });

  @override
  List<Object?> get props => [deviceName, isSyncing, syncRemaining];
}

/// Connected and streaming — the live-monitoring state.
class BandConnectedState extends BandMonitorState {
  final BandState vitals;
  const BandConnectedState(
    this.vitals, {
    super.isSyncing,
    super.syncRemaining,
  });

  BandConnectedState copyWith({
    BandState? vitals,
    bool? isSyncing,
    int? syncRemaining,
  }) =>
      BandConnectedState(
        vitals ?? this.vitals,
        isSyncing: isSyncing ?? this.isSyncing,
        syncRemaining: syncRemaining ?? this.syncRemaining,
      );

  @override
  List<Object?> get props => [vitals, isSyncing, syncRemaining];
}

/// Disconnected (either by user or unexpectedly).
class BandDisconnectedState extends BandMonitorState {
  final String? reason;
  const BandDisconnectedState({
    this.reason,
    super.isSyncing,
    super.syncRemaining,
  });

  @override
  List<Object?> get props => [reason, isSyncing, syncRemaining];
}
