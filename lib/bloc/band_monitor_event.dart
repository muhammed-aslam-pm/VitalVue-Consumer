import 'package:equatable/equatable.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

abstract class BandMonitorEvent extends Equatable {
  const BandMonitorEvent();
}

class StartScan extends BandMonitorEvent {
  const StartScan();
  @override
  List<Object?> get props => [];
}

class StopScan extends BandMonitorEvent {
  const StopScan();
  @override
  List<Object?> get props => [];
}

class ConnectToBand extends BandMonitorEvent {
  final BluetoothDevice device;
  const ConnectToBand(this.device);
  @override
  List<Object?> get props => [device];
}

class DisconnectBand extends BandMonitorEvent {
  const DisconnectBand();
  @override
  List<Object?> get props => [];
}
