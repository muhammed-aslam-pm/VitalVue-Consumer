import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/band_monitor_bloc.dart';
import '../../bloc/band_monitor_event.dart';
import '../../bloc/band_monitor_state.dart';

/// Bottom sheet for displaying BLE scan results and connecting to a device.
class DeviceScanSheet extends StatelessWidget {
  const DeviceScanSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D27),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'Nearby JStyle Devices',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Scanning for JCV5 / JStyle smartbands…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          BlocBuilder<BandMonitorBloc, BandMonitorState>(
            builder: (context, state) {
              if (state is BandScanningState && state.results.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(
                            color: Color(0xFF1A73E8)),
                        const SizedBox(height: 16),
                        Text(
                          'Looking for devices…',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final results = state is BandScanningState ? state.results : [];

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: results.length,
                separatorBuilder: (_, __) => Divider(
                  color: Colors.white.withValues(alpha: 0.08),
                  height: 1,
                ),
                itemBuilder: (context, i) {
                  final r = results[i] as ScanResult;
                  final name = r.device.platformName.isNotEmpty
                      ? r.device.platformName
                      : 'Unknown Device';
                  final rssi = r.rssi;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 0, vertical: 4),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A73E8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.watch_rounded,
                          color: Color(0xFF1A73E8), size: 22),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      '${r.device.remoteId.str}  •  $rssi dBm',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                    trailing: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1A73E8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        context
                            .read<BandMonitorBloc>()
                            .add(ConnectToBand(r.device));
                      },
                      child: const Text('Connect',
                          style: TextStyle(fontSize: 13)),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: (i * 60).ms, duration: 300.ms)
                      .slideX(begin: 0.1, end: 0);
                },
              );
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                context.read<BandMonitorBloc>().add(const StopScan());
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}
