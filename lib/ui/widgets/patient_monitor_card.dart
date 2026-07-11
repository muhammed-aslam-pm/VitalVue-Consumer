import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../cloud/assigned_patient.dart';

class PatientMonitorCard extends StatelessWidget {
  const PatientMonitorCard({
    super.key,
    required this.patient,
    required this.index,
  });

  final AssignedPatient patient;
  final int index;

  // ── Status color helpers ──────────────────────────────────────────────────

  static Color _statusColor(String status) {
    switch (status) {
      case 'Critical':
        return const Color(0xFFE53935);
      case 'Warning':
        return const Color(0xFFFFA726);
      default:
        return const Color(0xFF43A047);
    }
  }

  static Color _severityBorderColor(int severity) {
    if (severity == 2) return const Color(0xFFE53935).withValues(alpha: 0.7);
    if (severity == 1) return const Color(0xFFFFA726).withValues(alpha: 0.5);
    return Colors.white.withValues(alpha: 0.06);
  }

  static Color _severityBgTint(int severity) {
    if (severity == 2) return const Color(0xFFE53935).withValues(alpha: 0.06);
    if (severity == 1) return const Color(0xFFFFA726).withValues(alpha: 0.04);
    return const Color(0xFF1A1D27);
  }

  @override
  Widget build(BuildContext context) {
    final v = patient.latestConnectedVitals ?? patient.latestVitals;
    final severity = patient.overallSeverity;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: _severityBgTint(severity),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _severityBorderColor(severity)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────
                _Header(patient: patient, severity: severity),
                const SizedBox(height: 14),
                // ── Vitals row ───────────────────────────────────────────
                if (v != null) ...[
                  _VitalsRow(vitals: v),
                  const SizedBox(height: 12),
                  _StatusRow(vitals: v, patient: patient),
                ] else
                  _NoDataRow(),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: 60 * index), duration: 350.ms)
        .slideY(begin: 0.15, end: 0, duration: 350.ms, curve: Curves.easeOut);
  }
}

// ── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.patient, required this.severity});
  final AssignedPatient patient;
  final int severity;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1A73E8).withValues(alpha: 0.15),
            border: Border.all(
                color: const Color(0xFF1A73E8).withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(
              patient.fullName.isNotEmpty
                  ? patient.fullName.trim()[0].toUpperCase()
                  : '?',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A73E8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Name + IDs
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                patient.fullName.trim(),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'ID: ${patient.userId}  ·  Room ${patient.roomNo}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        // Connection + severity badge
        _ConnectionBadge(
            isConnected: patient.isConnected,
            isRemoved: patient.isRemoved,
            severity: severity),
      ],
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge(
      {required this.isConnected,
      required this.isRemoved,
      required this.severity});
  final bool isConnected;
  final bool isRemoved;
  final int severity;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (!isConnected) {
      color = const Color(0xFF4A4A5A);
      label = 'Disconnected';
    } else if (isRemoved) {
      color = const Color(0xFFE53935);
      label = 'Off-Wrist';
    } else {
      color = const Color(0xFF43A047);
      label = 'Connected';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          )
              .animate(onPlay: (c) => c.repeat())
              .scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1.2, 1.2),
                  duration: 900.ms),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vitals Row ────────────────────────────────────────────────────────────

class _VitalsRow extends StatelessWidget {
  const _VitalsRow({required this.vitals});
  final PatientVitalsSnapshot vitals;

  @override
  Widget build(BuildContext context) {
    final bpText = (vitals.bpSystolic > 0 || vitals.bpDiastolic > 0)
        ? '${vitals.bpSystolic}/${vitals.bpDiastolic}'
        : '--/--';

    return Row(
      children: [
        _VitalChip(
          icon: Icons.favorite_rounded,
          label: 'HR',
          value: vitals.heartRate > 0 ? '${vitals.heartRate}' : '--',
          unit: 'bpm',
          color: PatientMonitorCard._statusColor(vitals.heartRateStatus),
        ),
        const SizedBox(width: 8),
        _VitalChip(
          icon: Icons.water_drop_rounded,
          label: 'SpO₂',
          value: vitals.spo2 > 0 ? '${vitals.spo2.toStringAsFixed(0)}' : '--',
          unit: '%',
          color: PatientMonitorCard._statusColor(vitals.spo2Status),
        ),
        const SizedBox(width: 8),
        _VitalChip(
          icon: Icons.monitor_heart_rounded,
          label: 'BP',
          value: bpText,
          unit: 'mmHg',
          color: PatientMonitorCard._statusColor(vitals.bpStatus),
        ),
        const SizedBox(width: 8),
        _VitalChip(
          icon: Icons.thermostat_rounded,
          label: 'Temp',
          value: vitals.temp > 0 ? vitals.temp.toStringAsFixed(1) : '--',
          unit: '°C',
          color: PatientMonitorCard._statusColor(vitals.temperatureStatus),
        ),
      ],
    );
  }
}

class _VitalChip extends StatelessWidget {
  const _VitalChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 12),
                const SizedBox(width: 3),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              unit,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status footer row ────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.vitals, required this.patient});
  final PatientVitalsSnapshot vitals;
  final AssignedPatient patient;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Battery
        if (vitals.batteryPercent > 0) ...[
          Icon(Icons.battery_5_bar_rounded,
              color: Colors.white.withValues(alpha: 0.4), size: 14),
          const SizedBox(width: 3),
          Text(
            '${vitals.batteryPercent}%',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 12),
        ],
        // NEWS2
        if (patient.news2Score > 0) ...[
          Icon(Icons.warning_amber_rounded,
              color: const Color(0xFFFFA726), size: 14),
          const SizedBox(width: 3),
          Text(
            'NEWS2: ${patient.news2Score}',
            style: const TextStyle(color: Color(0xFFFFA726), fontSize: 11),
          ),
          const SizedBox(width: 12),
        ],
        // Stress
        if (vitals.stressLevel != 'N/A') ...[
          Icon(Icons.psychology_rounded,
              color: Colors.white.withValues(alpha: 0.35), size: 13),
          const SizedBox(width: 3),
          Text(
            vitals.stressLevel,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
          ),
        ],
        const Spacer(),
        // Device ID chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            vitals.deviceId.length > 12
                ? '…${vitals.deviceId.substring(vitals.deviceId.length - 12)}'
                : vitals.deviceId,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

class _NoDataRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.signal_wifi_off_rounded,
            color: Colors.white.withValues(alpha: 0.2), size: 16),
        const SizedBox(width: 8),
        Text(
          'No vitals data available',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
        ),
      ],
    );
  }
}
