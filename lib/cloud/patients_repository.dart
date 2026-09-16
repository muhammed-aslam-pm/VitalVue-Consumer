import 'dart:async';

import 'package:dio/dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../auth/auth_interceptor.dart';
import 'assigned_patient.dart';

/// Fetches the list of patients assigned to the currently logged-in staff user.
///
/// Endpoint: GET /api/v1/patients/assigned
/// Auth: Bearer token injected by [AuthInterceptor].
class PatientsRepository {
  PatientsRepository({
    required String baseUrl,
    required AuthInterceptor authInterceptor,
  }) : _baseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/' {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(authInterceptor);
  }

  final String _baseUrl;
  late final Dio _dio;

  String get _endpoint => '${_baseUrl}api/v1/patients/assigned';

  /// Fetches the current list of assigned patients once.
  Future<List<AssignedPatient>> fetchAssigned() async {
    final transaction = Sentry.startTransaction('fetchAssigned', 'task');
    final span = transaction.startChild('http.client', description: 'GET $_endpoint');

    try {
      final resp = await _dio.get(_endpoint);
      final list = resp.data as List<dynamic>;
      
      span.status = const SpanStatus.ok();
      span.finish();
      transaction.finish(status: const SpanStatus.ok());

      return list
          .map((e) => AssignedPatient.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      span.status = const SpanStatus.internalError();
      span.finish();
      transaction.finish(status: const SpanStatus.internalError());
      
      Sentry.captureException(
        e,
        stackTrace: stackTrace,
        withScope: (scope) => scope.setContexts('Request', {
          'url': _endpoint,
        }),
      );
      rethrow;
    }
  }

  /// Returns a stream that emits fresh patient data every [interval].
  /// The first event is emitted immediately.
  Stream<List<AssignedPatient>> pollingStream({
    Duration interval = const Duration(seconds: 15),
  }) async* {
    while (true) {
      try {
        yield await fetchAssigned();
      } catch (_) {
        // Swallow errors between polls — BLoC will surface the last error state
      }
      await Future.delayed(interval);
    }
  }

  /// Snoozes a critical alert for 10 minutes.
  Future<void> snoozeAlert({required int patientId, required int alertId}) async {
    final url = '${_baseUrl}api/v1/patients/patients/$patientId/alerts/$alertId/snooze';
    try {
      await _dio.post(url);
    } catch (e, stackTrace) {
      Sentry.captureException(
        e,
        stackTrace: stackTrace,
        withScope: (scope) => scope.setContexts('Request', {
          'url': url,
          'patient_id': patientId,
          'alert_id': alertId,
        }),
      );
      rethrow;
    }
  }

  /// Records an action taken by staff for a given alert.
  Future<void> takeAction({
    required int patientId,
    required int alertId,
    required String actionType,
    String otherDetails = '',
    required DateTime performedAt,
  }) async {
    final url = '${_baseUrl}api/v1/patients/patients/$patientId/action';
    try {
      await _dio.post(url, data: {
        'action_type': actionType,
        'alert_id': alertId,
        'other_details': otherDetails,
        'performed_at': performedAt.toUtc().toIso8601String(),
      });
    } catch (e, stackTrace) {
      Sentry.captureException(
        e,
        stackTrace: stackTrace,
        withScope: (scope) => scope.setContexts('Request', {
          'url': url,
          'patient_id': patientId,
          'alert_id': alertId,
          'action_type': actionType,
        }),
      );
      rethrow;
    }
  }
}
