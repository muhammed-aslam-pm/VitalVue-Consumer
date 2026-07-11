import 'assigned_patient.dart';

/// Base class for all events received from the SSE stream.
abstract class SseEvent {
  const SseEvent();
}

/// Fired once the SSE HTTP connection is established.
class SseConnectedEvent extends SseEvent {
  const SseConnectedEvent();
}

/// Fired when the SSE connection drops (before the next reconnect attempt).
class SseDisconnectedEvent extends SseEvent {
  const SseDisconnectedEvent(this.reason);
  final String reason;
}

/// `event: patient_vital_update` — carries fresh vitals for one patient.
class SseVitalUpdateEvent extends SseEvent {
  const SseVitalUpdateEvent({
    required this.patientId,
    required this.patientStatus,
    required this.vitals,
    required this.wardName,
    required this.roomNumber,
    required this.timestamp,
  });

  final int patientId;
  final String patientStatus; // "Stable" | "Warning" | "Critical"
  final PatientVitalsSnapshot vitals;
  final String wardName;
  final String roomNumber;
  final String timestamp;

  factory SseVitalUpdateEvent.fromJson(Map<String, dynamic> json) =>
      SseVitalUpdateEvent(
        patientId: json['patient_id'] as int,
        patientStatus: json['patient_status'] as String? ?? 'Stable',
        vitals: PatientVitalsSnapshot.fromJson(
            json['vitals'] as Map<String, dynamic>),
        wardName: json['ward_name'] as String? ?? '',
        roomNumber: json['room_number'] as String? ?? '',
        timestamp: json['timestamp'] as String? ?? '',
      );
}

/// `event: critical_alert` — a threshold breach that requires staff attention.
class SseCriticalAlertEvent extends SseEvent {
  const SseCriticalAlertEvent({
    required this.patientId,
    required this.wardName,
    required this.roomNumber,
    required this.phoneNumber,
    required this.severity,
    required this.vitalType,
    required this.triggeredValue,
    required this.alertId,
  });

  final int patientId;
  final String wardName;
  final String roomNumber;
  final String phoneNumber;
  final String severity; // "critical" | "warning"
  final String vitalType;
  final String triggeredValue;
  final int alertId;

  factory SseCriticalAlertEvent.fromJson(Map<String, dynamic> json) =>
      SseCriticalAlertEvent(
        patientId: json['patient_id'] as int,
        wardName: json['ward_name'] as String? ?? '',
        roomNumber: json['room_number'] as String? ?? '',
        phoneNumber: json['phone_number'] as String? ?? '',
        severity: json['severity'] as String? ?? 'critical',
        vitalType: json['vital_type'] as String? ?? '',
        triggeredValue: json['triggered_value'] as String? ?? '',
        alertId: (json['alert_id'] ?? json['id'] ?? 0) as int,
      );
}
