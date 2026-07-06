import 'package:dio/dio.dart';

class DiscoveryApi {
  DiscoveryApi({
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

  Future<List<Map<String, dynamic>>> getOrganizations({
    required String country,
    required String state,
    required String city,
  }) async {
    final endpoint = '${_baseUrl}api/v1/discovery/organizations';
    try {
      final resp = await _dio.get(endpoint, queryParameters: {
        'country': country,
        'state': state,
        'city': city,
      });
      if (resp.data is List) {
        return List<Map<String, dynamic>>.from(resp.data);
      }
      return [];
    } on DioException catch (e) {
      print('[Discovery] getOrganizations failed: ${e.message}');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getDepartments(int orgId) async {
    final endpoint = '${_baseUrl}api/v1/discovery/organizations/$orgId/departments';
    try {
      final resp = await _dio.get(endpoint);
      if (resp.data is List) {
        return List<Map<String, dynamic>>.from(resp.data);
      }
      return [];
    } on DioException catch (e) {
      print('[Discovery] getDepartments failed: ${e.message}');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getStations(int deptId) async {
    final endpoint = '${_baseUrl}api/v1/discovery/departments/$deptId/stations';
    try {
      final resp = await _dio.get(endpoint);
      if (resp.data is List) {
        return List<Map<String, dynamic>>.from(resp.data);
      }
      return [];
    } on DioException catch (e) {
      print('[Discovery] getStations failed: ${e.message}');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getWards(int stationId) async {
    final endpoint = '${_baseUrl}api/v1/discovery/stations/$stationId/wards';
    try {
      final resp = await _dio.get(endpoint);
      if (resp.data is List) {
        return List<Map<String, dynamic>>.from(resp.data);
      }
      return [];
    } on DioException catch (e) {
      print('[Discovery] getWards failed: ${e.message}');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRooms(int wardId) async {
    final endpoint = '${_baseUrl}api/v1/discovery/wards/$wardId/rooms';
    try {
      final resp = await _dio.get(endpoint);
      if (resp.data is List) {
        return List<Map<String, dynamic>>.from(resp.data);
      }
      return [];
    } on DioException catch (e) {
      print('[Discovery] getRooms failed: ${e.message}');
      return [];
    }
  }
}
