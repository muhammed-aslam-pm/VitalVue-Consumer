/// JStyle JCV5 protocol codec — Dart port of the Python jstyle_codec.py.
///
/// Pure bytes in / bytes out. No BLE, no globals — instance-safe.
///
/// Framing (verified against Java SDK BleSDK.java):
///   command packet = 16 bytes: [cmd][payload 14 bytes][crc]
///   crc = sum(bytes[0..14]) & 0xFF
///   time fields BCD: int.parse(value.toString(), radix: 16)
///   getValue(b, n) = (b & 0xFF) << (8*n)  → little-endian byte assembly
///
/// GATT: service fff0, write fff6 (no-response), notify fff7.
library;

import 'dart:typed_data';

// ── GATT UUIDs ────────────────────────────────────────────────────────────────
const kServiceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
const kWriteCharUuid = '0000fff6-0000-1000-8000-00805f9b34fb';
const kNotifyCharUuid = '0000fff7-0000-1000-8000-00805f9b34fb';

// ── Command bytes (DeviceConst.java) ──────────────────────────────────────────
const cmdSetTime = 0x01;
const cmdSetUserinfo = 0x02;
const cmdEnableActivity = 0x09; // RealTimeStep
const cmdGetBattery = 0x13;
const cmdGetVersion = 0x27;
const cmdMeasurementWithType = 0x28;
const cmdSetAuto = 0x2A;
const cmdMcuReset = 0x2E;
const cmdHeartPackage = 0x17; // realtime push (a)
const cmdHeartPackageFromDev = 0x18; // realtime push (b)
const cmdGetHrvData = 0x56; // BP / HRV

const cmdGetTotalData = 0x51;
const cmdGetDetailData = 0x52; // Steps history
const cmdGetHeartData = 0x54;  // HR history
const cmdGetOxygenData = 0x66; // SpO2 history
const cmdReadTempHistory = 0x62; // Temp history

// ── Measurement sub-types ─────────────────────────────────────────────────────
const measHr = 0x02;
const measSpo2 = 0x03;

const _packetLen = 16;

// ── Framing primitives ────────────────────────────────────────────────────────

/// CRC = sum of first 15 bytes, masked to 8 bits. Matches Python crc().
int _crc(Uint8List buf) {
  var s = 0;
  for (var i = 0; i < _packetLen - 1; i++) {
    s += buf[i];
  }
  return s & 0xFF;
}

/// BCD encode — matches Python bcd(): int.parse(str(v), base=16).
int _bcdEncode(int v) => int.parse(v.toString(), radix: 16);

/// BCD decode — properly convert BCD byte back to integer
int _bcdDecode(int v) => int.parse(v.toRadixString(16));

/// Little-endian byte assembly — matches Python gv(): (b & 0xFF) << (8*shift).
int gv(int b, int shift) => (b & 0xFF) << (8 * shift);

/// Sum value[start:end] little-endian. Matches Python le_sum().
int leSum(Uint8List value, int start, int end) {
  var result = 0;
  for (var i = start; i < end; i++) {
    result += gv(value[i], i - start);
  }
  return result;
}

/// Build a 16-byte packet with CRC at position 15.
Uint8List frame(int cmd, [Uint8List? payload]) {
  final p = payload ?? Uint8List(0);
  assert(p.length <= _packetLen - 2, 'payload too long for 16-byte packet');
  final buf = Uint8List(_packetLen);
  buf[0] = cmd & 0xFF;
  for (var i = 0; i < p.length; i++) {
    buf[1 + i] = p[i];
  }
  buf[_packetLen - 1] = _crc(buf);
  return buf;
}

// ── Data classes ──────────────────────────────────────────────────────────────

class PersonalInfo {
  final int sex; // 1 = male, 0 = female
  final int age;
  final int heightCm;
  final int weightKg;
  final int stepLengthCm;

  const PersonalInfo({
    this.sex = 1,
    this.age = 30,
    this.heightCm = 175,
    this.weightKg = 70,
    this.stepLengthCm = 70,
  });
}

class RealtimeData {
  final int hr;
  final int spo2;
  final double tempC;
  final int steps;
  final double calories;
  final double distanceKm;
  final String raw;

  const RealtimeData({
    required this.hr,
    required this.spo2,
    required this.tempC,
    required this.steps,
    required this.calories,
    required this.distanceKm,
    required this.raw,
  });
}

// ── History Data classes ──────────────────────────────────────────────────────

class HistoryRecord {
  final DateTime timestamp;
  HistoryRecord(this.timestamp);
}

class HistorySteps extends HistoryRecord {
  final int steps;
  final double calories;
  final double distanceKm;
  HistorySteps(super.timestamp, {required this.steps, required this.calories, required this.distanceKm});
}

