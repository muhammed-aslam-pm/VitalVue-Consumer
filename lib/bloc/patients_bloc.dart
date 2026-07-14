import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../cloud/assigned_patient.dart';
import '../cloud/patients_repository.dart';
import '../cloud/sse_events.dart';
import '../cloud/vitals_sse_service.dart';
import 'patients_event.dart';
import 'patients_state.dart';

// ── Private (file-scope) internal events ─────────────────────────────────────

class _PollDataReceived extends PatientsEvent {
  const _PollDataReceived(this.patients);
  final List<AssignedPatient> patients;
  @override
  List<Object?> get props => [patients];
}

class _PollErrorReceived extends PatientsEvent {
  const _PollErrorReceived(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

class _SseConnectionChanged extends PatientsEvent {
  const _SseConnectionChanged(this.connected);
  final bool connected;
  @override
  List<Object?> get props => [connected];
}

class _SseVitalReceived extends PatientsEvent {
  const _SseVitalReceived(this.update);
  final SseVitalUpdateEvent update;
  @override
  List<Object?> get props => [update.patientId, update.timestamp];
}

class _SseCriticalAlertReceived extends PatientsEvent {
  const _SseCriticalAlertReceived(this.alert);
  final SseCriticalAlertEvent alert;
  @override
  List<Object?> get props => [alert.alertId];
}

// ─────────────────────────────────────────────────────────────────────────────

class PatientsBloc extends Bloc<PatientsEvent, PatientsState> {
  PatientsBloc({
    required PatientsRepository repository,
    required VitalsSseService sseService,
  })  : _repo = repository,
        _sseService = sseService,
        super(const PatientsInitial()) {
    on<LoadPatients>(_onLoad);
    on<RefreshPatients>(_onRefresh);
    on<DismissAlert>(_onDismissAlert);
    on<StopPatients>(_onStop);
    on<_PollDataReceived>(_onPollData);
    on<_PollErrorReceived>(_onPollError);
    on<_SseConnectionChanged>(_onSseConnection);
    on<_SseVitalReceived>(_onSseVital);
    on<_SseCriticalAlertReceived>(_onSseAlert);
  }

  final PatientsRepository _repo;
  final VitalsSseService _sseService;
  StreamSubscription<List<AssignedPatient>>? _pollSub;
  StreamSubscription<SseEvent>? _sseSub;

  // ── Public handlers ───────────────────────────────────────────────────────

  Future<void> _onLoad(LoadPatients event, Emitter<PatientsState> emit) async {
    print('PatientsBloc: _onLoad started');
    if (state is PatientsLoaded) return; // already running
    emit(const PatientsLoading());
    // Initial fast load from REST
    try {
      print('PatientsBloc: Fetching assigned patients...');
      final patients = await _repo.fetchAssigned();
      print('PatientsBloc: Fetched ${patients.length} patients');
      emit(PatientsLoaded(patients));
    } catch (e) {
      print('PatientsBloc: Fetch error: $e');
      emit(PatientsError(e.toString()));
      return;
    }
    print('PatientsBloc: Starting SSE and polling...');
    _startSse();
    _startFallbackPoll(); // 2-minute sync for newly assigned patients
  }

  Future<void> _onRefresh(
      RefreshPatients event, Emitter<PatientsState> emit) async {
    if (state is PatientsLoaded) {
      final cur = state as PatientsLoaded;
      emit(cur.copyWith(isRefreshing: true));
    } else {
      emit(const PatientsLoading());
    }

    try {
      final patients = await _repo.fetchAssigned();
      if (state is PatientsLoaded) {
        // Merge liveVitals back so SSE data isn't lost on refresh
        final cur = state as PatientsLoaded;
        final liveMap = {for (final p in cur.patients) p.id: p.liveVitals};
        final merged = patients.map((p) {
          final live = liveMap[p.id];
          return live != null ? p.withLiveVitals(live) : p;
        }).toList();
        emit(cur.copyWith(patients: merged, isRefreshing: false));
      } else {
        emit(PatientsLoaded(patients));
      }
    } catch (_) {
      if (state is PatientsLoaded) {
        final cur = state as PatientsLoaded;
        emit(cur.copyWith(isRefreshing: false));
      }
    }
  }

  void _onDismissAlert(DismissAlert event, Emitter<PatientsState> emit) {
    if (state is! PatientsLoaded) return;
    final cur = state as PatientsLoaded;
    final alerts =
        cur.pendingAlerts.where((a) => a.alertId != event.alertId).toList();
    emit(cur.copyWith(pendingAlerts: alerts));
  }

  void _onStop(StopPatients event, Emitter<PatientsState> emit) {
    _pollSub?.cancel();
    _pollSub = null;
    _sseSub?.cancel();
    _sseSub = null;
    emit(const PatientsInitial());
  }

  // ── Poll handlers ─────────────────────────────────────────────────────────

  void _onPollData(_PollDataReceived event, Emitter<PatientsState> emit) {
    if (state is! PatientsLoaded) {
      emit(PatientsLoaded(event.patients));
      return;
    }
    final cur = state as PatientsLoaded;
    // Keep liveVitals from SSE so a polling sync doesn't clobber live data
    final liveMap = {for (final p in cur.patients) p.id: p.liveVitals};
    final merged = event.patients.map((p) {
      final live = liveMap[p.id];
      return live != null ? p.withLiveVitals(live) : p;
    }).toList();
    emit(cur.copyWith(patients: merged));
  }

  void _onPollError(_PollErrorReceived event, Emitter<PatientsState> emit) {
    // Keep current data; polling errors are non-fatal when SSE is running
    if (state is PatientsLoaded) return;
    emit(PatientsError(event.message));
  }

  // ── SSE handlers ──────────────────────────────────────────────────────────

  void _onSseConnection(
      _SseConnectionChanged event, Emitter<PatientsState> emit) {
    if (state is! PatientsLoaded) return;
    emit((state as PatientsLoaded).copyWith(sseConnected: event.connected));
  }

  void _onSseVital(_SseVitalReceived event, Emitter<PatientsState> emit) {
    if (state is! PatientsLoaded) return;
    final cur = state as PatientsLoaded;
    final updated = cur.patients.map((p) {
      if (p.id != event.update.patientId) return p;
      return p.withLiveVitals(event.update.vitals);
    }).toList();
    emit(cur.copyWith(patients: updated));
  }

  void _onSseAlert(
      _SseCriticalAlertReceived event, Emitter<PatientsState> emit) {
    if (state is! PatientsLoaded) return;
    final cur = state as PatientsLoaded;
    // Deduplicate by alertId
    final already = cur.pendingAlerts.any((a) => a.alertId == event.alert.alertId);
    if (already) return;
    emit(cur.copyWith(pendingAlerts: [...cur.pendingAlerts, event.alert]));
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _startSse() {
    _sseSub?.cancel();
    _sseSub = _sseService.connect().listen(
      (ev) {
        if (isClosed) return;
        if (ev is SseConnectedEvent) {
          add(const _SseConnectionChanged(true));
        } else if (ev is SseDisconnectedEvent) {
          add(const _SseConnectionChanged(false));
        } else if (ev is SseVitalUpdateEvent) {
          add(_SseVitalReceived(ev));
        } else if (ev is SseCriticalAlertEvent) {
          add(_SseCriticalAlertReceived(ev));
        }
      },
    );
  }

  void _startFallbackPoll() {
    _pollSub?.cancel();
    // Poll every 2 minutes as a full-list sync safety net
    _pollSub = _repo
        .pollingStream(interval: const Duration(minutes: 2))
        .skip(1) // first fetch already done
        .listen(
          (patients) {
            if (!isClosed) add(_PollDataReceived(patients));
          },
          onError: (e) {
            if (!isClosed) add(_PollErrorReceived(e.toString()));
          },
        );
  }

  @override
  Future<void> close() async {
    await _sseSub?.cancel();
    await _pollSub?.cancel();
    return super.close();
  }
}
