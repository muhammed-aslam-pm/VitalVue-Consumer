import 'package:dio/dio.dart';

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
    bool isConnected = true,
    bool isRemoved = false,
  }) async {
    final body = {
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
      'is_connected': isConnected,
      'is_removed': isRemoved,
    };

    // ignore: avoid_print
    print('[Cloud] POST $_endpoint  '
        'HR=$hr SpO2=$spo2 Temp=$tempC BP=$bpSys/$bpDia bat=$battery removed=$isRemoved '
        'HRV=$hrv Stress=$stress Steps=$steps Cal=$calories Dist=$distanceKm');

    try {
      final resp = await _dio.post(_endpoint, data: body);
      final ok = resp.statusCode != null && resp.statusCode! < 300;
      // ignore: avoid_print
      if (ok) print('[Cloud] ✓ Ingest accepted (${resp.statusCode})');
      return ok;
    } on DioException catch (e) {
      // ignore: avoid_print
      print('[Cloud] ✗ Ingest failed  status=${e.response?.statusCode}  '
          'url=$_endpoint  msg=${e.message}');
      return false;
    }
  }
}
