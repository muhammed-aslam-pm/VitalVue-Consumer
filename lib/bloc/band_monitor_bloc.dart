import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:flutter_background_service/flutter_background_service.dart';

import '../ble/band_ble_client.dart';
import '../cloud/band_vitals_api.dart';
import '../protocol/jstyle_codec.dart';
import '../session/band_session_service.dart';
import 'band_monitor_event.dart';
import 'band_monitor_state.dart';

// ── Internal events (private, never exposed to UI) ────────────────────────────

/// Fired by the session service whenever the band state changes.
/// Using add() instead of emit() from a subscription is the correct BLoC
/// pattern — emit() must only be called within an active event handler.
final class _BandStateUpdated extends BandMonitorEvent {
  final BandState state;
  const _BandStateUpdated(this.state);
  @override
  List<Object?> get props => [state];
}

/// Fired by the scan stream for each new result.
final class _ScanResultReceived extends BandMonitorEvent {
  final ScanResult result;
  const _ScanResultReceived(this.result);
  @override
  List<Object?> get props => [result.device.remoteId.str];
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

/// Bridges [BandSessionService] ↔ UI.
///
/// Key design rule (flutter_bloc):
///   emit() may only be called inside an active async event handler.
///   Any external async event (stream subscription, timer callback) must
///   use add() to dispatch an internal event, never emit() directly.
class BandMonitorBloc extends Bloc<BandMonitorEvent, BandMonitorState> {
  BandMonitorBloc({
    required BandVitalsApi vitalsApi,
    required int patientId,
    required String deviceId,
    required PersonalInfo personalInfo,
  })  : _vitalsApi = vitalsApi,
        _patientId = patientId,
        _deviceId = deviceId,
        _personalInfo = personalInfo,
        super(const BandIdleState()) {
    on<StartScan>(_onStartScan);
    on<StopScan>(_onStopScan);
    on<ConnectToBand>(_onConnect);
    on<DisconnectBand>(_onDisconnect);
    on<UpdateBandContext>(_onUpdateBandContext);
    // Internal events — handled inline with lambdas for brevity.
    on<_ScanResultReceived>((event, emit) {
      if (state is BandScanningState) {
        final current = state as BandScanningState;
        // Deduplicate by remote ID.
        final seen = {
          for (final r in current.results) r.device.remoteId.str: r,
        };
        seen[event.result.device.remoteId.str] = event.result;
        emit(BandScanningState(results: seen.values.toList()));
      }
    });
    on<_BandStateUpdated>((event, emit) {
      final s = event.state;
      if (s.connectionStatus == BleConnectionStatus.disconnected) {
        emit(const BandDisconnectedState());
      } else {
        emit(BandConnectedState(s));
      }
    });

    // Listen to background service updates
    _bgSub = FlutterBackgroundService().on('vitals_update').listen((data) {
      if (data == null) return;
      
      BleConnectionStatus status;
      if (data['status'] == BleConnectionStatus.connected.name) {
        status = BleConnectionStatus.connected;
      } else if (data['status'] == BleConnectionStatus.connecting.name) {
        status = BleConnectionStatus.connecting;
      } else {
        status = BleConnectionStatus.disconnected;
      }

      final state = BandState(
        connectionStatus: status,
        hr: data['hr'] as int? ?? 0,
        spo2: data['spo2'] as int? ?? 0,
        tempC: (data['tempC'] as num?)?.toDouble() ?? 0.0,
        systolic: data['bpSys'] as int?,
        diastolic: data['bpDia'] as int?,
        hrv: data['hrv'] as int?,
        stress: data['stress'] as int?,
        steps: data['steps'] as int? ?? 0,
        calories: (data['calories'] as num?)?.toDouble() ?? 0.0,
        distanceKm: (data['distanceKm'] as num?)?.toDouble() ?? 0.0,
        battery: data['battery'] as int? ?? -1,
        isRemoved: data['isRemoved'] as bool? ?? false,
      );
      
      if (!isClosed) add(_BandStateUpdated(state));
    });
  }

  final BandVitalsApi _vitalsApi;
  int _patientId;
  final String _deviceId;
  PersonalInfo _personalInfo;

  StreamSubscription<Map<String, dynamic>?>? _bgSub;
  StreamSubscription<ScanResult>? _scanSub;

  // ── Scan ──────────────────────────────────────────────────────────────────

  Future<void> _onStartScan(StartScan _, Emitter<BandMonitorState> emit) async {
    emit(const BandScanningState());
    await _scanSub?.cancel();

    // Dispatch each scan result as an internal event — never emit() from here.
    _scanSub = BandBleClient.scan().listen((r) {
      if (!isClosed) add(_ScanResultReceived(r));
    });
  }

  Future<void> _onStopScan(StopScan _, Emitter<BandMonitorState> emit) async {
    await _scanSub?.cancel();
    _scanSub = null;
    await BandBleClient.stopScan();
    emit(const BandIdleState());
  }

  // ── Context ───────────────────────────────────────────────────────────────

  void _onUpdateBandContext(
    UpdateBandContext event,
    Emitter<BandMonitorState> emit,
  ) {
    _patientId = event.patientId;
    _personalInfo = event.personalInfo;
    
    // If we're already connected, we could theoretically send SetPersonalInfo
    // command to the band here. For now, it will apply to the next connection
    // and the ingest loop automatically picks up the new _patientId.
  }

  // ── Connect ───────────────────────────────────────────────────────────────

  Future<void> _onConnect(
      ConnectToBand event, Emitter<BandMonitorState> emit) async {
    await _scanSub?.cancel();
    _scanSub = null;
    await BandBleClient.stopScan();

    emit(BandConnectingState(event.device.platformName));
    
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
    
    service.invoke('connectDevice', {
      'remote_id': event.device.remoteId.str,
      'device_id': _deviceId,
    });
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  Future<void> _onDisconnect(
      DisconnectBand _, Emitter<BandMonitorState> emit) async {
    FlutterBackgroundService().invoke('stopService');
    emit(const BandDisconnectedState());
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    await _bgSub?.cancel();
    await _scanSub?.cancel();
    return super.close();
  }
}
