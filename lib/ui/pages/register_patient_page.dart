import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  String _bloodGroup = 'O+';

  @override
  void initState() {
    super.initState();
    _registerBloc = RegisterBloc(
      discoveryApi: DiscoveryApi(baseUrl: _kApiBaseUrl),
      patientApi: PatientApi(baseUrl: _kApiBaseUrl),
    );
    _registerBloc.add(const RegisterSearchOrganizations(
      country: 'India',
      state: 'Kerala',
      city: 'Cochin',
    ));
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
          backgroundColor: const Color(0xFF0F1117),
          elevation: 0,
        ),
        backgroundColor: const Color(0xFF0F1117),
        body: BlocConsumer<RegisterBloc, RegisterState>(
          listener: (context, state) {
            if (state.status == RegisterStatus.success) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Patient registered successfully!')),
              );
              Navigator.of(context).pop();
            } else if (state.status == RegisterStatus.failure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.errorMessage ?? 'Registration failed')),
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
                    _buildTextField(_userIdCtrl, 'Patient ID (User ID)', required: true),
                    _buildTextField(_fullNameCtrl, 'Full Name', required: true, textCapitalization: TextCapitalization.words),
                    Row(
                      children: [
                        Expanded(child: _buildTextField(_ageCtrl, 'Age', required: true, keyboardType: TextInputType.number)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _gender,
                            decoration: InputDecoration(
                              labelText: 'Gender',
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.1),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            dropdownColor: const Color(0xFF1A1C24),
                            style: const TextStyle(color: Colors.white),
                            items: const [
                              DropdownMenuItem(value: 'M', child: Text('Male')),
                              DropdownMenuItem(value: 'F', child: Text('Female')),
                              DropdownMenuItem(value: 'O', child: Text('Other')),
                            ],
                            onChanged: (val) => setState(() => _gender = val!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _bloodGroup,
                      decoration: InputDecoration(
                        labelText: 'Blood Group',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.1),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      dropdownColor: const Color(0xFF1A1C24),
                      style: const TextStyle(color: Colors.white),
                      items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                          .map((bg) => DropdownMenuItem(value: bg, child: Text(bg)))
                          .toList(),
                      onChanged: (val) => setState(() => _bloodGroup = val!),
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(_phoneCtrl, 'Phone Number', required: true, keyboardType: TextInputType.phone),
                    _buildTextField(_altPhoneCtrl, 'Alt Phone Number', keyboardType: TextInputType.phone),
                    
                    const SizedBox(height: 32),
                    _buildSectionTitle('Hospital Details'),
                    
                    _buildDropdown('Hospital', state.organizations, state.selectedOrgId, (id) {
                      _registerBloc.add(RegisterOrganizationSelected(id));
                    }),
                    
                    _buildDropdown('Department', state.departments, state.selectedDeptId, (id) {
                      _registerBloc.add(RegisterDepartmentSelected(id));
                    }),
                    
                    _buildDropdown('Nursing Station', state.stations, state.selectedStationId, (id) {
                      _registerBloc.add(RegisterStationSelected(id));
                    }),
                    
                    _buildDropdown('Ward', state.wards, state.selectedWardId, (id) {
                      _registerBloc.add(RegisterWardSelected(id));
                    }),
                    
                    _buildDropdown('Room', state.rooms, state.selectedRoomId, (id) {
                      _registerBloc.add(RegisterRoomSelected(id));
                    }),

                    const SizedBox(height: 48),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFF1A73E8),
                      ),
                      onPressed: state.status == RegisterStatus.loading ? null : _onSubmit,
                      child: state.status == RegisterStatus.loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Register Patient', style: TextStyle(fontSize: 16, color: Colors.white)),
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
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl, 
    String label, 
    {bool required = false, TextInputType keyboardType = TextInputType.text, TextCapitalization textCapitalization = TextCapitalization.none}
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.1),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        validator: required
            ? (value) => (value == null || value.isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }

  Widget _buildDropdown(
    String label, 
    List<Map<String, dynamic>> items, 
    int? selectedValue, 
    Function(int)? onChanged
  ) {
    final bool isEmpty = items.isEmpty;
    final dropdown = DropdownButtonFormField<int>(
      value: selectedValue,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dropdownColor: const Color(0xFF1A1C24),
      style: const TextStyle(color: Colors.white),
      items: isEmpty ? null : items.map((item) {
        final displayName = item['name'] ?? item['room_number'] ?? 'Unknown';
        return DropdownMenuItem<int>(
          value: item['id'] as int,
          child: Text(displayName.toString()),
        );
      }).toList(),
      onChanged: isEmpty ? null : (val) {
        if (val != null && onChanged != null) onChanged(val);
      },
      validator: (value) => value == null && !isEmpty ? 'Please select $label' : null,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: isEmpty
          ? GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No $label found for the selected location.')),
                );
              },
              child: AbsorbPointer(child: dropdown),
            )
          : dropdown,
    );
  }
}
