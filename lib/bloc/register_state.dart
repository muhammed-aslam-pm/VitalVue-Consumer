import 'package:equatable/equatable.dart';

enum RegisterStatus { initial, loading, success, failure }

class RegisterState extends Equatable {
  final RegisterStatus status;
  final String? errorMessage;

  final List<Map<String, dynamic>> organizations;
  final List<Map<String, dynamic>> departments;
  final List<Map<String, dynamic>> stations;
  final List<Map<String, dynamic>> wards;
  final List<Map<String, dynamic>> rooms;

  final int? selectedOrgId;
  final int? selectedDeptId;
  final int? selectedStationId;
  final int? selectedWardId;
  final int? selectedRoomId;

  const RegisterState({
    this.status = RegisterStatus.initial,
    this.errorMessage,
    this.organizations = const [],
    this.departments = const [],
    this.stations = const [],
    this.wards = const [],
    this.rooms = const [],
    this.selectedOrgId,
    this.selectedDeptId,
    this.selectedStationId,
    this.selectedWardId,
    this.selectedRoomId,
  });

  RegisterState copyWith({
    RegisterStatus? status,
    String? errorMessage,
    List<Map<String, dynamic>>? organizations,
    List<Map<String, dynamic>>? departments,
    List<Map<String, dynamic>>? stations,
    List<Map<String, dynamic>>? wards,
    List<Map<String, dynamic>>? rooms,
    int? selectedOrgId,
    int? selectedDeptId,
    int? selectedStationId,
    int? selectedWardId,
    int? selectedRoomId,
    bool clearOrg = false,
    bool clearDept = false,
    bool clearStation = false,
    bool clearWard = false,
    bool clearRoom = false,
  }) {
    return RegisterState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      organizations: organizations ?? this.organizations,
      departments: departments ?? this.departments,
      stations: stations ?? this.stations,
      wards: wards ?? this.wards,
      rooms: rooms ?? this.rooms,
      selectedOrgId: clearOrg ? null : (selectedOrgId ?? this.selectedOrgId),
      selectedDeptId: clearDept ? null : (selectedDeptId ?? this.selectedDeptId),
      selectedStationId: clearStation ? null : (selectedStationId ?? this.selectedStationId),
      selectedWardId: clearWard ? null : (selectedWardId ?? this.selectedWardId),
      selectedRoomId: clearRoom ? null : (selectedRoomId ?? this.selectedRoomId),
    );
  }

  @override
  List<Object?> get props => [
        status,
        errorMessage,
        organizations,
        departments,
        stations,
        wards,
        rooms,
        selectedOrgId,
        selectedDeptId,
        selectedStationId,
        selectedWardId,
        selectedRoomId,
      ];
}
