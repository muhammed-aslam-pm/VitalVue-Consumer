/// A single vitals reading — either from polling (vitals_history) or from SSE.
///
/// Fields marked with `?` are only present in SSE `patient_vital_update`
/// events and will be null for data loaded via the REST endpoint.
class PatientVitalsSnapshot {
  const PatientVitalsSnapshot({
    required this.patientId,
    required this.deviceId,
    required this.heartRate,
    required this.spo2,
    required this.temp,
    required this.bpSystolic,
    required this.bpDiastolic,
    required this.hrvScore,
    required this.stressLevel,
    required this.movement,
    required this.sleepPattern,
    required this.batteryPercent,
    required this.isConnected,
    required this.isRemoved,
    required this.heartRateStatus,
    required this.spo2Status,
    required this.bpStatus,
    required this.temperatureStatus,
    // SSE-only extras
    this.news2Score,
    this.strokeRisk,
    this.afWarning,
    this.seizureRisk,
    this.createdAt,
  });

  final int patientId;
  final String deviceId;
  final int heartRate;
  final double spo2;
  final double temp;
  final int bpSystolic;
  final int bpDiastolic;
  final int hrvScore;
  final String stressLevel;
  final int movement;
  final String sleepPattern;
  final int batteryPercent;
  final bool isConnected;
  final bool isRemoved;
  final String heartRateStatus;
  final String spo2Status;
  final String bpStatus;
  final String temperatureStatus;

  // Present in SSE `patient_vital_update` vitals objects
  final int? news2Score;
  final String? strokeRisk;
  final String? afWarning;
  final String? seizureRisk;
  final String? createdAt;

  factory PatientVitalsSnapshot.fromJson(Map<String, dynamic> j) =>
      PatientVitalsSnapshot(
        patientId: j['patient_id'] as int? ?? 0,
        deviceId: j['device_id'] as String? ?? '',
        heartRate: j['heart_rate'] as int? ?? 0,
        spo2: (j['spo2'] as num?)?.toDouble() ?? 0.0,
        temp: (j['temp'] as num?)?.toDouble() ?? 0.0,
        bpSystolic: j['bp_systolic'] as int? ?? 0,
        bpDiastolic: j['bp_diastolic'] as int? ?? 0,
        hrvScore: j['hrv_score'] as int? ?? 0,
        stressLevel: j['stress_level'] as String? ?? 'N/A',
        movement: j['movement'] as int? ?? 0,
        sleepPattern: j['sleep_pattern'] as String? ?? 'N/A',
        batteryPercent: j['battery_percent'] as int? ?? 0,
        isConnected: j['is_connected'] as bool? ?? false,
        isRemoved: j['is_removed'] as bool? ?? false,
        heartRateStatus: j['heart_rate_status'] as String? ?? 'Stable',
        spo2Status: j['spo2_status'] as String? ?? 'Stable',
        bpStatus: j['bp_status'] as String? ?? 'Stable',
        temperatureStatus: j['temperature_status'] as String? ?? 'Stable',
        news2Score: j['news2_score'] as int?,
        strokeRisk: j['stroke_risk'] as String?,
        afWarning: j['af_warning'] as String?,
        seizureRisk: j['seizure_risk'] as String?,
        createdAt: j['created_at'] as String?,
      );

  /// Highest severity across all vital statuses.
  /// Returns 2 = Critical, 1 = Warning, 0 = Stable.
  int get overallSeverity {
    int severity = 0;
    for (final s in [heartRateStatus, spo2Status, bpStatus, temperatureStatus]) {
      if (s == 'Critical') return 2;
      if (s == 'Warning') severity = 1;
    }
    return severity;
  }

  String get overallStatusLabel {
    switch (overallSeverity) {
      case 2:
        return 'Critical';
      case 1:
        return 'Warning';
      default:
        return 'Stable';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// A patient entry from `GET /api/v1/patients/assigned`.
///
/// [liveVitals] is null initially and gets populated by SSE updates.
/// The [latestVitals] getter always prefers live data.
class AssignedPatient {
  const AssignedPatient({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.age,
    required this.gender,
    required this.bloodGroup,
    required this.roomNo,
    required this.assignedDoctor,
    this.assignedNurse,
    required this.phoneNumber,
    required this.altPhone,
    required this.news2Score,
    required this.afWarning,
    required this.isConnected,
    required this.isRemoved,
    required this.vitalsHistory,
    this.liveVitals,
  });

  final int id;
  final String userId;
  final String fullName;
  final int age;
  final String gender;
  final String bloodGroup;
  final String roomNo;
  final String assignedDoctor;
  final String? assignedNurse;
  final String phoneNumber;
  final String altPhone;
  final int news2Score;
  final String afWarning;
  final bool isConnected;
  final bool isRemoved;
  final List<PatientVitalsSnapshot> vitalsHistory;

  /// Most-recent vitals pushed by SSE; null until first SSE event.
  final PatientVitalsSnapshot? liveVitals;

  factory AssignedPatient.fromJson(Map<String, dynamic> j) {
    final rawHistory = j['vitals_history'] as List<dynamic>? ?? [];
    final history = rawHistory
        .map((e) => PatientVitalsSnapshot.fromJson(e as Map<String, dynamic>))
        .toList();
    return AssignedPatient(
      id: j['id'] as int,
      userId: j['user_id'] as String? ?? '',
      fullName: j['full_name'] as String? ?? '',
      age: j['age'] as int? ?? 0,
      gender: j['gender'] as String? ?? '',
      bloodGroup: j['blood_group'] as String? ?? '',
      roomNo: j['room_no'] as String? ?? '',
      assignedDoctor: j['assigned_doctor'] as String? ?? '',
      assignedNurse: j['assigned_nurse'] as String?,
      phoneNumber: j['phone_number'] as String? ?? '',
      altPhone: j['alt_phone'] as String? ?? '',
      news2Score: j['news2_score'] as int? ?? 0,
      afWarning: j['af_warning'] as String? ?? 'N/A',
      isConnected: j['is_connected'] as bool? ?? false,
      isRemoved: j['is_removed'] as bool? ?? false,
      vitalsHistory: history,
    );
  }

  /// Returns live SSE vitals if available, otherwise the last history entry.
  PatientVitalsSnapshot? get latestVitals =>
      liveVitals ?? (vitalsHistory.isEmpty ? null : vitalsHistory.last);

  /// Latest history entry where the device was connected.
  PatientVitalsSnapshot? get latestConnectedVitals {
    if (liveVitals != null) return liveVitals;
    for (final v in vitalsHistory.reversed) {
      if (v.isConnected) return v;
    }
    return null;
  }

  int get overallSeverity => latestVitals?.overallSeverity ?? 0;
  String get overallStatusLabel => latestVitals?.overallStatusLabel ?? 'Stable';

  /// Returns a copy with [liveVitals] updated (and optionally connection flags).
  AssignedPatient withLiveVitals(PatientVitalsSnapshot v) => AssignedPatient(
        id: id,
        userId: userId,
        fullName: fullName,
        age: age,
        gender: gender,
        bloodGroup: bloodGroup,
        roomNo: roomNo,
        assignedDoctor: assignedDoctor,
        assignedNurse: assignedNurse,
        phoneNumber: phoneNumber,
        altPhone: altPhone,
        news2Score: v.news2Score ?? news2Score,
        afWarning: v.afWarning ?? afWarning,
        isConnected: v.isConnected,
        isRemoved: v.isRemoved,
        vitalsHistory: vitalsHistory,
        liveVitals: v,
      );
}
