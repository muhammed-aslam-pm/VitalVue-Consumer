import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/band_ble_client.dart';
import '../protocol/jstyle_codec.dart';
import '../db/vitals_database.dart';
import 'band_timing_logger.dart';

// ── Timer constants — match Python band_session.py exactly ──────────────────
const _watchdogTimeoutS = 90; // HR=0 for >90s → band removed
const _spo2KickIntervalS = 120; // SpO2 spot-check every 120s
const _spo2KickDurationS = 45; // SpO2 PPG window
const _spo2SuppressWindowS = _spo2KickDurationS + 30; // suppress watchdog during PPG
const _bpKickIntervalS = 300; // BP/HRV kick every 300s
const _ingestIntervalS = 60; // cloud ingest every 60s
const _loopTickS = 2; // main loop tick

// ── Band state value object ───────────────────────────────────────────────────

enum BleConnectionStatus { idle, scanning, connecting, connected, disconnected }

class BandState {
  final BleConnectionStatus connectionStatus;
  final int hr;
  final int spo2;
  final double tempC;
  final int? systolic;
  final int? diastolic;
  final int? hrv;
  final int? stress;
  final int steps;
  final double calories;
  final double distanceKm;
  final int battery;
  final bool isRemoved;
  final String? errorMessage;

  const BandState({
    this.connectionStatus = BleConnectionStatus.idle,
    this.hr = 0,
    this.spo2 = 0,
    this.tempC = 0.0,
    this.systolic,
    this.diastolic,
    this.hrv,
    this.stress,
    this.steps = 0,
    this.calories = 0.0,
    this.distanceKm = 0.0,
    this.battery = -1,
    this.isRemoved = false,
    this.errorMessage,
  });

  BandState copyWith({
    BleConnectionStatus? connectionStatus,
    int? hr,
    int? spo2,
    double? tempC,
    int? systolic,
    int? diastolic,
    int? hrv,
    int? stress,
    int? steps,
    double? calories,
    double? distanceKm,
    int? battery,
    bool? isRemoved,
    String? errorMessage,
    bool clearError = false,
    bool clearBp = false,
  }) {
    return BandState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      hr: hr ?? this.hr,
      spo2: spo2 ?? this.spo2,
      tempC: tempC ?? this.tempC,
      systolic: clearBp ? null : (systolic ?? this.systolic),
      diastolic: clearBp ? null : (diastolic ?? this.diastolic),
      hrv: hrv ?? this.hrv,
      stress: stress ?? this.stress,
      steps: steps ?? this.steps,
      calories: calories ?? this.calories,
      distanceKm: distanceKm ?? this.distanceKm,
      battery: battery ?? this.battery,
      isRemoved: isRemoved ?? this.isRemoved,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ── Session service — state machine ──────────────────────────────────────────

/// Dart translation of Python band_session.py.
///
/// Owns the BLE client, codec, all timers, and exposes a [stateStream]
/// that the BLoC subscribes to for UI updates.
class BandSessionService {
  BandSessionService({
    required this.patientId,
    required this.deviceId,
    required PersonalInfo personalInfo,
    required this.onIngest,
  }) : _personalInfo = personalInfo;

  final int patientId;
  final String deviceId;
  final PersonalInfo _personalInfo;

  /// Called every [_ingestIntervalS] seconds with the current snapshot.
  final Future<void> Function(BandState state) onIngest;

  final _codec = JStyleCodec();
  final _ble = BandBleClient();

  // Internal mutable state.
  BandState _state = const BandState();

  // State stream (broadcast so BLoC can listen).
  final _controller = StreamController<BandState>.broadcast();
  Stream<BandState> get stateStream => _controller.stream;
  BandState get currentState => _state;

  // Timer handles.
  Timer? _mainLoopTimer;
  Timer? _ingestTimer;
  Timer? _delayedBpTimer;

  Completer<void>? _historyStepsCompleter;
  Completer<void>? _historyHrCompleter;

  // Timestamp tracking.
  DateTime _lastValidHrTime = DateTime.now();
  DateTime _lastSpo2KickTime = DateTime(2000);
  DateTime _lastKickTime = DateTime(2000);
  DateTime _lastBpKickTime = DateTime(2000);

  // Staleness tracking to detect phantom pulses (band off-wrist but reporting steady HR)
  final List<int> _hrHistory = [];

  StreamSubscription<Uint8List>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  
  BluetoothDevice? _device;
  bool _isAutoReconnecting = false;

  // ── Timing instrumentation ──────────────────────────────────────────────────
  DateTime? _connectTime;
  DateTime? _lastVitalsTime;
  bool _firstHr = true;
  bool _firstSpo2 = true;
  bool _firstTemp = true;
  bool _firstBp = true;
  bool _firstBattery = true;
  late final BandTimingLogger _timingLogger;
  // ── End timing ──────────────────────────────────────────────────────────────

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<bool> connect(BluetoothDevice device) async {
    _device = device;
    _isAutoReconnecting = false;
    _emit(_state.copyWith(connectionStatus: BleConnectionStatus.connecting));

    final ok = await _ble.connect(device);
    if (!ok) {
      _emit(_state.copyWith(
        connectionStatus: BleConnectionStatus.disconnected,
        errorMessage: 'Connection failed',
      ));
      return false;
    }

    _connectTime = DateTime.now();
    _firstHr = true; _firstSpo2 = true; _firstTemp = true;
    _firstBp = true; _firstBattery = true; _lastVitalsTime = null;
    _timingLogger = BandTimingLogger(deviceId: deviceId);
    await _timingLogger.open();
    _timingLogger.log('connected', sinceConnectMs: 0, intervalMs: null);
    debugPrint('[$deviceId] ⏱ Connected at $_connectTime');

    _emit(_state.copyWith(
      connectionStatus: BleConnectionStatus.connected,
      clearError: true,
    ));

    // Watch for unexpected disconnects.
    _connStateSub = _ble.connectionStateStream.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        _handleDisconnect();
      }
    });

