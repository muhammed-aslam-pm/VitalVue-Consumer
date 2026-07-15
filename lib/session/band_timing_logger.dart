import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Writes band timing events to a CSV file for offline analysis.
///
/// Usage:
///   final logger = BandTimingLogger(deviceId: 'jband-dev-01');
///   await logger.open();
///   logger.log('first_hr', sinceConnectMs: 1095, intervalMs: null, hr: 72);
///   ...
///   await logger.close();
///
/// Pull from device:
///   adb shell "ls /sdcard/Android/data/com.jband.jband_monitor/files/timing/"
///   adb pull /sdcard/Android/data/com.jband.jband_monitor/files/timing/
class BandTimingLogger {
  BandTimingLogger({required this.deviceId});

  final String deviceId;
  IOSink? _sink;
  String? _filePath;

  static const _header =
      'timestamp_ms,event,device_id,since_connect_ms,interval_ms,hr,spo2,temp_c,note\n';

  Future<void> open() async {
    try {
      final dir = await _timingDir();
      final now = DateTime.now();
      final stamp =
          '${now.year}${_p(now.month)}${_p(now.day)}_${_p(now.hour)}${_p(now.minute)}${_p(now.second)}';
      final file = File(p.join(dir.path, '${deviceId}_$stamp.csv'));
      _filePath = file.path;
      _sink = file.openWrite();
      _sink!.write(_header);
      debugPrint('[BandTimingLogger] Writing timing data to: $_filePath');
    } catch (e) {
      debugPrint('[BandTimingLogger] Failed to open log file: $e');
    }
  }

  /// Log a timing event.
  ///
  /// [event] — short identifier e.g. 'connected', 'first_hr', 'vitals_interval', 'first_bp', 'first_battery'
  void log(
    String event, {
    required int sinceConnectMs,
    required int? intervalMs,
    int hr = 0,
    int spo2 = 0,
    double tempC = 0.0,
    String note = '',
  }) {
    if (_sink == null) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final row =
        '$ts,$event,$deviceId,$sinceConnectMs,${intervalMs ?? ''},$hr,$spo2,$tempC,$note\n';
    _sink!.write(row);
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    if (_filePath != null) {
      debugPrint('[BandTimingLogger] Log closed: $_filePath');
      debugPrint(
          '[BandTimingLogger] Pull with:\n'
          '  adb pull /sdcard/Android/data/com.jband.jband_monitor/files/timing/');
    }
  }

  static Future<Directory> _timingDir() async {
    final base = await getExternalStorageDirectory();
    final dir = Directory(p.join(base!.path, 'timing'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _p(int n) => n.toString().padLeft(2, '0');

  /// Convenience: pull the timing directory path for display.
  static Future<String> timingDirPath() async {
    final d = await _timingDir();
    return d.path;
  }
}
