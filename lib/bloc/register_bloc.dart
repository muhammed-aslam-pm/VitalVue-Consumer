import 'package:flutter_bloc/flutter_bloc.dart';

import '../cloud/discovery_api.dart';
import '../cloud/patient_api.dart';
import 'register_event.dart';
import 'register_state.dart';

class RegisterBloc extends Bloc<RegisterEvent, RegisterState> {
  final DiscoveryApi discoveryApi;
  final PatientApi patientApi;

  RegisterBloc({
    required this.discoveryApi,
    required this.patientApi,
  }) : super(const RegisterState()) {
    on<RegisterFetchNearbyOrganizations>(_onFetchNearbyOrganizations);
    on<RegisterToggleManualSelection>(_onToggleManualSelection);
    on<RegisterSearchOrganizations>(_onSearchOrganizations);
    on<RegisterOrganizationSelected>(_onOrganizationSelected);
    on<RegisterDepartmentSelected>(_onDepartmentSelected);
    on<RegisterStationSelected>(_onStationSelected);
    on<RegisterLocationTypeSelected>(_onLocationTypeSelected);
    on<RegisterWardSelected>(_onWardSelected);
    on<RegisterRoomSelected>(_onRoomSelected);
    on<RegisterBedSelected>(_onBedSelected);
    on<RegisterSubmit>(_onSubmit);
    on<RegisterInitialize>(_onInitialize);
  }

