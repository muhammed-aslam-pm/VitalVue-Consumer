import 'package:dio/dio.dart';

import 'auth_token_store.dart';
import 'patient_profile.dart';
/// Pure data layer for VitalVue authentication.
///
/// Two-step flow (staff / nurse / doctor):
///   1. [initiate]   POST /api/v1/auth/login-initiate   → dispatches OTP
///   2. [verifyOtp]  POST /api/v1/auth/verify-otp       → returns JWT pair
///
/// Token refresh:
///   [refresh]       POST /api/v1/auth/refresh          → new access token
class AuthRepository {
  AuthRepository({
    required String baseUrl,
    required AuthTokenStore store,
  })  : _store = store,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        )) {
    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: false,
      responseBody: true,
      error: true,
    ));
  }

  final AuthTokenStore _store;
  final Dio _dio;

  // ── Step 1: Initiate login (dispatch OTP) ──────────────────────────────────

  /// Sends user_id to the server. Server dispatches OTP to the registered
  /// contact (email/SMS). Throws [AuthException] on failure.
  Future<void> initiate(String userId) async {
    try {
      await _dio.post(
        'api/v1/auth/login-initiate',
        data: {'user_id': userId},
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
    } on DioException catch (e) {
      throw AuthException._fromDio(e);
    }
  }

  // ── Step 2: Verify OTP → get tokens ───────────────────────────────────────

  /// Exchanges (userId, otp) for access + refresh tokens.
  /// Persists tokens to [AuthTokenStore] on success.
  Future<void> verifyOtp(String userId, String otp) async {
    try {
      final resp = await _dio.post(
        'api/v1/auth/verify-otp',
        data: 'username=${Uri.encodeComponent(userId)}&password=${Uri.encodeComponent(otp)}',
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      final body = resp.data as Map<String, dynamic>;
      final accessToken = body['access_token'] as String? ?? '';
      // refresh_token may come in body OR in an HttpOnly cookie.
      // For mobile: fall back to body field.
      final refreshToken = (body['refresh_token'] as String?) ?? '';

      await _store.save(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userId,
      );
    } on DioException catch (e) {
      throw AuthException._fromDio(e);
    }
  }

  // ── Token refresh ──────────────────────────────────────────────────────────

  /// Exchanges the stored refresh token for a new access token.
  /// Returns the new access token, or throws [AuthException].
  Future<String> refresh() async {
    final rt = await _store.refreshToken;
    if (rt == null || rt.isEmpty) {
      throw const AuthException('No refresh token stored. Please log in again.');
    }

    try {
      final resp = await _dio.post(
        'api/v1/auth/refresh',
        data: {'refresh_token': rt},
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      final body = resp.data as Map<String, dynamic>;
      final newAccess = body['access_token'] as String? ?? '';
      if (newAccess.isEmpty) {
        throw const AuthException('Server returned empty access token.');
      }

      await _store.saveAccessToken(newAccess);
      return newAccess;
    } on DioException catch (e) {
      throw AuthException._fromDio(e);
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> logout() => _store.clear();

  // ── Fetch Profile ──────────────────────────────────────────────────────────

  /// Fetches the user profile from the server using the provided access token.
  Future<PatientProfile> getProfile(String accessToken) async {
    try {
      final resp = await _dio.get(
        'api/v1/auth/profile',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final body = resp.data as Map<String, dynamic>;
      return PatientProfile.fromJson(body);
    } on DioException catch (e) {
      throw AuthException._fromDio(e);
    }
  }
}

// ── Error type ────────────────────────────────────────────────────────────────

class AuthException implements Exception {
  const AuthException(this.message);

  factory AuthException._fromDio(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return const AuthException('Invalid credentials or OTP. Please try again.');
    }
    if (status == 404) {
      return const AuthException('User ID not found. Please check and retry.');
    }
    if (status == 422) {
      // Extract FastAPI validation detail if present.
      final detail = e.response?.data?['detail'];
      if (detail is List && detail.isNotEmpty) {
        return AuthException(detail.first['msg']?.toString() ?? 'Validation error');
      }
    }
    return AuthException(e.message ?? 'Network error. Please try again.');
  }

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
