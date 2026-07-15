import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/user_profile.dart';
import '../../bloc/auth_bloc.dart';
import '../../bloc/auth_event.dart';
import '../../background/background_preferences.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _enableTts = true;
  bool _enablePush = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final tts = await BackgroundPreferences.getEnableTts();
    final push = await BackgroundPreferences.getEnablePush();
    if (mounted) {
      setState(() {
        _enableTts = tts;
        _enablePush = push;
      });
    }
  }

  // Map role values to readable display strings
  String get _roleLabel {
    switch (widget.profile.role) {
      case 'doctor':
        return 'Doctor';
      case 'nurse':
        return 'Nurse';
      case 'patient':
        return 'Patient';
      default:
        return widget.profile.role[0].toUpperCase() + widget.profile.role.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '$_roleLabel Profile',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
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
                profile.fullName.isNotEmpty
                    ? profile.fullName[0].toUpperCase()
                    : '?',
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
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            // Role badge
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF1A73E8).withValues(alpha: 0.4)),
              ),
              child: Text(
                _roleLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A73E8),
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Text(
              'ID: ${profile.userId}',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 32),

            // ── Patient sections ──────────────────────────────────────────
            if (profile.isPatient) ...[
              _buildSection(
                title: 'Vitals Basics',
                children: [
                  _buildRow('Age', '${profile.age ?? 'N/A'} years'),
                  _buildRow('Gender', profile.gender ?? 'N/A'),
                  _buildRow('Height',
                      profile.height != null ? '${profile.height} cm' : 'N/A'),
                  _buildRow('Weight',
                      profile.weight != null ? '${profile.weight} kg' : 'N/A'),
                  _buildRow('Blood Group', profile.bloodGroup ?? 'N/A'),
                ],
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'Hospital Context',
                children: [
                  _buildRow('Doctor', profile.doctorName ?? 'N/A'),
                  _buildRow('Department', profile.departmentName ?? 'N/A'),
                  _buildRow('Ward / Room',
                      '${profile.wardName ?? '-'} / ${profile.roomNumber ?? '-'}'),
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
            ],

            // ── Staff / Doctor / Nurse sections ───────────────────────────
            if (!profile.isPatient) ...[
              _buildSection(
                title: 'Professional Details',
                children: [
                  if (profile.specialization != null)
                    _buildRow('Specialization', profile.specialization!),
                  if (profile.isOnCall != null)
                    _buildRow(
                        'On-Call Status', profile.isOnCall! ? 'On Call' : 'Off Duty'),
                  if (profile.organizationId != null)
                    _buildRow('Organisation',
                        'Org #${profile.organizationId}'),
                ],
              ),
              const SizedBox(height: 16),
              _buildSection(
                title: 'Contact Information',
                children: [
                  _buildRow('Phone', profile.phoneNumber ?? 'N/A'),
                ],
              ),
            ],

            const SizedBox(height: 16),
            _buildSection(
              title: 'Alert Settings',
              children: [
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: const Color(0xFF1A73E8),
                    title: Text(
                      'Voice Announcements',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      'Verbal read-out of critical alerts',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                    ),
                    value: _enableTts,
                    onChanged: (val) async {
                      setState(() => _enableTts = val);
                      await BackgroundPreferences.setEnableTts(val);
                    },
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: const Color(0xFF1A73E8),
                    title: Text(
                      'Push Notifications',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      'Heads-up banners for critical alerts',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                    ),
                    value: _enablePush,
                    onChanged: (val) async {
                      setState(() => _enablePush = val);
                      await BackgroundPreferences.setEnablePush(val);
                    },
                  ),
                ),
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

  Widget _buildSection(
      {required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
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
          Text(label,
              style:
                  TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}

