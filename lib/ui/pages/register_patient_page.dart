import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../bloc/register_bloc.dart';
import '../../bloc/register_event.dart';
import '../../bloc/register_state.dart';
import '../../cloud/discovery_api.dart';
import '../../cloud/patient_api.dart';

const _kApiBaseUrl = String.fromEnvironment(
  'BAND_API_URL',
  defaultValue: 'https://vitalvue-api.genesysailabs.com',
);

class RegisterPatientPage extends StatefulWidget {
  const RegisterPatientPage({super.key});

  @override
  State<RegisterPatientPage> createState() => _RegisterPatientPageState();
}

class _RegisterPatientPageState extends State<RegisterPatientPage> {
  late final RegisterBloc _registerBloc;

  final _formKey = GlobalKey<FormState>();

  final _userIdCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _altPhoneCtrl = TextEditingController();
  String _gender = 'M';
  final String _bloodGroup = 'O+';
  String? _preCondition;

  @override
  void initState() {
    super.initState();
    _registerBloc = RegisterBloc(
      discoveryApi: DiscoveryApi(baseUrl: _kApiBaseUrl),
      patientApi: PatientApi(baseUrl: _kApiBaseUrl),
    );
    _registerBloc.add(RegisterInitialize());
    _registerBloc.add(const RegisterSearchOrganizations(
      country: 'India',
      state: 'Kerala',
      city: 'Cochin',
    ));
    _detectLocationAndFetchHospitals();
  }

