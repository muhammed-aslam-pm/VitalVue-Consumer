import 'dart:async';

import 'package:flutter/foundation.dart';
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

  /// Helper to test if a scan result matches JStyle / JCV smartband criteria.
  static bool isJStyleDevice(ScanResult r, {bool showAll = false}) {
    if (showAll) return true;
    final platformName = r.device.platformName.toLowerCase();
    final advName = r.advertisementData.advName.toLowerCase();

    // Check name against known JStyle model prefixes and generic smartband keywords
    final isNameMatch = platformName.contains('jcv') ||
        platformName.contains('jstyle') ||
        platformName.contains('v19') ||
        platformName.contains('jc') ||
        platformName.contains('2025') ||
        platformName.contains('1963') ||
        platformName.contains('1908') ||
        platformName.contains('1790') ||
        platformName.contains('smart') ||
        platformName.contains('band') ||
        platformName.contains('watch') ||
        advName.contains('jcv') ||
        advName.contains('jstyle') ||
        advName.contains('v19') ||
        advName.contains('jc') ||
        advName.contains('2025') ||
        advName.contains('1963') ||
        advName.contains('1908') ||
        advName.contains('1790') ||
        advName.contains('smart') ||
        advName.contains('band') ||
        advName.contains('watch');

    // Check 16-bit or 128-bit FFF0 service UUID in adv payload
    final isUuidMatch = r.advertisementData.serviceUuids.any((u) {
      final str = u.toString().toLowerCase();
      return str.contains('fff0');
    });

    // Check service data payload
    final isDataMatch = r.advertisementData.serviceData.keys.any((u) {
      return u.toString().toLowerCase().contains('fff0');
    });

    return isNameMatch || isUuidMatch || isDataMatch;
  }

  /// Scan for nearby JStyle devices.
  /// Returns once [timeout] elapses or the caller cancels the subscription.
  static Stream<ScanResult> scan({
    Duration timeout = const Duration(seconds: 12),
    bool showAll = false,
  }) {
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}

    FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: false,
      continuousUpdates: true,
    ).catchError((e) {
      debugPrint('[BandBleClient] startScan error: $e');
    });

    return FlutterBluePlus.scanResults
        .expand((results) => results)
        .where((r) => isJStyleDevice(r, showAll: showAll));
  }

  static Future<void> stopScan() => FlutterBluePlus.stopScan();

  /// Connect to [device] with retries, MTU negotiation, and subscribe to the fff7 notify characteristic.
  Future<bool> connect(BluetoothDevice device, {int maxRetries = 3}) async {
    _device = device;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('[BandBleClient] Connection attempt $attempt/$maxRetries to ${device.remoteId.str}');

        // Disconnect any lingering socket first
        try {
          await device.disconnect();
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (_) {}

        await device.connect(
          autoConnect: false,
          timeout: const Duration(seconds: 10),
        );

        if (!device.isConnected) {
          debugPrint('[BandBleClient] Attempt $attempt failed: device not connected');
          continue;
        }

        // Request higher MTU size on Android
        if (defaultTargetPlatform == TargetPlatform.android) {
          try {
            await device.requestMtu(247);
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            debugPrint('[BandBleClient] Request MTU notice: $e');
          }
        }

        // Discovery stabilization delay for older Android chipsets
        await Future.delayed(const Duration(milliseconds: 250));
        final services = await device.discoverServices();
        
        _writeChar = null;
        _notifyChar = null;

        for (final svc in services) {
          final sUuid = svc.serviceUuid.toString().toLowerCase();
          if (sUuid.contains('fff0')) {
            for (final char in svc.characteristics) {
              final cUuid = char.characteristicUuid.toString().toLowerCase();
              if (cUuid.contains('fff6')) _writeChar = char;
              if (cUuid.contains('fff7')) _notifyChar = char;
            }
          }
        }

        if (_notifyChar == null || _writeChar == null) {
          debugPrint('[BandBleClient] Services discovered but fff6/fff7 missing. Retrying...');
          await device.disconnect();
          continue;
        }

        // Stabilization delay before CCCD descriptor write
        await Future.delayed(const Duration(milliseconds: 250));
        await _notifyChar!.setNotifyValue(true);

        // Cancel any existing subscription to prevent duplicate streams
        await _notifySub?.cancel();
        _notifySub = _notifyChar!.onValueReceived.listen((data) {
          if (data.isNotEmpty) _notifyController.add(Uint8List.fromList(data));
        });

        debugPrint('[BandBleClient] Connected successfully to ${device.remoteId.str}');
        return true;
      } catch (e) {
        debugPrint('[BandBleClient] Connection attempt $attempt error: $e');
        try {
          await device.disconnect();
        } catch (_) {}
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }

    _device = null;
    _writeChar = null;
    _notifyChar = null;
    return false;
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

