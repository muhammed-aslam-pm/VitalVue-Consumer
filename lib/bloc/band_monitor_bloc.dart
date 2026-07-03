import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
  }

  final BandVitalsApi _vitalsApi;
  final int _patientId;
  final String _deviceId;
  final PersonalInfo _personalInfo;

  BandSessionService? _session;
  StreamSubscription<BandState>? _stateSub;
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

  // ── Connect ───────────────────────────────────────────────────────────────

  Future<void> _onConnect(
      ConnectToBand event, Emitter<BandMonitorState> emit) async {
    await _scanSub?.cancel();
    _scanSub = null;
    await BandBleClient.stopScan();

    emit(BandConnectingState(event.device.platformName));
    await _teardownSession();

    _session = BandSessionService(
      patientId: _patientId,
      deviceId: _deviceId,
      personalInfo: _personalInfo,
      onIngest: (s) => _vitalsApi.ingest(
        patientId: _patientId,
        deviceId: _deviceId,
        hr: s.hr,
        spo2: s.spo2,
        tempC: s.tempC,
        bpSys: s.systolic ?? 0,
        bpDia: s.diastolic ?? 0,
        battery: s.battery,
        isRemoved: s.isRemoved,
      ),
    );

    final connected = await _session!.connect(event.device);

    if (!connected) {
      await _teardownSession();
      emit(const BandDisconnectedState(reason: 'Connection failed'));
      return;
    }

    // ✅ Correct pattern: subscribe → add() internal events.
    // The _onConnect handler returns immediately after this; ongoing state
    // changes flow through _BandStateUpdated events handled by their own handler.
    _stateSub = _session!.stateStream.listen((s) {
      if (!isClosed) add(_BandStateUpdated(s));
    });

    // Emit the initial connected snapshot synchronously — still inside handler.
    emit(BandConnectedState(_session!.currentState));
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  Future<void> _onDisconnect(
      DisconnectBand _, Emitter<BandMonitorState> emit) async {
    await _teardownSession();
    emit(const BandDisconnectedState());
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  Future<void> _teardownSession() async {
    await _stateSub?.cancel();
    _stateSub = null;
    await _session?.disconnect();
    _session?.dispose();
    _session = null;
  }

  @override
  Future<void> close() async {
    await _teardownSession();
    await _scanSub?.cancel();
    return super.close();
  }
}