class HistoryHr extends HistoryRecord {
  final int hr;
  HistoryHr(super.timestamp, this.hr);
}

class HistorySpo2 extends HistoryRecord {
  final int spo2;
  HistorySpo2(super.timestamp, this.spo2);
}

class HistoryTemp extends HistoryRecord {
  final double tempC;
  HistoryTemp(super.timestamp, this.tempC);
}

// ── Parsed event types ────────────────────────────────────────────────────────

sealed class BandEvent {}

class RealtimeEvent extends BandEvent {
  final RealtimeData data;
  RealtimeEvent(this.data);
}

class BpResultEvent extends BandEvent {
  final int systolic;
  final int diastolic;
  final int hrv;
  final int stress;
  BpResultEvent({
    required this.systolic,
    required this.diastolic,
    required this.hrv,
    required this.stress,
  });
}

class BpNoDataEvent extends BandEvent {}

class BatteryEvent extends BandEvent {
  final int percent;
  BatteryEvent(this.percent);
}

class HistoryDataEvent extends BandEvent {
  final int cmd;
  final List<HistoryRecord> records;
  final bool isEnd;
  HistoryDataEvent({required this.cmd, required this.records, required this.isEnd});
}

class UnknownEvent extends BandEvent {
  final int dataType;
  final String raw;
  UnknownEvent({required this.dataType, required this.raw});
}

// ── Main codec class ──────────────────────────────────────────────────────────

class JStyleCodec {
  // ── Command builders ───────────────────────────────────────────────────────

  /// Sync device clock using BCD-encoded fields. Matches Python set_device_time().
  Uint8List setDeviceTime([DateTime? when]) {
    final t = when ?? DateTime.now();
    return frame(cmdSetTime, Uint8List.fromList([
      _bcdEncode(t.year % 100),
      _bcdEncode(t.month),
      _bcdEncode(t.day),
      _bcdEncode(t.hour),
      _bcdEncode(t.minute),
      _bcdEncode(t.second),
      0,
      _timezoneByte(),
    ]));
  }

  /// Write user biometrics so the band can compute calories/distance.
  Uint8List setPersonalInfo(PersonalInfo info) {
    return frame(cmdSetUserinfo, Uint8List.fromList([
      info.sex & 0xFF,
      info.age & 0xFF,
      info.heightCm & 0xFF,
      info.weightKg & 0xFF,
      info.stepLengthCm & 0xFF,
    ]));
  }

  /// Enable/disable real-time HR + step + temperature streaming.
  Uint8List realTimeStep({bool enable = true, bool tempEnable = true}) {
    return frame(cmdEnableActivity, Uint8List.fromList([
      enable ? 1 : 0,
      tempEnable ? 1 : 0,
    ]));
  }

  /// HR kickstart or SpO2 spot-check. kind = measHr | measSpo2.
  /// Matches Python set_measurement().
  Uint8List setMeasurement(int kind, int seconds, {required bool open}) {
    final p = Uint8List(5);
    p[0] = kind; // value[1] in frame
    p[1] = open ? 0x01 : 0x00; // value[2]
    // p[2] unused
    p[3] = seconds & 0xFF; // value[4] LSB
    p[4] = (seconds >> 8) & 0xFF; // value[5] MSB
    return frame(cmdMeasurementWithType, p);
  }

  Uint8List getBattery() => frame(cmdGetBattery);
  Uint8List getVersion() => frame(cmdGetVersion);
  Uint8List mcuReset() => frame(cmdMcuReset);

  /// Trigger HRV / Blood Pressure calculation. Matches Python get_bp_hrv_data().
  Uint8List getBpHrvData() => frame(cmdGetHrvData);

  /// Fetch Historical Data (0x00 mode reads all)
  Uint8List getHistorySteps() => frame(cmdGetDetailData, Uint8List.fromList([0x00]));
  Uint8List getHistoryHeartRate() => frame(cmdGetHeartData, Uint8List.fromList([0x00]));
  Uint8List getHistorySpo2() => frame(cmdGetOxygenData, Uint8List.fromList([0x00]));
  Uint8List getHistoryTemp() => frame(cmdReadTempHistory, Uint8List.fromList([0x00]));

  // ── Parser ─────────────────────────────────────────────────────────────────