  Future<void> _onFetchNearbyOrganizations(
      RegisterFetchNearbyOrganizations event, Emitter<RegisterState> emit) async {
    emit(state.copyWith(
      isAutoDetecting: true,
      clearLocationMessage: true,
    ));

    try {
      final nearbyOrgs = await discoveryApi.getNearbyOrganizations(
        lat: event.lat,
        lon: event.lon,
        radiusM: event.radiusM,
      );

      if (nearbyOrgs.isNotEmpty) {
        final firstOrgId = nearbyOrgs.first['id'] as int?;
        emit(state.copyWith(
          isAutoDetecting: false,
          isManualSelection: false,
          nearbyOrganizations: nearbyOrgs,
          organizations: nearbyOrgs,
          selectedOrgId: firstOrgId,
          locationMessage: 'Detected ${nearbyOrgs.length} nearby hospital(s).',
        ));

        if (firstOrgId != null) {
          add(RegisterOrganizationSelected(firstOrgId));
        }
      } else {
        emit(state.copyWith(
          isAutoDetecting: false,
          isManualSelection: true,
          nearbyOrganizations: [],
          locationMessage:
              'No hospitals detected within ${event.radiusM}m radius. Switched to manual selection.',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isAutoDetecting: false,
        isManualSelection: true,
        nearbyOrganizations: [],
        locationMessage:
            'Unable to fetch nearby hospitals. Switched to manual selection.',
      ));
    }
  }

  void _onToggleManualSelection(
      RegisterToggleManualSelection event, Emitter<RegisterState> emit) {
    emit(state.copyWith(isManualSelection: event.isManual));
  }

  Future<void> _onInitialize(
      RegisterInitialize event, Emitter<RegisterState> emit) async {
    try {
      final comorbidities = await discoveryApi.getComorbidities();
      emit(state.copyWith(comorbidities: comorbidities));
    } catch (_) {}
  }

  Future<void> _onSearchOrganizations(
      RegisterSearchOrganizations event, Emitter<RegisterState> emit) async {
    emit(state.copyWith(status: RegisterStatus.loading));
    try {
      final orgs = await discoveryApi.getOrganizations(
        country: event.country,
        state: event.state,
        city: event.city,
      );
      emit(state.copyWith(
        status: RegisterStatus.initial,
        organizations: orgs,
        departments: [],
        stations: [],
        wards: [],
        rooms: [],
        clearOrg: true,
        clearDept: true,
        clearStation: true,
        clearWard: true,
        clearRoom: true,
      ));
    } catch (e) {
      emit(state.copyWith(
          status: RegisterStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _onOrganizationSelected(
      RegisterOrganizationSelected event, Emitter<RegisterState> emit) async {
    emit(state.copyWith(
      status: RegisterStatus.loading,
      selectedOrgId: event.orgId,
      departments: [],
      stations: [],
      wards: [],
      rooms: [],
      clearDept: true,
      clearStation: true,
      clearWard: true,
      clearRoom: true,
    ));
    try {
      final depts = await discoveryApi.getDepartments(event.orgId);
      emit(state.copyWith(status: RegisterStatus.initial, departments: depts));
    } catch (e) {
      emit(state.copyWith(
          status: RegisterStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _onDepartmentSelected(
      RegisterDepartmentSelected event, Emitter<RegisterState> emit) async {
    emit(state.copyWith(
      status: RegisterStatus.loading,
      selectedDeptId: event.deptId,
      stations: [],
      wards: [],
      rooms: [],
      clearStation: true,
      clearWard: true,
      clearRoom: true,
    ));
    try {
      final stations = await discoveryApi.getStations(event.deptId);
      emit(state.copyWith(status: RegisterStatus.initial, stations: stations));
    } catch (e) {
      emit(state.copyWith(
          status: RegisterStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _onStationSelected(
      RegisterStationSelected event, Emitter<RegisterState> emit) async {
    // Selecting a station resets everything downstream so the user
    // must re-choose the location type (Room vs Ward).
    emit(state.copyWith(
      status: RegisterStatus.initial,
      selectedStationId: event.stationId,
      wards: [],
      rooms: [],
      beds: [],
      clearLocationType: true,
      clearWard: true,
      clearRoom: true,
      clearBed: true,
    ));
  }

  Future<void> _onLocationTypeSelected(
      RegisterLocationTypeSelected event, Emitter<RegisterState> emit) async {
    final isWard = event.locationType == 'ward';
    final newType = isWard ? StationLocationType.ward : StationLocationType.room;

    emit(state.copyWith(
      status: RegisterStatus.loading,
      locationType: newType,
      wards: [],
      rooms: [],
      beds: [],
      clearWard: true,
      clearRoom: true,
      clearBed: true,
    ));

    try {
      if (isWard) {
        // Ward path: fetch wards under the current station
        final wards = await discoveryApi.getWards(state.selectedStationId!);
        emit(state.copyWith(
          status: RegisterStatus.initial,
          locationType: newType,
          wards: wards,
        ));
      } else {
        // Room path: fetch rooms under the current station's first ward,
        // or — if the API exposes rooms directly from the station — use that.
        // Here we fetch from the station itself treated as a wardId context.
        final rooms = await discoveryApi.getRooms(state.selectedStationId!);
        emit(state.copyWith(
          status: RegisterStatus.initial,
          locationType: newType,
          rooms: rooms,
        ));
      }
    } catch (e) {
      emit(state.copyWith(
          status: RegisterStatus.failure, errorMessage: e.toString()));
    }
  }

  Future<void> _onWardSelected(
      RegisterWardSelected event, Emitter<RegisterState> emit) async {
    emit(state.copyWith(
      status: RegisterStatus.loading,
      selectedWardId: event.wardId,
      beds: [],
      rooms: [],
      clearRoom: true,
      clearBed: true,
    ));
    try {
      // Ward path: fetch available beds for the selected ward
      final beds = await discoveryApi.getBedsForWard(event.wardId);
      emit(state.copyWith(status: RegisterStatus.initial, beds: beds));
    } catch (e) {
      emit(state.copyWith(
          status: RegisterStatus.failure, errorMessage: e.toString()));
    }
  }

  void _onRoomSelected(
      RegisterRoomSelected event, Emitter<RegisterState> emit) {
    emit(state.copyWith(selectedRoomId: event.roomId));
  }

  void _onBedSelected(
      RegisterBedSelected event, Emitter<RegisterState> emit) {
    emit(state.copyWith(selectedBedId: event.bedId));
  }

  Future<void> _onSubmit(
      RegisterSubmit event, Emitter<RegisterState> emit) async {
    final isWardPath = state.locationType == StationLocationType.ward;

    // Validate: if ward path, bed must be selected; if room path, room must be selected.
    if (isWardPath && state.selectedBedId == null) {
      emit(state.copyWith(
          status: RegisterStatus.failure,
          errorMessage: 'Please select a bed.'));
      return;
    }
    if (!isWardPath && state.selectedRoomId == null) {
      emit(state.copyWith(
          status: RegisterStatus.failure,
          errorMessage: 'Please select a room.'));
      return;
    }

    emit(state.copyWith(status: RegisterStatus.loading));
    try {
      final success = await patientApi.registerPatient(
        userId: event.userId,
        phoneNumber: event.phone,
        fullName: event.fullName,
        roomId: isWardPath ? null : state.selectedRoomId,
        bedId: isWardPath ? state.selectedBedId : null,
        age: event.age,
        gender: event.gender,
        bloodGroup: event.bloodGroup,
        deviceId: event.deviceId,
        altPhone: event.altPhone,
        preCondition: event.preCondition,
      );

      if (success) {
        emit(state.copyWith(status: RegisterStatus.success));
      } else {
        emit(state.copyWith(
            status: RegisterStatus.failure,
            errorMessage: 'Failed to register patient.'));
      }
    } catch (e) {
      emit(state.copyWith(
          status: RegisterStatus.failure, errorMessage: e.toString()));
    }
  }
}
