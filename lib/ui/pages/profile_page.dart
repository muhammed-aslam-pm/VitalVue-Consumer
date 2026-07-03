import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/patient_profile.dart';
import '../../bloc/auth_bloc.dart';
import '../../bloc/auth_event.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.profile});

  final PatientProfile profile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Patient Profile',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Avatar
            CircleAvatar(
              radius: 48,
              backgroundColor: const Color(0xFF1A73E8).withValues(alpha: 0.2),
              child: Text(
                profile.fullName.isNotEmpty ? profile.fullName[0].toUpperCase() : '?',
                style: GoogleFonts.inter(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A73E8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              profile.fullName,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'Patient ID: ${profile.userId}',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 32),

            // Info Cards
            _buildSection(
              title: 'Vitals Basics',
              children: [
                _buildRow('Age', '${profile.age} years'),
                _buildRow('Gender', profile.gender),
                _buildRow('Height', '${profile.height} cm'),
                _buildRow('Weight', '${profile.weight} kg'),
                _buildRow('Blood Group', profile.bloodGroup ?? 'N/A'),
              ],
            ),
            
            const SizedBox(height: 16),
            _buildSection(
              title: 'Hospital Context',
              children: [
                _buildRow('Doctor', profile.doctorName ?? 'N/A'),
                _buildRow('Department', profile.departmentName ?? 'N/A'),
                _buildRow('Ward / Room', '${profile.wardName ?? '-'} / ${profile.roomNumber ?? '-'}'),
              ],
            ),

            const SizedBox(height: 16),
            _buildSection(
              title: 'Contact Information',
              children: [
                _buildRow('Primary Phone', profile.phoneNumber ?? 'N/A'),
                _buildRow('Alt Phone', profile.altPhone ?? 'N/A'),
              ],
            ),

            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.read<AuthBloc>().add(const AuthLogout());
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE53935),
                  side: const BorderSide(color: Color(0xFFE53935)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text(
                  'Log Out',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white54,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
