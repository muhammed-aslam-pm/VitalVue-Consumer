import 'package:equatable/equatable.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../protocol/jstyle_codec.dart' show PersonalInfo;
abstract class BandMonitorEvent extends Equatable {
  const BandMonitorEvent();
}

class StartScan extends BandMonitorEvent {
  final bool showAll;
  const StartScan({this.showAll = false});
  @override
  List<Object?> get props => [showAll];
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

class UpdateBandContext extends BandMonitorEvent {
  final int patientId;
  final PersonalInfo personalInfo;
  
  const UpdateBandContext({
    required this.patientId,
    required this.personalInfo,
  });

  @override
  List<Object?> get props => [patientId, personalInfo];
}
