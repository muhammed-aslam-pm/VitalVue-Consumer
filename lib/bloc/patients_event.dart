import 'package:equatable/equatable.dart';

abstract class PatientsEvent extends Equatable {
  const PatientsEvent();
  @override
  List<Object?> get props => [];
}

/// Load patients list (first time) + start SSE stream.
class LoadPatients extends PatientsEvent {
  const LoadPatients();
}

/// Pull-to-refresh: re-fetch REST list while SSE keeps running.
class RefreshPatients extends PatientsEvent {
  const RefreshPatients();
}

/// Dismiss an alert by its [alertId] after the user acknowledges it.
class DismissAlert extends PatientsEvent {
  const DismissAlert(this.alertId);
  final int alertId;
  @override
  List<Object?> get props => [alertId];
}

/// Stop polling and clear data when logging out.
class StopPatients extends PatientsEvent {
  const StopPatients();
}