  @override
  void dispose() {
    _registerBloc.close();
    _userIdCtrl.dispose();
    _fullNameCtrl.dispose();
    _ageCtrl.dispose();
    _phoneCtrl.dispose();
    _altPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectLocationAndFetchHospitals() async {
    var permission = await Permission.locationWhenInUse.status;
    if (permission.isDenied) {
      permission = await Permission.locationWhenInUse.request();
    }

    if (!permission.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Location permission required for auto-detect. Switched to manual selection.'),
            backgroundColor: Color(0xFFE53935),
          ),
        );
      }
      _registerBloc.add(const RegisterToggleManualSelection(true));
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please enable Location Services (GPS) to auto-detect nearby hospitals.'),
            backgroundColor: Color(0xFFE53935),
          ),
        );
      }
      _registerBloc.add(const RegisterToggleManualSelection(true));
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _registerBloc.add(RegisterFetchNearbyOrganizations(
        lat: position.latitude,
        lon: position.longitude,
        radiusM: 200,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Could not get GPS location: $e. Switched to manual selection.'),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
      _registerBloc.add(const RegisterToggleManualSelection(true));
    }
  }

  void _onSubmit() {
    if (_formKey.currentState!.validate()) {
      _registerBloc.add(RegisterSubmit(
        userId: _userIdCtrl.text.trim(),
        fullName: _fullNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        altPhone: _altPhoneCtrl.text.trim(),
        age: int.tryParse(_ageCtrl.text.trim()) ?? 0,
        gender: _gender,
        bloodGroup: _bloodGroup,
        deviceId: 'device_${DateTime.now().millisecondsSinceEpoch}',
        preCondition: _preCondition,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _registerBloc,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Register Patient'),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: BlocConsumer<RegisterBloc, RegisterState>(
          listener: (context, state) {
            if (state.status == RegisterStatus.success) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Patient registered successfully!')),
              );
              Navigator.of(context).pop();
            } else if (state.status == RegisterStatus.failure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(state.errorMessage ?? 'Registration failed')),
              );
            }
          },
          builder: (context, state) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSectionTitle('Personal Details'),
                    _buildTextField(_userIdCtrl, 'Patient ID (User ID)',
                        required: true),
                    _buildTextField(_fullNameCtrl, 'Full Name',
                        required: true,
                        textCapitalization: TextCapitalization.words),
                    Row(
                      children: [
                        Expanded(
                            child: _buildTextField(_ageCtrl, 'Age',
                                required: true,
                                keyboardType: TextInputType.number)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _gender,
                            decoration: InputDecoration(
                              labelText: 'Gender',
                              filled: true,
                              fillColor: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.05),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                            dropdownColor:
                                Theme.of(context).colorScheme.surface,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface),
                            items: const [
                              DropdownMenuItem(value: 'M', child: Text('Male')),
                              DropdownMenuItem(
                                  value: 'F', child: Text('Female')),
                              DropdownMenuItem(
                                  value: 'O', child: Text('Other')),
                            ],
                            onChanged: (val) => setState(() => _gender = val!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(_phoneCtrl, 'Phone Number',
                        required: true, keyboardType: TextInputType.phone),
                    _buildTextField(_altPhoneCtrl, 'Alt Phone Number',
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionTitle('Hospital Details'),
                        TextButton.icon(
                          onPressed: () {
                            if (state.isManualSelection) {
                              _detectLocationAndFetchHospitals();
                            } else {
                              _registerBloc.add(
                                  const RegisterToggleManualSelection(true));
                            }
                          },
                          icon: Icon(
                            state.isManualSelection
                                ? Icons.my_location_rounded
                                : Icons.edit_location_alt_rounded,
                            size: 18,
                            color: const Color(0xFF1A73E8),
                          ),
                          label: Text(
                            state.isManualSelection
                                ? 'Auto-Detect (GPS)'
                                : 'Manual Selection',
                            style: const TextStyle(
                              color: Color(0xFF1A73E8),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (state.isAutoDetecting) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF1A73E8).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                const Color(0xFF1A73E8).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Detecting nearby hospital using device GPS...',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1A73E8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (state.locationMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: state.isManualSelection
                              ? const Color(0xFFFFF3E0)
                              : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: state.isManualSelection
                                ? const Color(0xFFFFB74D)
                                : const Color(0xFF81C784),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              state.isManualSelection
                                  ? Icons.info_outline_rounded
                                  : Icons.check_circle_outline_rounded,
                              size: 20,
                              color: state.isManualSelection
                                  ? const Color(0xFFE65100)
                                  : const Color(0xFF2E7D32),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                state.locationMessage!,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: state.isManualSelection
                                      ? const Color(0xFFE65100)
                                      : const Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    _buildDropdown(
                        'Hospital', state.organizations, state.selectedOrgId,
                        (id) {
                      _registerBloc.add(RegisterOrganizationSelected(id));
                    }),
                    _buildDropdown(
                        'Department', state.departments, state.selectedDeptId,
                        (id) {
                      _registerBloc.add(RegisterDepartmentSelected(id));
                    }),
                    _buildDropdown('Nursing Station', state.stations,
                        state.selectedStationId, (id) {
                      _registerBloc.add(RegisterStationSelected(id));
                    }),

                    // ── Location type choice ────────────────────────────────
                    if (state.selectedStationId != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A73E8).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF1A73E8)
                                  .withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select location type',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A73E8)),
                            ),
                            const SizedBox(height: 10),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'room',
                                  label: Text('Room'),
                                  icon: Icon(Icons.meeting_room_rounded),
                                ),
                                ButtonSegment(
                                  value: 'ward',
                                  label: Text('Ward'),
                                  icon: Icon(Icons.local_hospital_rounded),
                                ),
                              ],
                              selected: {
                                if (state.locationType ==
                                    StationLocationType.room)
                                  'room'
                                else if (state.locationType ==
                                    StationLocationType.ward)
                                  'ward'
                                else
                                  ''
                              },
                              emptySelectionAllowed: true,
                              onSelectionChanged: (val) {
                                if (val.isEmpty) return;
                                _registerBloc.add(
                                    RegisterLocationTypeSelected(val.first));
                              },
                              style: SegmentedButton.styleFrom(
                                selectedBackgroundColor:
                                    const Color(0xFF1A73E8),
                                selectedForegroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── Room path ───────────────────────────────────────────
                    if (state.locationType == StationLocationType.room) ...[
                      _buildDropdown('Room', state.rooms, state.selectedRoomId,
                          (id) {
                        _registerBloc.add(RegisterRoomSelected(id));
                      }),
                    ],

                    // ── Ward path ───────────────────────────────────────────
                    if (state.locationType == StationLocationType.ward) ...[
                      _buildDropdown('Ward', state.wards, state.selectedWardId,
                          (id) {
                        _registerBloc.add(RegisterWardSelected(id));
                      }),
                      _buildDropdown('Bed', state.beds, state.selectedBedId,
                          (id) {
                        _registerBloc.add(RegisterBedSelected(id));
                      }),
                    ],

                    const SizedBox(height: 48),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFF1A73E8),
                      ),
                      onPressed: state.status == RegisterStatus.loading
                          ? null
                          : _onSubmit,
                      child: state.status == RegisterStatus.loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Register Patient',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label,
      {bool required = false,
      TextInputType keyboardType = TextInputType.text,
      TextCapitalization textCapitalization = TextCapitalization.none}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        keyboardType: keyboardType,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        validator: required
            ? (value) => (value == null || value.isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }

  Widget _buildDropdown(String label, List<Map<String, dynamic>> items,
      int? selectedValue, Function(int)? onChanged) {
    final bool isEmpty = items.isEmpty;
    final dropdown = DropdownButtonFormField<int>(
      value: selectedValue,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor:
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      dropdownColor: Theme.of(context).colorScheme.surface,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      items: isEmpty
          ? null
          : items.map((item) {
              final displayName =
                  item['name'] ?? item['bed_no'] ?? item['room_number'] ?? 'Unknown';
              return DropdownMenuItem<int>(
                value: item['id'] as int,
                child: Text(displayName.toString()),
              );
            }).toList(),
      onChanged: isEmpty
          ? null
          : (val) {
              if (val != null && onChanged != null) onChanged(val);
            },
      validator: (value) =>
          value == null && !isEmpty ? 'Please select $label' : null,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: isEmpty
          ? GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('No $label found for the selected location.')),
                );
              },
              child: AbsorbPointer(child: dropdown),
            )
          : dropdown,
    );
  }
}
