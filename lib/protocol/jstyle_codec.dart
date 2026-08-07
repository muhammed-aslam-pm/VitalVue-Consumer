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
const cmdGetHeartData = 0x54; // HR history
const cmdGetOxygenData = 0x66; // SpO2 history
const cmdReadTempHistory = 0x62; // Temp history

// ── Measurement sub-types ─────────────────────────────────────────────────────
const measHr = 0x02;
const measSpo2 = 0x03;
const measHrv = 0x01;

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
  HistorySteps(super.timestamp,
      {required this.steps, required this.calories, required this.distanceKm});
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

/// One background HRV/BP measurement stored in the band's flash.
/// Parsed from CMD_Get_HrvTestData (0x56) response — 15 bytes per record.
/// Fields match SDK's ResolveUtil.getHrvTestData() exactly.
class HistoryBpHrv extends HistoryRecord {
  final int hrv;
  final int vascularAging;
  final int hr;
  final int stress;
  final int systolic;
  final int diastolic;

  HistoryBpHrv(
    super.timestamp, {
    required this.hrv,
    required this.vascularAging,
    required this.hr,
    required this.stress,
    required this.systolic,
    required this.diastolic,
  });
}

// ── Parsed event types ────────────────────────────────────────────────────────

sealed class BandEvent {}

class RealtimeEvent extends BandEvent {
  final RealtimeData data;
  RealtimeEvent(this.data);
}

class BatteryEvent extends BandEvent {
  final int percent;
  BatteryEvent(this.percent);
}

class HistoryDataEvent extends BandEvent {
  final int cmd;
  final List<HistoryRecord> records;
  final bool isEnd;
  HistoryDataEvent(
      {required this.cmd, required this.records, required this.isEnd});
}

class UnknownEvent extends BandEvent {
  final int dataType;
  final String raw;
  UnknownEvent({required this.dataType, required this.raw});
}

class ManualMeasurementEvent extends BandEvent {
  final int type; // 1=HRV, 2=HR, 3=SpO2
  final int hr;
  final int spo2;
  final int hrv;
  final int stress;
  final int systolic;
  final int diastolic;

  ManualMeasurementEvent({
    required this.type,
    required this.hr,
    required this.spo2,
    required this.hrv,
    required this.stress,
    required this.systolic,
    required this.diastolic,
  });
}

// ── Main codec class ──────────────────────────────────────────────────────────

class JStyleCodec {
  // ── Command builders ───────────────────────────────────────────────────────

