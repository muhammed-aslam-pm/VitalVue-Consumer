class PatientProfile {
  final int id;
  final String userId;
  final String fullName;
  final String role;
  final int? organizationId;
  final String? phoneNumber;
  final int age;
  final String gender;
  final int height;
  final int weight;
  final String? bloodGroup;
  final String? altPhone;
  final String? deviceId;
  final String? nurseId;
  final String? doctorName;
  final String? roomNumber;
  final String? wardName;
  final String? departmentName;

  PatientProfile({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.role,
    this.organizationId,
    this.phoneNumber,
    required this.age,
    required this.gender,
    required this.height,
    required this.weight,
    this.bloodGroup,
    this.altPhone,
    this.deviceId,
    this.nurseId,
    this.doctorName,
    this.roomNumber,
    this.wardName,
    this.departmentName,
  });

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    return PatientProfile(
      id: json['id'] as int,
      userId: json['user_id'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      role: json['role'] as String? ?? 'patient',
      organizationId: json['organization_id'] as int?,
      phoneNumber: json['phone_number'] as String?,
      age: (json['age'] as num?)?.toInt() ?? 30, // Fallback if missing
      gender: json['gender'] as String? ?? 'Male',
      height: (json['height'] as num?)?.toInt() ?? 170, // Fallback for SDK
      weight: (json['weight'] as num?)?.toInt() ?? 70, // Fallback for SDK
      bloodGroup: json['blood_group'] as String?,
      altPhone: json['alt_phone'] as String?,
      deviceId: json['device_id'] as String?,
      nurseId: json['nurse_id'] as String?,
      doctorName: json['doctor_name'] as String?,
      roomNumber: json['room_number'] as String?,
      wardName: json['ward_name'] as String?,
      departmentName: json['department_name'] as String?,
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
      'doctor_name': doctorName,
      'room_number': roomNumber,
      'ward_name': wardName,
      'department_name': departmentName,
    };
  }
}
