import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/patients_bloc.dart';
import '../../bloc/patients_event.dart';
import '../../cloud/assigned_patient.dart';
import '../../cloud/sse_events.dart';
import '../../cloud/patients_repository.dart';
import 'action_capture_dialog.dart';

class CriticalAlertDialog extends StatefulWidget {
  const CriticalAlertDialog({
    super.key,
    required this.alert,
    required this.patient,
    required this.onDismiss,
  });

  final SseCriticalAlertEvent alert;
  final AssignedPatient? patient; // null if patient not yet in list
  final VoidCallback onDismiss;

  @override
  State<CriticalAlertDialog> createState() => _CriticalAlertDialogState();
}

class _CriticalAlertDialogState extends State<CriticalAlertDialog> {
  bool _isLoading = false;

  Color get _severityColor {
    switch (widget.alert.severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFE53935);
      case 'warning':
        return const Color(0xFFFFA726);
      default:
        return const Color(0xFFE53935);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vitals = widget.patient?.latestVitals;
    final color = _severityColor;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141620),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.25),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                border: Border(
                    bottom: BorderSide(
                        color: color.withValues(alpha: 0.3), width: 1)),
              ),
              child: Column(
                children: [
                  Icon(Icons.warning_amber_rounded, color: color, size: 36)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                          begin: const Offset(0.9, 0.9),
                          end: const Offset(1.1, 1.1),
                          duration: 700.ms),
                  const SizedBox(height: 8),
                  Text(
                    'VITAL ALERT',
                    style: GoogleFonts.inter(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Patient name
                  Text(
                    widget.patient?.fullName ?? 'Patient #${widget.alert.patientId}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Ward / Room pills
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Pill(
                        label: 'Ward: ${widget.alert.wardName}',
                        color: const Color(0xFF1A73E8),
                      ),
                      const SizedBox(width: 8),
                      _Pill(
                        label: 'Room No: ${widget.alert.roomNumber}',
                        color: const Color(0xFF7C4DFF),
                      ),
                    ],
                  ),

                  if (widget.alert.phoneNumber.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.phone_rounded,
                            color: Colors.white.withValues(alpha: 0.4),
                            size: 14),
                        const SizedBox(width: 6),
                        Text(
                          widget.alert.phoneNumber,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Triggered alert
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '● TRIGGERED ALERT',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              widget.alert.vitalType,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              widget.alert.triggeredValue,
                              style: TextStyle(
                                color: color,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Current vitals (from liveVitals if available)
                  if (vitals != null) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'CURRENT VITALS',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _VitalsGrid(vitals: vitals),
                  ],

                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _handleSnooze,
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Colors.white.withValues(alpha: 0.6),
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.2)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('SNOOZE',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleTakeAction,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: color.withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('TAKE ACTION',
                                  style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .scale(
            begin: const Offset(0.8, 0.8),
            end: const Offset(1, 1),
            duration: 300.ms,
            curve: Curves.easeOutBack)
        .fadeIn(duration: 200.ms);
  }

  Future<void> _handleSnooze() async {
    setState(() => _isLoading = true);
    try {
      await context.read<PatientsRepository>().snoozeAlert(
            patientId: widget.alert.patientId,
            alertId: widget.alert.alertId,
          );
      if (mounted) widget.onDismiss();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to snooze: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleTakeAction() async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => const ActionCaptureDialog(),
    );
    if (action != null && mounted) {
      setState(() => _isLoading = true);
      try {
        await context.read<PatientsRepository>().takeAction(
              patientId: widget.alert.patientId,
              alertId: widget.alert.alertId,
              actionType: action.startsWith('Other: ') ? 'Other Action' : action,
              otherDetails: action.startsWith('Other: ') ? action.substring(7) : '',
              performedAt: DateTime.now(),
            );
        if (mounted) widget.onDismiss();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to record action: $e')),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _VitalsGrid extends StatelessWidget {
  const _VitalsGrid({required this.vitals});
  final PatientVitalsSnapshot vitals;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _VitalBox(
            label: 'Heart Rate',
            value: vitals.heartRate > 0 ? '${vitals.heartRate}' : '--',
            unit: 'bpm',
            status: vitals.heartRateStatus,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _VitalBox(
            label: 'SpO2',
            value: vitals.spo2 > 0 ? '${vitals.spo2.toStringAsFixed(0)}' : '--',
            unit: '%',
            status: vitals.spo2Status,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _VitalBox(
            label: 'Blood Pressure',
            value: (vitals.bpSystolic > 0 || vitals.bpDiastolic > 0)
                ? '${vitals.bpSystolic}/${vitals.bpDiastolic}'
                : '--/--',
            unit: 'mmHg',
            status: vitals.bpStatus,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _VitalBox(
            label: 'Temperature',
            value: vitals.temp > 0 ? vitals.temp.toStringAsFixed(1) : '--',
            unit: '°C',
            status: vitals.temperatureStatus,
          ),
        ),
      ],
    );
  }
}

class _VitalBox extends StatelessWidget {
  const _VitalBox({
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
  });
  final String label;
  final String value;
  final String unit;
  final String status;

  Color get _color {
    switch (status) {
      case 'Critical':
        return const Color(0xFFE53935);
      case 'Warning':
        return const Color(0xFFFFA726);
      default:
        return const Color(0xFF43A047);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: _color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}
