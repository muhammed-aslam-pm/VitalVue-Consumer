import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../auth/user_profile.dart';
import '../../bloc/auth_bloc.dart';
import '../../bloc/auth_state.dart';
import '../../bloc/patients_bloc.dart';
import '../../bloc/patients_event.dart';
import '../../bloc/patients_state.dart';
import '../../cloud/assigned_patient.dart';
import '../widgets/critical_alert_dialog.dart';
import '../widgets/patient_monitor_card.dart';
import 'profile_page.dart';

class StaffDashboardPage extends StatefulWidget {
  const StaffDashboardPage({super.key});

  @override
  State<StaffDashboardPage> createState() => _StaffDashboardPageState();
}

class _StaffDashboardPageState extends State<StaffDashboardPage> {
  @override
  void initState() {
    super.initState();
    Permission.notification.request();
    context.read<PatientsBloc>().add(const LoadPatients());
    FlutterBackgroundService().startService();
  }

  Future<void> _onRefresh() async {
    context.read<PatientsBloc>().add(const RefreshPatients());
    // Wait until no longer refreshing
    await Future.delayed(const Duration(milliseconds: 800));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PatientsBloc, PatientsState>(
      listenWhen: (previous, current) {
        if (previous is PatientsLoaded && current is PatientsLoaded) {
          return previous.pendingAlerts.length != current.pendingAlerts.length &&
              current.pendingAlerts.isNotEmpty;
        }
        return current is PatientsLoaded && current.pendingAlerts.isNotEmpty;
      },
      listener: (context, state) {
        if (state is PatientsLoaded && state.pendingAlerts.isNotEmpty) {
          final alert = state.pendingAlerts.first;
          final patient = state.patients
              .where((p) => p.id == alert.patientId)
              .firstOrNull;

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => CriticalAlertDialog(
              alert: alert,
              patient: patient,
              onDismiss: () {
                Navigator.of(context).pop();
                context.read<PatientsBloc>().add(DismissAlert(alert.alertId));
              },
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        body: Stack(
        children: [
          // Background blobs
          _Background(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App bar
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, authState) {
                    final profile = authState is AuthAuthenticated
                        ? authState.profile
                        : null;
                    return _AppBar(profile: profile);
                  },
                ),
                // Summary chips
                BlocBuilder<PatientsBloc, PatientsState>(
                  builder: (context, state) {
                    if (state is PatientsLoaded) {
                      return _SummaryBar(patients: state.patients);
                    }
                    return const SizedBox.shrink();
                  },
                ),
                // Patient list
                Expanded(
                  child: BlocBuilder<PatientsBloc, PatientsState>(
                    builder: (context, state) {
                      if (state is PatientsLoading) {
                        return const _LoadingView();
                      }
                      if (state is PatientsError) {
                        return _ErrorView(
                          message: state.message,
                          onRetry: () => context
                              .read<PatientsBloc>()
                              .add(const RefreshPatients()),
                        );
                      }
                      if (state is PatientsLoaded) {
                        return _PatientList(
                          patients: state.patients,
                          isRefreshing: state.isRefreshing,
                          onRefresh: _onRefresh,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }
}

// ── App Bar ────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  const _AppBar({required this.profile});
  final UserProfile? profile;

  String _roleLabel(String role) {
    switch (role) {
      case 'doctor':
        return 'Doctor';
      case 'nurse':
        return 'Nurse';
      default:
        return role[0].toUpperCase() + role.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VitalVue',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (profile != null)
                  Text(
                    '${_roleLabel(profile!.role)} Dashboard',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          // Live indicator
          BlocBuilder<PatientsBloc, PatientsState>(
            builder: (context, state) {
              if (state is PatientsLoaded && state.sseConnected) {
                return _LiveDot();
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(width: 8),
          // Profile button
          if (profile != null)
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfilePage(profile: profile!),
                ),
              ),
              icon: const Icon(Icons.person_rounded, color: Colors.white),
              tooltip: 'Profile',
            ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF43A047),
          ),
        )
            .animate(onPlay: (c) => c.repeat())
            .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1.3, 1.3),
                duration: 1000.ms,
                curve: Curves.easeInOut),
        const SizedBox(width: 5),
        Text(
          'LIVE',
          style: TextStyle(
            color: const Color(0xFF43A047),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

// ── Summary Bar ───────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.patients});
  final List<AssignedPatient> patients;

  @override
  Widget build(BuildContext context) {
    int critical = 0, warning = 0, stable = 0;
    for (final p in patients) {
      switch (p.overallSeverity) {
        case 2:
          critical++;
          break;
        case 1:
          warning++;
          break;
        default:
          stable++;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          _SummaryChip(
            label: 'Critical',
            count: critical,
            color: const Color(0xFFE53935),
            icon: Icons.emergency_rounded,
          ),
          const SizedBox(width: 8),
          _SummaryChip(
            label: 'Warning',
            count: warning,
            color: const Color(0xFFFFA726),
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(width: 8),
          _SummaryChip(
            label: 'Stable',
            count: stable,
            color: const Color(0xFF43A047),
            icon: Icons.check_circle_outline_rounded,
          ),
          const Spacer(),
          Text(
            '${patients.length} patient${patients.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 12,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            '$count $label',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Patient List ──────────────────────────────────────────────────────────

class _PatientList extends StatelessWidget {
  const _PatientList({
    required this.patients,
    required this.isRefreshing,
    required this.onRefresh,
  });
  final List<AssignedPatient> patients;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;

  // Sort: critical first, then warning, then stable. Connected before disconnected.
  List<AssignedPatient> get _sorted {
    final copy = [...patients];
    copy.sort((a, b) {
      final sev = b.overallSeverity.compareTo(a.overallSeverity);
      if (sev != 0) return sev;
      if (a.isConnected && !b.isConnected) return -1;
      if (!a.isConnected && b.isConnected) return 1;
      return a.fullName.compareTo(b.fullName);
    });
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    if (patients.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline_rounded,
                size: 64, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(
              'No patients assigned',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final sorted = _sorted;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: onRefresh,
          color: const Color(0xFF1A73E8),
          backgroundColor: const Color(0xFF1A1D27),
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            itemCount: sorted.length,
            itemBuilder: (context, i) => PatientMonitorCard(
              key: ValueKey(sorted[i].id),
              patient: sorted[i],
              index: i,
            ),
          ),
        ),
        if (isRefreshing)
          Positioned(
            top: 8,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF1A73E8).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: const Color(0xFF1A73E8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('Refreshing',
                      style: TextStyle(
                          color: Color(0xFF1A73E8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ).animate().fadeIn(duration: 200.ms),
          ),
      ],
    );
  }
}

// ── Loading / Error states ────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
              color: Color(0xFF1A73E8), strokeWidth: 2),
          const SizedBox(height: 20),
          Text(
            'Loading patients…',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 56, color: Color(0xFF4A4A5A)),
            const SizedBox(height: 16),
            Text(
              'Could not load patients',
              style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1A73E8),
                side: const BorderSide(color: Color(0xFF1A73E8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Background blobs ──────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -80,
          right: -60,
          child: _blob(const Color(0x261A73E8), 280),
        ),
        Positioned(
          bottom: 80,
          left: -40,
          child: _blob(const Color(0x1A7C4DFF), 240),
        ),
      ],
    );
  }

  Widget _blob(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0.2),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.2, 0.6, 1.0],
          ),
        ),
      );
}
