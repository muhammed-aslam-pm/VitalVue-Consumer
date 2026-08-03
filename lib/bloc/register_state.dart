import 'package:equatable/equatable.dart';

enum RegisterStatus { initial, loading, success, failure }

/// Which sub-path was chosen after the nursing station selection.
enum StationLocationType { none, room, ward }

class RegisterState extends Equatable {
  final RegisterStatus status;
  final String? errorMessage;

  final bool isAutoDetecting;
  final bool isManualSelection;
  final String? locationMessage;
  final List<Map<String, dynamic>> nearbyOrganizations;

  final List<Map<String, dynamic>> organizations;
  final List<Map<String, dynamic>> departments;
  final List<Map<String, dynamic>> stations;
  final List<Map<String, dynamic>> wards;
  final List<Map<String, dynamic>> rooms;
  final List<Map<String, dynamic>> beds;
  final List<String> comorbidities;

  /// Whether the user chose "Room" or "Ward" after station selection.
  final StationLocationType locationType;

  final int? selectedOrgId;
  final int? selectedDeptId;
  final int? selectedStationId;
  final int? selectedWardId;
  final int? selectedRoomId;
  final int? selectedBedId;

  const RegisterState({
    this.status = RegisterStatus.initial,
    this.errorMessage,
    this.isAutoDetecting = false,
    this.isManualSelection = false,
    this.locationMessage,
    this.nearbyOrganizations = const [],
    this.organizations = const [],
    this.departments = const [],
    this.stations = const [],
    this.wards = const [],
    this.rooms = const [],
    this.beds = const [],
    this.comorbidities = const [],
    this.locationType = StationLocationType.none,
    this.selectedOrgId,
    this.selectedDeptId,
    this.selectedStationId,
    this.selectedWardId,
    this.selectedRoomId,
    this.selectedBedId,
  });

  RegisterState copyWith({
    RegisterStatus? status,
    String? errorMessage,
    bool? isAutoDetecting,
    bool? isManualSelection,
    String? locationMessage,
    bool clearLocationMessage = false,
    List<Map<String, dynamic>>? nearbyOrganizations,
    List<Map<String, dynamic>>? organizations,
    List<Map<String, dynamic>>? departments,
    List<Map<String, dynamic>>? stations,
    List<Map<String, dynamic>>? wards,
    List<Map<String, dynamic>>? rooms,
    List<Map<String, dynamic>>? beds,
    List<String>? comorbidities,
    StationLocationType? locationType,
    int? selectedOrgId,
    int? selectedDeptId,
    int? selectedStationId,
    int? selectedWardId,
    int? selectedRoomId,
    int? selectedBedId,
    bool clearOrg = false,
    bool clearDept = false,
    bool clearStation = false,
    bool clearLocationType = false,
    bool clearWard = false,
    bool clearRoom = false,
    bool clearBed = false,
  }) {
    return RegisterState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      isAutoDetecting: isAutoDetecting ?? this.isAutoDetecting,
      isManualSelection: isManualSelection ?? this.isManualSelection,
      locationMessage: clearLocationMessage ? null : (locationMessage ?? this.locationMessage),
      nearbyOrganizations: nearbyOrganizations ?? this.nearbyOrganizations,
      organizations: organizations ?? this.organizations,
      departments: departments ?? this.departments,
      stations: stations ?? this.stations,
      wards: wards ?? this.wards,
      rooms: rooms ?? this.rooms,
      beds: beds ?? this.beds,
      comorbidities: comorbidities ?? this.comorbidities,
      locationType: clearLocationType ? StationLocationType.none : (locationType ?? this.locationType),
      selectedOrgId: clearOrg ? null : (selectedOrgId ?? this.selectedOrgId),
      selectedDeptId: clearDept ? null : (selectedDeptId ?? this.selectedDeptId),
      selectedStationId: clearStation ? null : (selectedStationId ?? this.selectedStationId),
      selectedWardId: clearWard ? null : (selectedWardId ?? this.selectedWardId),
      selectedRoomId: clearRoom ? null : (selectedRoomId ?? this.selectedRoomId),
      selectedBedId: clearBed ? null : (selectedBedId ?? this.selectedBedId),
    );
  }

  @override
  List<Object?> get props => [
        status,
        errorMessage,
        isAutoDetecting,
        isManualSelection,
        locationMessage,
        nearbyOrganizations,
        organizations,
        departments,
        stations,
        wards,
        rooms,
        beds,
        comorbidities,
        locationType,
        selectedOrgId,
        selectedDeptId,
        selectedStationId,
        selectedWardId,
        selectedRoomId,
        selectedBedId,
      ];
}
