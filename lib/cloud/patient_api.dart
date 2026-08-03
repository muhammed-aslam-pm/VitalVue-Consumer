import 'package:dio/dio.dart';

class PatientApi {
  PatientApi({
    required String baseUrl,
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
  }

  final String _baseUrl;
  late final Dio _dio;

  Future<bool> registerPatient({
    required String userId,
    required String phoneNumber,
    required String fullName,
    int? roomId,
    int? bedId,
    required int age,
    required String gender,
    required String bloodGroup,
    required String deviceId,
    String? altPhone,
    String? preCondition,
  }) async {
    final endpoint = '${_baseUrl}api/v1/patients/register';
    
    final body = {
      'user_id': userId,
      'phone_number': phoneNumber,
      'full_name': fullName,
      if (roomId != null) 'room_id': roomId,
      if (bedId != null) 'bed_id': bedId,
      'age': age,
      'gender': gender,
      'blood_group': bloodGroup,
      'device_id': deviceId,
      if (altPhone != null && altPhone.isNotEmpty) 'alt_phone': altPhone,
      if (preCondition != null && preCondition.isNotEmpty) 'pre_condition': preCondition,
    };

    try {
      final resp = await _dio.post(endpoint, data: body);
      return resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300;
    } on DioException catch (e) {
      print('[PatientApi] registerPatient failed: ${e.message}');
      if (e.response != null) {
        print('[PatientApi] registerPatient error data: ${e.response?.data}');
        throw Exception(e.response?.data['detail'] ?? 'Registration failed');
      }
      throw Exception('Network error during registration');
    }
  }
}
