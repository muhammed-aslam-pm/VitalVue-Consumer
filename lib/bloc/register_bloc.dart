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
    on<RegisterSearchOrganizations>(_onSearchOrganizations);
    on<RegisterOrganizationSelected>(_onOrganizationSelected);
    on<RegisterDepartmentSelected>(_onDepartmentSelected);
    on<RegisterStationSelected>(_onStationSelected);
    on<RegisterWardSelected>(_onWardSelected);
    on<RegisterRoomSelected>(_onRoomSelected);
    on<RegisterSubmit>(_onSubmit);
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
    emit(state.copyWith(
      status: RegisterStatus.loading,
      selectedStationId: event.stationId,
      wards: [],
      rooms: [],
      clearWard: true,
      clearRoom: true,
    ));
    try {
      final wards = await discoveryApi.getWards(event.stationId);
      emit(state.copyWith(status: RegisterStatus.initial, wards: wards));
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
      rooms: [],
      clearRoom: true,
    ));
    try {
      final rooms = await discoveryApi.getRooms(event.wardId);
      emit(state.copyWith(status: RegisterStatus.initial, rooms: rooms));
    } catch (e) {
      emit(state.copyWith(
          status: RegisterStatus.failure, errorMessage: e.toString()));
    }
  }

  void _onRoomSelected(
      RegisterRoomSelected event, Emitter<RegisterState> emit) {
    emit(state.copyWith(selectedRoomId: event.roomId));
  }

  Future<void> _onSubmit(
      RegisterSubmit event, Emitter<RegisterState> emit) async {
    if (state.selectedRoomId == null) {
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
        roomId: state.selectedRoomId!,
        age: event.age,
        gender: event.gender,
        bloodGroup: event.bloodGroup,
        deviceId: event.deviceId,
        altPhone: event.altPhone,
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