    // Subscribe to GATT notifications.
    _notifySub = _ble.notifyStream.listen(_onNotify);

    // 1.0s stabilisation delay before init sequence.
    await Future.delayed(const Duration(seconds: 1));
    await _initSequence();

    // Start the main loop and ingest loop.
    _lastKickTime = DateTime.now();
    _lastBpKickTime = DateTime.now();
    _lastValidHrTime = DateTime.now();

    _mainLoopTimer = Timer.periodic(
      const Duration(seconds: _loopTickS),
      (_) => _tick(),
    );

    _ingestTimer = Timer.periodic(
      const Duration(seconds: _ingestIntervalS),
      (_) => _runIngest(),
    );

    return true;
  }

  Future<void> disconnect() async {
    _isAutoReconnecting = false;
    _device = null;
    _cancelTimers();
    await _notifySub?.cancel();
    await _connStateSub?.cancel();
    await _ble.disconnect();
    _emit(_state.copyWith(connectionStatus: BleConnectionStatus.disconnected));
    await _runIngest(); // Immediately push disconnected status to cloud and wait for it
    await _timingLogger.close();
  }

  void dispose() {
    _cancelTimers();
    _notifySub?.cancel();
    _connStateSub?.cancel();
    _ble.dispose();
    _controller.close();
  }

  // ── Init sequence — matches Python _init_sequence() ───────────────────────

  Future<void> _initSequence() async {
    // Note: Do NOT use setMeasurement or setAutoMeasurement here, as forcefully turning
    // the LED on overrides the band's capacitive/reflective off-wrist detection, 
    // causing it to hallucinate phantom pulses (e.g. HR=73) when placed on a table.
    
    await _write('RealTimeStep', _codec.realTimeStep(enable: true, tempEnable: true));
    await _write('SetDeviceTime', _codec.setDeviceTime());
    await _write('SetPersonalInfo', _codec.setPersonalInfo(_personalInfo));
    await _write('GetBattery', _codec.getBattery());
    await Future.delayed(const Duration(milliseconds: 500));

    /*
    // Fetch History Data
    try {
      debugPrint('[$deviceId] Fetching Steps History...');
      _historyStepsCompleter = Completer<void>();
      await _write('GetHistorySteps', _codec.getHistorySteps());
      await _historyStepsCompleter!.future.timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[$deviceId] Steps history sync timeout/error: $e');
    }

    try {
      debugPrint('[$deviceId] Fetching HR History...');
      _historyHrCompleter = Completer<void>();
      await _write('GetHistoryHR', _codec.getHistoryHeartRate());
      await _historyHrCompleter!.future.timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[$deviceId] HR history sync timeout/error: $e');
    }
    */
  }

  // ── Main loop tick — matches Python while self.ble.connected ──────────────

  void _tick() {
    if (!_ble.isConnected) return;

    final now = DateTime.now();

    final isProcessingSpo2 =
        now.difference(_lastSpo2KickTime).inSeconds < _spo2SuppressWindowS;

    // ── Off-wrist watchdog ────────────────────────────────────────────────
    if (!isProcessingSpo2) {
      final secondsSinceValidHr = now.difference(_lastValidHrTime).inSeconds;

      if (secondsSinceValidHr > _watchdogTimeoutS) {
        if (!_state.isRemoved || _state.hr > 0) {
          debugPrint('[$deviceId] WATCHDOG: HR flatlined >$_watchdogTimeoutS s. Band removed.');
          _emit(_state.copyWith(isRemoved: true, hr: 0, spo2: 0, tempC: 0.0));
        }
      }

      // Stream stall recovery (HR dead for >120s): re-kick HR streaming.
      if (secondsSinceValidHr > 120) {
        debugPrint('[$deviceId] Stalled stream. Issuing restart handshake.');
        _write('Recover_RealTime', _codec.realTimeStep(enable: true, tempEnable: true));
        _lastValidHrTime = now; // reset to prevent spam
      }
    }

    // ── SpO2 restore after PPG window ends ─────────────────────────────────
    final spo2Elapsed = now.difference(_lastSpo2KickTime).inSeconds;
    if (_lastSpo2KickTime.year > 2000 &&
        spo2Elapsed >= _spo2KickDurationS + 2 &&
        spo2Elapsed < _spo2KickDurationS + 4) {
      debugPrint('[$deviceId] SpO2 cycle finished. Restoring streaming mode.');
      _write('Restore_Stream', _codec.realTimeStep(enable: true, tempEnable: true));
      _write('Kickstart_HR', _codec.setMeasurement(measHr, 3600, open: true));
      _lastValidHrTime = now;
    }

    // ── SpO2 and BP kick scheduling ────────────────────────────────────────
    if (!_state.isRemoved) {
      final triggerSpo2 =
          now.difference(_lastKickTime).inSeconds >= _spo2KickIntervalS;
      final triggerBp =
          now.difference(_lastBpKickTime).inSeconds >= _bpKickIntervalS;

      // Collision guard: if both fire at once, delay BP by 5 s.
      if (triggerSpo2 && triggerBp) {
        debugPrint('[$deviceId] Collision detected. Slotting BP 5s into future.');
        _lastSpo2KickTime = now;
        _lastKickTime = now;
        _write('SpO2_Kick',
            _codec.setMeasurement(measSpo2, _spo2KickDurationS, open: true));
        _delayedBpTimer?.cancel();
        _delayedBpTimer = Timer(const Duration(seconds: 5), () {
          _write('BP_HRV_Kick', _codec.getBpHrvData());
        });
        _lastBpKickTime = now;
      } else {
        if (triggerSpo2) {
          _lastSpo2KickTime = now;
          _lastKickTime = now;
          _write('SpO2_Kick',
              _codec.setMeasurement(measSpo2, _spo2KickDurationS, open: true));
        }
        if (triggerBp) {
          _lastBpKickTime = now;
          _write('BP_HRV_Kick', _codec.getBpHrvData());
        }
      }
    }
  }

  // ── Notification handler — matches Python _on_notify() ────────────────────

  void _onNotify(Uint8List data) {
    final event = _codec.parse(data);
    if (event == null) return;

    switch (event) {
      case HistoryDataEvent(:final records, :final isEnd, :final cmd):
        _ingestHistoryRecords(records);
        if (isEnd) {
          if (cmd == cmdGetDetailData && _historyStepsCompleter?.isCompleted == false) {
            _historyStepsCompleter!.complete();
          } else if (cmd == cmdGetHeartData && _historyHrCompleter?.isCompleted == false) {
            _historyHrCompleter!.complete();
          }
        }
        break;
        
      case RealtimeEvent(:final data):
        var next = _state;
        if (data.hr > 0) {
          _hrHistory.add(data.hr);
          if (_hrHistory.length > 90) {
            _hrHistory.removeAt(0);
          }

          bool isStale = false;
          if (_hrHistory.length >= 90) {
            final minHr = _hrHistory.reduce(math.min);
            final maxHr = _hrHistory.reduce(math.max);
            // If the HR hasn't varied by more than 2 bpm over 90 seconds, it's a phantom pulse
            if (maxHr - minHr <= 2) {
              isStale = true;
            }
          }

          if (isStale) {
            next = next.copyWith(hr: 0, spo2: 0, tempC: 0.0, isRemoved: true, clearError: true);
            // DO NOT update _lastValidHrTime, so watchdog also trips if needed
          } else {
            next = next.copyWith(hr: data.hr, isRemoved: false, clearError: true);
            _lastValidHrTime = DateTime.now();
          }
        } else {
          // data.hr == 0
          _hrHistory.clear(); // Reset history if we get a true 0 reading
        }
        
        if (data.spo2 > 0) next = next.copyWith(spo2: data.spo2);
        if (data.tempC > 0) next = next.copyWith(tempC: data.tempC);
        
        // Update activity metrics (steps, calories, distance)
        next = next.copyWith(
          steps: data.steps,
          calories: data.calories,
          distanceKm: data.distanceKm,
        );

        _emit(next);

        // ── Timing logs ────────────────────────────────────────────────────
        final now = DateTime.now();
        final sinceConnect = _connectTime != null
            ? now.difference(_connectTime!).inMilliseconds
            : -1;

        if (_firstHr && next.hr > 0) {
          _firstHr = false;
          debugPrint('[$deviceId] ⏱ First HR (${next.hr} bpm) received ${sinceConnect}ms after connect');
          _timingLogger.log('first_hr', sinceConnectMs: sinceConnect, intervalMs: null, hr: next.hr, tempC: next.tempC);
        }
        if (_firstSpo2 && next.spo2 > 0) {
          _firstSpo2 = false;
          debugPrint('[$deviceId] ⏱ First SpO2 (${next.spo2}%) received ${sinceConnect}ms after connect');
          _timingLogger.log('first_spo2', sinceConnectMs: sinceConnect, intervalMs: null, spo2: next.spo2);
        }
        if (_firstTemp && next.tempC > 0) {
          _firstTemp = false;
          debugPrint('[$deviceId] ⏱ First Temp (${next.tempC}°C) received ${sinceConnect}ms after connect');
          _timingLogger.log('first_temp', sinceConnectMs: sinceConnect, intervalMs: null, tempC: next.tempC);
        }

        if (_lastVitalsTime != null) {
          final intervalMs = now.difference(_lastVitalsTime!).inMilliseconds;
          debugPrint('[$deviceId] ⏱ VITALS interval: ${intervalMs}ms  '
              'HR=${next.hr} SpO2=${next.spo2} Temp=${next.tempC}°C');
          _timingLogger.log('vitals_interval',
              sinceConnectMs: sinceConnect,
              intervalMs: intervalMs,
              hr: next.hr,
              spo2: next.spo2,
              tempC: next.tempC);
        } else {
          debugPrint('[$deviceId] ⏱ First VITALS update at ${sinceConnect}ms after connect');
          _timingLogger.log('first_vitals', sinceConnectMs: sinceConnect, intervalMs: null, hr: next.hr, spo2: next.spo2, tempC: next.tempC);
        }
        _lastVitalsTime = now;
        // ── End timing logs ────────────────────────────────────────────────

        // Mirror Python: log.info("[%s] HR=%d SpO2=%d temp=%.1f | Removed: %s")
        debugPrint('[$deviceId] VITALS  HR=${next.hr} bpm  '
            'SpO2=${next.spo2}%  Temp=${next.tempC}°C  '
            'Steps=${next.steps}  Cal=${next.calories}  Dist=${next.distanceKm}km  '
            '| removed=${next.isRemoved}');

      case BpResultEvent(:final systolic, :final diastolic, :final hrv, :final stress):
        if (systolic > 0 && diastolic > 0) {
          // BP receipt also proves band is on wrist — refresh watchdog.
          _lastValidHrTime = DateTime.now();
          _emit(_state.copyWith(
            systolic: systolic,
            diastolic: diastolic,
            hrv: hrv,
            stress: stress,
            isRemoved: false,
            clearError: true,
          ));
          if (_firstBp) {
            _firstBp = false;
            final sinceConnect = _connectTime != null
                ? DateTime.now().difference(_connectTime!).inMilliseconds
                : -1;
            debugPrint('[$deviceId] ⏱ First BP ($systolic/$diastolic mmHg) received ${sinceConnect}ms after connect');
            _timingLogger.log('first_bp', sinceConnectMs: sinceConnect, intervalMs: null,
                note: '${systolic}/${diastolic}mmHg hrv:$hrv stress:$stress');
          }
          debugPrint('[$deviceId] BP received: $systolic/$diastolic mmHg, HRV: $hrv, Stress: $stress');
        }

      case BpNoDataEvent():
        // Device responded (band is on-wrist) — refresh watchdog.
        _lastValidHrTime = DateTime.now();

      case BatteryEvent(:final percent):
        _emit(_state.copyWith(battery: percent));
        if (_firstBattery) {
          _firstBattery = false;
          final sinceConnect = _connectTime != null
              ? DateTime.now().difference(_connectTime!).inMilliseconds
              : -1;
          debugPrint('[$deviceId] ⏱ First Battery ($percent%) received ${sinceConnect}ms after connect');
          _timingLogger.log('first_battery', sinceConnectMs: sinceConnect, intervalMs: null, note: '${percent}%');
        }
        debugPrint('[$deviceId] BATTERY  $percent%');

      case UnknownEvent(:final dataType, :final raw):
        debugPrint('[$deviceId] Unhandled event type=0x${dataType.toRadixString(16)} raw=$raw');
    }
  }

  Future<void> _ingestHistoryRecords(List<HistoryRecord> records) async {
    if (records.isEmpty) return;
    
    final oneDayAgo = DateTime.now().subtract(const Duration(hours: 24));
    final oneHourFromNow = DateTime.now().add(const Duration(hours: 1));
    
    for (final r in records) {
      // Ignore records older than 24 hours or in the future (due to band clock errors)
      if (r.timestamp.isBefore(oneDayAgo) || r.timestamp.isAfter(oneHourFromNow)) continue;

      final map = <String, dynamic>{
        'timestamp': r.timestamp.millisecondsSinceEpoch,
        'patient_id': patientId,
        'device_id': deviceId,
        'isRemoved': 0,
        'isIngested': 0,
      };
      if (r is HistoryHr) {
        map['hr'] = r.hr;
      } else if (r is HistorySteps) {
        map['steps'] = r.steps;
        map['calories'] = r.calories;
        map['distanceKm'] = r.distanceKm;
      }
      await VitalsDatabase.instance.upsertVital(map);
    }
    
    // Clear any older history automatically
    await VitalsDatabase.instance.deleteOldVitals();
  }

  // ── Database Ingest Loop — matches Python _ingest_to_cloud() ───────────────────────────────────────────────────────────

  Future<void> _runIngest() async {
    try {
      await onIngest(_state);
    } catch (e) {
      debugPrint('[$deviceId] Ingest error: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _write(String name, Uint8List data) async {
    try {
      await _ble.write(data);
      debugPrint('[$deviceId] → $name');
    } catch (e) {
      debugPrint('[$deviceId] write failed [$name]: $e');
      _emit(_state.copyWith(errorMessage: 'Write failed: $name'));
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }

  void _emit(BandState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  void _handleDisconnect() {
    _cancelTimers();
    _emit(_state.copyWith(connectionStatus: BleConnectionStatus.disconnected));
    _runIngest(); // Fire-and-forget for unexpected disconnects
    
    if (_device != null && !_isAutoReconnecting) {
      _startAutoReconnect();
    }
  }

  void _startAutoReconnect() async {
    _isAutoReconnecting = true;
    while (_isAutoReconnecting && _device != null) {
      debugPrint('[$deviceId] Attempting auto-reconnect...');
      _emit(_state.copyWith(connectionStatus: BleConnectionStatus.connecting));
      
      final connected = await _ble.connect(_device!);
      if (connected) {
        debugPrint('[$deviceId] Auto-reconnect successful!');
        
        _emit(_state.copyWith(
          connectionStatus: BleConnectionStatus.connected,
          clearError: true,
        ));
        
        // Subscribe to GATT notifications again
        await _notifySub?.cancel();
        _notifySub = _ble.notifyStream.listen(_onNotify);
        
        await Future.delayed(const Duration(seconds: 1));
        await _initSequence();
        
        _lastKickTime = DateTime.now();
        _lastBpKickTime = DateTime.now();
        _lastValidHrTime = DateTime.now();
        
        _mainLoopTimer = Timer.periodic(
          const Duration(seconds: _loopTickS),
          (_) => _tick(),
        );
        _ingestTimer = Timer.periodic(
          const Duration(seconds: _ingestIntervalS),
          (_) => _runIngest(),
        );
        _isAutoReconnecting = false;
        return;
      }
      
      debugPrint('[$deviceId] Auto-reconnect failed. Retrying in 5 seconds...');
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  void _cancelTimers() {
    _mainLoopTimer?.cancel();
    _ingestTimer?.cancel();
    _delayedBpTimer?.cancel();
    _mainLoopTimer = null;
    _ingestTimer = null;
    _delayedBpTimer = null;
  }
}