  /// Dispatch incoming GATT notification bytes to a typed [BandEvent].
  /// Matches Python JStyleCodec.parse().
  BandEvent? parse(Uint8List value) {
    if (value.isEmpty) return null;
    final dt = value[0];

    if (dt == cmdHeartPackage ||
        dt == cmdHeartPackageFromDev ||
        dt == cmdEnableActivity) {
      return RealtimeEvent(_parseRealtime(value));
    }

    if (dt == cmdGetHrvData) {
      if (value.length < 15) return BpNoDataEvent();
      final sys = value[13] & 0xFF;
      final dia = value[14] & 0xFF;
      final hrv = value[9] & 0xFF;
      final stress = value[12] & 0xFF;
      if (sys == 0 && dia == 0 && hrv == 0) return BpNoDataEvent();
      return BpResultEvent(
        systolic: sys,
        diastolic: dia,
        hrv: hrv,
        stress: stress,
      );
    }

    if (dt == cmdGetBattery) {
      final pct = value.length > 1 ? value[1] : -1;
      return BatteryEvent(pct);
    }

    // Historical HR
    if (dt == cmdGetHeartData) {
      final records = <HistoryRecord>[];
      final count = 24;
      final size = value.length ~/ count;
      bool isEnd = false;
      if (size == 0) return HistoryDataEvent(cmd: dt, records: records, isEnd: true);
      
      for (int i = 0; i < size; i++) {
        int offset = i * count;
        if (value.isNotEmpty && value[value.length - 1] == 0xff) isEnd = true;
        
        try {
          final year = 2000 + _bcdDecode(value[offset + 3]);
          final month = _bcdDecode(value[offset + 4]);
          final day = _bcdDecode(value[offset + 5]);
          final hour = _bcdDecode(value[offset + 6]);
          final minute = _bcdDecode(value[offset + 7]);
          final second = _bcdDecode(value[offset + 8]);
          final baseTime = DateTime(year, month, day, hour, minute, second);
          
          for (int j = 0; j < 15; j++) {
            int hr = value[offset + 9 + j] & 0xFF;
            if (hr > 0) {
              records.add(HistoryHr(baseTime.add(Duration(minutes: j)), hr));
            }
          }
        } catch (_) {}
      }
      return HistoryDataEvent(cmd: dt, records: records, isEnd: isEnd);
    }

    // Historical Steps
    if (dt == cmdGetDetailData) {
      final records = <HistoryRecord>[];
      final count = 25;
      final size = value.length ~/ count;
      bool isEnd = false;
      if (size == 0) return HistoryDataEvent(cmd: dt, records: records, isEnd: true);
      
      for (int i = 0; i < size; i++) {
        int offset = i * count;
        if (value.isNotEmpty && value[value.length - 1] == 0xff) isEnd = true;
        
        try {
          final year = 2000 + _bcdDecode(value[offset + 3]);
          final month = _bcdDecode(value[offset + 4]);
          final day = _bcdDecode(value[offset + 5]);
          final hour = _bcdDecode(value[offset + 6]);
          final minute = _bcdDecode(value[offset + 7]);
          final second = _bcdDecode(value[offset + 8]);
          final baseTime = DateTime(year, month, day, hour, minute, second);
          
          int steps = leSum(value, offset + 9, offset + 11);
          double cal = leSum(value, offset + 11, offset + 13) / 100.0;
          double dist = leSum(value, offset + 13, offset + 15) / 100.0;
          
          if (steps > 0 || cal > 0 || dist > 0) {
            records.add(HistorySteps(baseTime, steps: steps, calories: cal, distanceKm: dist));
          }
        } catch (_) {}
      }
      return HistoryDataEvent(cmd: dt, records: records, isEnd: isEnd);
    }

    return UnknownEvent(dataType: dt, raw: _hex(value));
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Port of ResolveUtil.getActivityData — realtime HR/SpO2/temp/steps packet.
  static RealtimeData _parseRealtime(Uint8List raw) {
    // Pad to at least 25 bytes to safely index all fields.
    final Uint8List value = raw.length < 25
        ? (Uint8List(25)..setRange(0, raw.length, raw))
        : raw;

    final steps = leSum(value, 1, 5);
    final cal = leSum(value, 5, 9) / 100.0;
    final dist = leSum(value, 9, 13) / 100.0;
    final hr = gv(value[21], 0);
    // temp: 16-bit little-endian at bytes 22-23, scaled by 0.1
    final tempRaw = gv(value[22], 0) + gv(value[23], 1);
    final temp = double.parse((tempRaw * 0.1).toStringAsFixed(1));
    final spo2 = gv(value[24], 0);

    return RealtimeData(
      hr: hr,
      spo2: spo2,
      tempC: temp,
      steps: steps,
      calories: double.parse(cal.toStringAsFixed(1)),
      distanceKm: double.parse((dist / 100.0).toStringAsFixed(2)),
      raw: _hex(raw),
    );
  }

  static String _hex(Uint8List b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  /// UTC offset byte — matches Python _timezone_byte() logic.
  static int _timezoneByte() {
    final offMin = DateTime.now().timeZoneOffset.inMinutes;
    final offH = offMin ~/ 60;
    return offH >= 0 ? (offH + 0x80) : (offH.abs() & 0xFF);
  }
}
