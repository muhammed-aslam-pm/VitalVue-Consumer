import 'package:equatable/equatable.dart';

abstract class RegisterEvent extends Equatable {
  const RegisterEvent();

  @override
  List<Object?> get props => [];
}

class RegisterSearchOrganizations extends RegisterEvent {
  final String country;
  final String state;
  final String city;

  const RegisterSearchOrganizations({
    required this.country,
    required this.state,
    required this.city,
  });

  @override
  List<Object?> get props => [country, state, city];
}

class RegisterOrganizationSelected extends RegisterEvent {
  final int orgId;
  const RegisterOrganizationSelected(this.orgId);
  @override
  List<Object?> get props => [orgId];
}

class RegisterDepartmentSelected extends RegisterEvent {
  final int deptId;
  const RegisterDepartmentSelected(this.deptId);
  @override
  List<Object?> get props => [deptId];
}

class RegisterStationSelected extends RegisterEvent {
  final int stationId;
  const RegisterStationSelected(this.stationId);
  @override
  List<Object?> get props => [stationId];
}

class RegisterWardSelected extends RegisterEvent {
  final int wardId;
  const RegisterWardSelected(this.wardId);
  @override
  List<Object?> get props => [wardId];
}

class RegisterRoomSelected extends RegisterEvent {
  final int roomId;
  const RegisterRoomSelected(this.roomId);
  @override
  List<Object?> get props => [roomId];
}

class RegisterSubmit extends RegisterEvent {
  final String userId;
  final String fullName;
  final String phone;
  final String? altPhone;
  final int age;
  final String gender;
  final String bloodGroup;
  final String deviceId;

  const RegisterSubmit({
    required this.userId,
    required this.fullName,
    required this.phone,
    this.altPhone,
    required this.age,
    required this.gender,
    required this.bloodGroup,
    required this.deviceId,
  });

  @override
  List<Object?> get props => [
        userId,
        fullName,
        phone,
        altPhone,
        age,
        gender,
        bloodGroup,
        deviceId,
      ];
}
