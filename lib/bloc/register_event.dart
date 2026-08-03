import 'package:equatable/equatable.dart';

abstract class RegisterEvent extends Equatable {
  const RegisterEvent();

  @override
  List<Object?> get props => [];
}

class RegisterInitialize extends RegisterEvent {}

class RegisterFetchNearbyOrganizations extends RegisterEvent {
  final double lat;
  final double lon;
  final int radiusM;

  const RegisterFetchNearbyOrganizations({
    required this.lat,
    required this.lon,
    this.radiusM = 500,
  });

  @override
  List<Object?> get props => [lat, lon, radiusM];
}

class RegisterToggleManualSelection extends RegisterEvent {
  final bool isManual;
  const RegisterToggleManualSelection(this.isManual);
  @override
  List<Object?> get props => [isManual];
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

class RegisterLocationTypeSelected extends RegisterEvent {
  /// 'room' or 'ward'
  final String locationType;
  const RegisterLocationTypeSelected(this.locationType);
  @override
  List<Object?> get props => [locationType];
}

class RegisterBedSelected extends RegisterEvent {
  final int bedId;
  const RegisterBedSelected(this.bedId);
  @override
  List<Object?> get props => [bedId];
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
  final String? preCondition;

  const RegisterSubmit({
    required this.userId,
    required this.fullName,
    required this.phone,
    this.altPhone,
    required this.age,
    required this.gender,
    required this.bloodGroup,
    required this.deviceId,
    this.preCondition,
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
        preCondition,
      ];
}
