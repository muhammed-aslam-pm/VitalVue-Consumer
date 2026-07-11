/// Unified profile model for all user roles (patient, doctor, nurse, etc.)
class UserProfile {
  final int id;
  final String userId;
  final String fullName;
  final String role;
  final int? organizationId;
  final String? phoneNumber;

  // ── Patient-only fields ───────────────────────────────────────────────────
  final int? age;
  final String? gender;
  final int? height;
  final int? weight;
  final String? bloodGroup;
  final String? altPhone;
  final String? deviceId;
  final String? nurseId;
  final String? doctorName;
  final String? roomNumber;
  final String? wardName;
  final String? departmentName;

  // ── Doctor / Staff-only fields ────────────────────────────────────────────
  final String? specialization;
  final bool? isOnCall;

  UserProfile({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.role,
    this.organizationId,
    this.phoneNumber,
    // patient fields
    this.age,
    this.gender,
    this.height,
    this.weight,
    this.bloodGroup,
    this.altPhone,
    this.deviceId,
    this.nurseId,
    this.doctorName,
    this.roomNumber,
    this.wardName,
    this.departmentName,
    // staff fields
    this.specialization,
    this.isOnCall,
  });

  /// Whether this user is a patient (band connection features should be shown).
  bool get isPatient => role == 'patient';

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as int,
      userId: json['user_id'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      role: json['role'] as String? ?? 'patient',
      organizationId: json['organization_id'] as int?,
      phoneNumber: json['phone_number'] as String?,
      // patient fields — all optional
      age: (json['age'] as num?)?.toInt(),
      gender: json['gender'] as String?,
      height: (json['height'] as num?)?.toInt(),
      weight: (json['weight'] as num?)?.toInt(),
      bloodGroup: json['blood_group'] as String?,
      altPhone: json['alt_phone'] as String?,
      deviceId: json['device_id'] as String?,
      nurseId: json['nurse_id'] as String?,
      doctorName: json['doctor_name'] as String?,
      roomNumber: json['room_number'] as String?,
      wardName: json['ward_name'] as String?,
      departmentName: json['department_name'] as String?,
      // staff fields
      specialization: json['specialization'] as String?,
      isOnCall: json['is_on_call'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'full_name': fullName,
      'role': role,
      'organization_id': organizationId,
      'phone_number': phoneNumber,
      'age': age,
      'gender': gender,
      'height': height,
      'weight': weight,
      'blood_group': bloodGroup,
      'alt_phone': altPhone,
      'device_id': deviceId,
      'nurse_id': nurseId,
      'room_number': roomNumber,
      'ward_name': wardName,
      'department_name': departmentName,
      'specialization': specialization,
      'is_on_call': isOnCall,
    };
  }
}
