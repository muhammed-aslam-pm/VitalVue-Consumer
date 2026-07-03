import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE transport layer — Dart translation of Python ble_transport.py.
///
/// Wraps flutter_blue_plus.
/// GATT: service fff0, write fff6 (write-without-response), notify fff7.
class BandBleClient {
  BandBleClient();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;

  // Public stream that delivers decoded notification bytes to the session.
  final _notifyController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get notifyStream => _notifyController.stream;

  Stream<BluetoothConnectionState> get connectionStateStream =>
      _device?.connectionState ?? const Stream.empty();

  bool get isConnected =>
      _device != null &&
      _device!.isConnected;

  /// Scan for nearby JStyle devices.
  /// Returns once [timeout] elapses or the caller cancels the subscription.
  static Stream<ScanResult> scan({Duration timeout = const Duration(seconds: 10)}) {
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults
        .expand((results) => results)
        .where((r) {
          final name = (r.device.platformName).toLowerCase();
          return name.contains('jcv5') ||
              name.contains('jstyle') ||
              r.advertisementData.serviceUuids.any(
                  (u) => u.toString().toLowerCase().contains('fff0'));
        });
  }

  static Future<void> stopScan() => FlutterBluePlus.stopScan();

  /// Connect to [device] and subscribe to the fff7 notify characteristic.
  Future<bool> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
    if (!device.isConnected) return false;

    // Discover services.
    final services = await device.discoverServices();
    for (final svc in services) {
      if (svc.serviceUuid.toString().toLowerCase().contains('fff0')) {
        for (final char in svc.characteristics) {
          final uuid = char.characteristicUuid.toString().toLowerCase();
          if (uuid.contains('fff6')) _writeChar = char;
          if (uuid.contains('fff7')) _notifyChar = char;
        }
      }
    }

    if (_writeChar == null || _notifyChar == null) {
      await device.disconnect();
      return false;
    }

    // Subscribe to notifications — mirrors Python: client.start_notify(NOTIFY_CHAR, _cb)
    await _notifyChar!.setNotifyValue(true);
    _notifySub = _notifyChar!.lastValueStream.listen((raw) {
      if (raw.isNotEmpty) {
        _notifyController.add(Uint8List.fromList(raw));
      }
    });

    return true;
  }

  /// Write [data] to fff6 without waiting for a response.
  /// Matches Python: write_gatt_char(WRITE_CHAR, data, response=False)
  Future<void> write(Uint8List data) async {
    if (_writeChar == null) throw StateError('Not connected — no write char');
    await _writeChar!.write(data, withoutResponse: true);
  }

  /// Disconnect and release all resources.
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    _writeChar = null;
    _notifyChar = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
  }

  void dispose() {
    _notifyController.close();
  }
}