  /// Sync device clock using BCD-encoded fields. Matches Python set_device_time().
  Uint8List setDeviceTime([DateTime? when]) {
    final t = when ?? DateTime.now();
    return frame(
        cmdSetTime,
        Uint8List.fromList([
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
    return frame(
        cmdSetUserinfo,
        Uint8List.fromList([
          info.sex & 0xFF,
          info.age & 0xFF,
          info.heightCm & 0xFF,
          info.weightKg & 0xFF,
          info.stepLengthCm & 0xFF,
        ]));
  }

  /// Enable/disable real-time HR + step + temperature streaming.
  Uint8List realTimeStep({bool enable = true, bool tempEnable = true}) {
    return frame(
        cmdEnableActivity,
        Uint8List.fromList([
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

  /// Configure the band's internal automatic background monitoring.
  /// [kind]: 1=HR, 2=SpO2, 3=Temp, 4=HRV. [intervalMins] interval in minutes.
  /// [mode]: 0=disable, 1=enable full period, 2=interval measurement (default: 2 when enable=true)
  Uint8List setAutoMeasurement(int kind, int intervalMins,
      {required bool enable, int mode = 2}) {
    final p = Uint8List(9);
    p[0] = enable ? mode : 0x00; // workMode: 2 = interval measurement
    p[1] = 0; // startHour (00:00)
    p[2] = 0; // startMin
    p[3] = 23; // endHour (23:59)
    p[4] = 59; // endMin
    p[5] = 0x7F; // week (all days)
    p[6] = intervalMins & 0xFF; // time LSB
    p[7] = (intervalMins >> 8) & 0xFF; // time MSB
    p[8] = kind; // type: 1=HR, 2=SpO2, 3=Temp, 4=HRV
    return frame(cmdSetAuto, p);
  }

  Uint8List getBattery() => frame(cmdGetBattery);
  Uint8List getVersion() => frame(cmdGetVersion);
  Uint8List mcuReset() => frame(cmdMcuReset);

  /// Fetch BP/HRV history from the band's flash storage.
  ///
  /// [mode] follows the same protocol as every other history command:
  ///   0x00 = start fresh (read from most recent)
  ///   0x02 = continue reading (when data count == 50 and not yet end)
  ///   0x99 = delete all HRV history
  ///
  /// Matches SDK BleSDK.GetHRVDataWithMode().
  Uint8List getBpHrvDataWithMode(int mode) {
    return frame(cmdGetHrvData, Uint8List.fromList([mode & 0xFF]));
  }

  /// Convenience wrapper: start a fresh BP/HRV history fetch.
  Uint8List getBpHrvData() => getBpHrvDataWithMode(0x00);

  /// Fetch Historical Data (0x00 mode reads all)
  Uint8List getHistorySteps() =>
      frame(cmdGetDetailData, Uint8List.fromList([0x00]));
  Uint8List getHistoryHeartRate() =>
      frame(cmdGetHeartData, Uint8List.fromList([0x00]));
  Uint8List getHistorySpo2() =>
      frame(cmdGetOxygenData, Uint8List.fromList([0x00]));
  Uint8List getHistoryTemp() =>
      frame(cmdReadTempHistory, Uint8List.fromList([0x00]));

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

    // ── BP / HRV history (0x56 CMD_Get_HrvTestData) ─────────────────────────
    // Packet format (SDK ResolveUtil.getHrvTestData):
    //   [0]        = 0x56  (cmd echo)
    //   [1]        = mode echo
    //   [2]        = reserved
    //   [3+i*15]   = year  (BCD)
    //   [4+i*15]   = month (BCD)
    //   [5+i*15]   = day   (BCD)
    //   [6+i*15]   = hour  (BCD)
    //   [7+i*15]   = minute(BCD)
    //   [8+i*15]   = second(BCD)
    //   [9+i*15]   = HRV
    //   [10+i*15]  = VascularAging
    //   [11+i*15]  = HeartRate
    //   [12+i*15]  = Stress (fatigue/tired)
    //   [13+i*15]  = highBP (systolic)
    //   [14+i*15]  = lowBP  (diastolic)
    //   [last]     = 0xFF when this is the last packet in the sequence
    if (dt == cmdGetHrvData) {
      final records = <HistoryRecord>[];
      const count = 15;
      final size = value.length ~/ count;

      if (size == 0) {
        return HistoryDataEvent(cmd: dt, records: records, isEnd: true);
      }

      final isEnd = value[value.length - 1] == 0xFF;

      for (int i = 0; i < size; i++) {
        try {
          final year = 2000 + _bcdDecode(value[3 + i * count]);
          final month = _bcdDecode(value[4 + i * count]);
          final day = _bcdDecode(value[5 + i * count]);
          final hour = _bcdDecode(value[6 + i * count]);
          final minute = _bcdDecode(value[7 + i * count]);
          final second = _bcdDecode(value[8 + i * count]);

          final hrv = value[9 + i * count] & 0xFF;
          final vascularAging = value[10 + i * count] & 0xFF;
          final hr = value[11 + i * count] & 0xFF;
          final stress = value[12 + i * count] & 0xFF;
          final systolic = value[13 + i * count] & 0xFF;
          final diastolic = value[14 + i * count] & 0xFF;

          // Skip all-zero records (band memory not yet written)
          if (systolic == 0 && diastolic == 0 && hrv == 0) continue;

          final ts = DateTime(year, month, day, hour, minute, second);
          records.add(HistoryBpHrv(
            ts,
            hrv: hrv,
            vascularAging: vascularAging,
            hr: hr,
            stress: stress,
            systolic: systolic,
            diastolic: diastolic,
          ));
        } catch (_) {}
      }

      return HistoryDataEvent(cmd: dt, records: records, isEnd: isEnd);
    }

    if (dt == cmdGetBattery) {
      final pct = value.length > 1 ? value[1] : -1;
      return BatteryEvent(pct);
    }

    // Historical SpO2 (0x66 CMD_Get_OxygenData OR 0xAB CMD_Get_Auto)
    if (dt == cmdGetOxygenData || dt == 0xAB) {
      final records = <HistoryRecord>[];
      const count = 10;
      final size = value.length ~/ count;
      if (size == 0) {
        return HistoryDataEvent(cmd: dt, records: records, isEnd: true);
      }
      final isEnd = value.isNotEmpty && value[value.length - 1] == 0xFF;
      for (int i = 0; i < size; i++) {
        try {
          final year = 2000 + _bcdDecode(value[3 + i * count]);
          final month = _bcdDecode(value[4 + i * count]);
          final day = _bcdDecode(value[5 + i * count]);
          final hour = _bcdDecode(value[6 + i * count]);
          final minute = _bcdDecode(value[7 + i * count]);
          final second = _bcdDecode(value[8 + i * count]);
          var spo2 = value[9 + i * count] & 0xFF;
          if (spo2 == 0 && value.length > 13 + i * count) {
            final fallback = value[13 + i * count] & 0xFF;
            if (fallback >= 50 && fallback <= 100) {
              spo2 = fallback;
            }
          }
          if (spo2 > 0) {
            records.add(HistorySpo2(
              DateTime(year, month, day, hour, minute, second),
              spo2,
            ));
          }
        } catch (_) {}
      }
      return HistoryDataEvent(cmd: dt, records: records, isEnd: isEnd);
    }

    // Historical HR
    if (dt == cmdGetHeartData) {
      const records = <HistoryRecord>[];
      const count = 24;
      final size = value.length ~/ count;
      bool isEnd = false;
      if (size == 0) {
        return HistoryDataEvent(cmd: dt, records: records, isEnd: true);
      }

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
      const records = <HistoryRecord>[];
      const count = 25;
      final size = value.length ~/ count;
      bool isEnd = false;
      if (size == 0) {
        return HistoryDataEvent(cmd: dt, records: records, isEnd: true);
      }

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
            records.add(HistorySteps(baseTime,
                steps: steps, calories: cal, distanceKm: dist));
          }
        } catch (_) {}
      }
      return HistoryDataEvent(cmd: dt, records: records, isEnd: isEnd);
    }

    // Manual/active measurements (0x28)
    if (dt == cmdMeasurementWithType) {
      if (value.length > 7) {
        final type = value[1] & 0xFF;
        final hr = value[2] & 0xFF;
        final spo2 = value[3] & 0xFF;
        final hrv = value[4] & 0xFF;
        final stress = value[5] & 0xFF;
        final sys = value[6] & 0xFF;
        final dia = value[7] & 0xFF;

        if (hr > 0 || spo2 > 0 || hrv > 0 || stress > 0 || sys > 0 || dia > 0) {
          return ManualMeasurementEvent(
            type: type,
            hr: hr,
            spo2: spo2,
            hrv: hrv,
            stress: stress,
            systolic: sys,
            diastolic: dia,
          );
        }
      }
    }

    return UnknownEvent(dataType: dt, raw: _hex(value));
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Port of ResolveUtil.getActivityData — realtime HR/SpO2/temp/steps packet.
  static RealtimeData _parseRealtime(Uint8List raw) {
    // Pad to at least 25 bytes to safely index all fields.
    final Uint8List value =
        raw.length < 25 ? (Uint8List(25)..setRange(0, raw.length, raw)) : raw;

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
