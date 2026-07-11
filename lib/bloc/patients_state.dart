import 'package:equatable/equatable.dart';

import '../cloud/assigned_patient.dart';
import '../cloud/sse_events.dart';

abstract class PatientsState extends Equatable {
  const PatientsState();
  @override
  List<Object?> get props => [];
}

class PatientsInitial extends PatientsState {
  const PatientsInitial();
}

class PatientsLoading extends PatientsState {
  const PatientsLoading();
}

class PatientsLoaded extends PatientsState {
  const PatientsLoaded(
    this.patients, {
    this.isRefreshing = false,
    this.sseConnected = false,
    this.pendingAlerts = const [],
  });

  final List<AssignedPatient> patients;
  final bool isRefreshing;
  final bool sseConnected;

  /// Queue of critical alerts waiting to be shown to the user.
  final List<SseCriticalAlertEvent> pendingAlerts;

  PatientsLoaded copyWith({
    List<AssignedPatient>? patients,
    bool? isRefreshing,
    bool? sseConnected,
    List<SseCriticalAlertEvent>? pendingAlerts,
  }) =>
      PatientsLoaded(
        patients ?? this.patients,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        sseConnected: sseConnected ?? this.sseConnected,
        pendingAlerts: pendingAlerts ?? this.pendingAlerts,
      );

  @override
  List<Object?> get props =>
      [patients, isRefreshing, sseConnected, pendingAlerts.length];
}

class PatientsError extends PatientsState {
  const PatientsError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}
