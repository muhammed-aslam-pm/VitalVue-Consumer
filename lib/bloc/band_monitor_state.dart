import 'package:equatable/equatable.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../session/band_session_service.dart';

abstract class BandMonitorState extends Equatable {
  const BandMonitorState();
}

/// App just launched — idle.
class BandIdleState extends BandMonitorState {
  const BandIdleState();
  @override
  List<Object?> get props => [];
}

/// BLE scan is active, listing nearby JStyle devices.
class BandScanningState extends BandMonitorState {
  final List<ScanResult> results;
  const BandScanningState({this.results = const []});

  BandScanningState copyWith({List<ScanResult>? results}) =>
      BandScanningState(results: results ?? this.results);

  @override
  List<Object?> get props => [results];
}

/// Attempting to connect to a device.
class BandConnectingState extends BandMonitorState {
  final String deviceName;
  const BandConnectingState(this.deviceName);
  @override
  List<Object?> get props => [deviceName];
}

/// Connected and streaming — the live-monitoring state.
class BandConnectedState extends BandMonitorState {
  final BandState vitals;
  const BandConnectedState(this.vitals);

  BandConnectedState copyWith({BandState? vitals}) =>
      BandConnectedState(vitals ?? this.vitals);

  @override
  List<Object?> get props => [vitals];
}

/// Disconnected (either by user or unexpectedly).
class BandDisconnectedState extends BandMonitorState {
  final String? reason;
  const BandDisconnectedState({this.reason});
  @override
  List<Object?> get props => [reason];
}
