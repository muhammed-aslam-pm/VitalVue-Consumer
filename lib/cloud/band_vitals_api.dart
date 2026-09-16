import 'package:dio/dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../auth/auth_interceptor.dart';

/// Cloud ingest client — POST /api/v1/vitals/ingest.
/// Matches the Python cloud.py payload exactly.
///
/// [AuthInterceptor] is injected at construction time so that every request
/// automatically carries a valid Bearer token, with silent refresh on 401.
class BandVitalsApi {
  BandVitalsApi({
    required String baseUrl,
    AuthInterceptor? authInterceptor,
  }) : _baseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/' {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: false,
      responseBody: true,
      error: true,
    ));
    if (authInterceptor != null) {
      _dio.interceptors.add(authInterceptor);
    }
  }

  final String _baseUrl;
  late final Dio _dio;

  /// Full ingest URL — matches Python: base_url.rstrip("/") + "/api/v1/vitals/ingest"
  String get _endpoint => '${_baseUrl}api/v1/vitals/ingest';

  /// Bulk ingest URL — POST /api/v1/vitals/bulk-ingest
  String get _bulkEndpoint => '${_baseUrl}api/v1/vitals/bulk-ingest';

  /// Standard payload builder matching VitalIngestSchema
  static Map<String, dynamic> buildVitalPayload({
    required int patientId,
    required String deviceId,
    required int hr,
    required int spo2,
    required double tempC,
    int bpSys = 0,
    int bpDia = 0,
    int hrv = 0,
    String stress = '0',
    int movement = 0,
    int steps = 0,
    double calories = 0.0,
    double distanceKm = 0.0,
    int battery = -1,
    int phoneBattery = -1,
    bool isConnected = true,
    bool isRemoved = false,
    DateTime? recordedAt,
  }) {
    final payload = <String, dynamic>{
      'patient_id': patientId,
      'device_id': deviceId,
      'heart_rate': hr,
      'spo2': spo2,
      'temp': tempC,
      'bp_systolic': bpSys,
      'bp_diastolic': bpDia,
      'hrv_score': hrv,
      'stress_level': stress,
      'movement': movement,
      'steps': steps,
      'calories': calories,
      'distance_km': distanceKm,
      'sleep_pattern': 'unknown',
      'battery_percent': battery,
      'phone_battery': phoneBattery,
      'is_connected': isConnected,
      'is_removed': isRemoved,
    };

    if (recordedAt != null) {
      payload['timestamp'] = recordedAt.millisecondsSinceEpoch;
      payload['created_at'] = recordedAt.toIso8601String();
      payload['recorded_at'] = recordedAt.toIso8601String();
    }

    return payload;
  }

  Future<bool> ingest({
    required int patientId,
    required String deviceId,
    required int hr,
    required int spo2,
    required double tempC,
    int bpSys = 0,
    int bpDia = 0,
    int hrv = 0,
    String stress = '0',
    int movement = 0,
    int steps = 0,
    double calories = 0.0,
    double distanceKm = 0.0,
    int battery = -1,
    int phoneBattery = -1,
    bool isConnected = true,
    bool isRemoved = false,
  }) async {
    final body = buildVitalPayload(
      patientId: patientId,
      deviceId: deviceId,
      hr: hr,
      spo2: spo2,
      tempC: tempC,
      bpSys: bpSys,
      bpDia: bpDia,
      hrv: hrv,
      stress: stress,
      movement: movement,
      steps: steps,
      calories: calories,
      distanceKm: distanceKm,
      battery: battery,
      phoneBattery: phoneBattery,
      isConnected: isConnected,
      isRemoved: isRemoved,
    );

    final span = Sentry.getSpan()?.startChild(
      'http.client',
      description: 'POST $_endpoint',
    );

    try {
      final resp = await _dio.post(_endpoint, data: body);
      final ok = resp.statusCode != null && resp.statusCode! < 300;
      
      span?.status = ok ? const SpanStatus.ok() : const SpanStatus.internalError();
      span?.finish();

      if (!isConnected) {
        // ignore: avoid_print
        print('[Cloud] ✓ Final disconnect ingest sent (Status: ${resp.statusCode})');
      } else {
        // ignore: avoid_print
        print('[Cloud] ✓ Ingest sent (Status: ${resp.statusCode}) HR: $hr, SpO2: $spo2');
      }
      
      return ok;
    } on DioException catch (e, stackTrace) {
      span?.status = const SpanStatus.internalError();
      span?.finish();
      
      Sentry.captureException(
        e,
        stackTrace: stackTrace,
        withScope: (scope) => scope.setContexts('Request', {
          'url': _endpoint,
          'patient_id': patientId,
          'device_id': deviceId,
        }),
      );

      if (!isConnected) {
        // ignore: avoid_print
        print('[Cloud] ✗ Final disconnect ingest failed (Error: ${e.message})');
      } else {
        // ignore: avoid_print
        print('[Cloud] ✗ Ingest failed (Error: ${e.message})');
      }
      return false;
    }
  }

  /// Bulk ingest client — POST /api/v1/vitals/bulk-ingest
  /// Takes a list of vital payloads and sends them in batches (default 50 items per batch).
  Future<bool> bulkIngest(
    List<Map<String, dynamic>> payloads, {
    int batchSize = 50,
  }) async {
    if (payloads.isEmpty) return true;

    final transaction = Sentry.startTransaction('bulkIngest', 'task');

    // Process in batches
    for (int i = 0; i < payloads.length; i += batchSize) {
      final end = (i + batchSize < payloads.length) ? i + batchSize : payloads.length;
      final batch = payloads.sublist(i, end);

      final span = transaction.startChild('http.client', description: 'POST $_bulkEndpoint batch ${i ~/ batchSize}');

      try {
        final resp = await _dio.post(_bulkEndpoint, data: batch);
        final ok = resp.statusCode != null && resp.statusCode! < 300;
        
        span.status = ok ? const SpanStatus.ok() : const SpanStatus.internalError();
        span.finish();

        if (!ok) {
          // ignore: avoid_print
          print('[Cloud] ✗ Bulk ingest batch failed (Status: ${resp.statusCode})');
          transaction.finish(status: const SpanStatus.internalError());
          return false;
        }
        // ignore: avoid_print
        print('[Cloud] ✓ Bulk ingest sent (Status: ${resp.statusCode}) Batch ${i ~/ batchSize + 1} (${batch.length} items)');
      } on DioException catch (e, stackTrace) {
        span.status = const SpanStatus.internalError();
        span.finish();
        
        Sentry.captureException(
          e,
          stackTrace: stackTrace,
          withScope: (scope) => scope.setContexts('Request', {
            'url': _bulkEndpoint,
            'batch_size': batch.length,
          }),
        );

        // ignore: avoid_print
        print('[Cloud] ✗ Bulk ingest failed (Error: ${e.message})');
        transaction.finish(status: const SpanStatus.internalError());
        return false;
      }
    }

    transaction.finish(status: const SpanStatus.ok());
    return true;
  }

  /// Assigns a new device to the current patient.
  /// Endpoint: POST /api/v1/patients/me/change-device
  Future<bool> changeDevice(String newDeviceId) async {
    final url = '${_baseUrl}api/v1/patients/me/change-device';
    // ignore: avoid_print
    print('[Cloud] Attempting to change device to: $newDeviceId');
    try {
      final resp = await _dio.put(url, data: {
        'new_device_id': newDeviceId,
      });
      return resp.statusCode != null && resp.statusCode! < 300;
    } on DioException catch (e) {
      // ignore: avoid_print
      print('[Cloud] ✗ changeDevice failed: ${e.message}');
      return false;
    }
  }
}
