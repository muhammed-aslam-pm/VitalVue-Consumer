import 'dart:async';

import 'package:dio/dio.dart';

import 'auth_repository.dart';
import 'auth_token_store.dart';

/// Dio interceptor that:
///   1. Injects `Authorization: Bearer <token>` on every request.
///   2. On 401: calls /api/v1/auth/refresh once, then retries the original.
///   3. On second 401 (refresh also failed): fires [onLogout] so the app can
///      navigate back to the login screen.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required AuthTokenStore store,
    required AuthRepository repository,
    required void Function() onLogout,
  })  : _store = store,
        _repo = repository,
        _onLogout = onLogout;

  final AuthTokenStore _store;
  final AuthRepository _repo;
  final void Function() _onLogout;

  bool _isRefreshing = false;
  final _refreshCompleter = Completer<String?>();

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _store.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only intercept 401 errors, and only once per refresh cycle.
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Prevent multiple simultaneous refresh calls.
    if (_isRefreshing) {
      final newToken = await _refreshCompleter.future;
      if (newToken == null) return handler.next(err);
      return handler.resolve(await _retry(err.requestOptions, newToken));
    }

    _isRefreshing = true;

    try {
      final newToken = await _repo.refresh();
      _refreshCompleter.complete(newToken);
      handler.resolve(await _retry(err.requestOptions, newToken));
    } on AuthException {
      _refreshCompleter.complete(null);
      _onLogout();
      handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<Response<dynamic>> _retry(
      RequestOptions opts, String newToken) async {
    opts.headers['Authorization'] = 'Bearer $newToken';
    return Dio().fetch(opts);
  }
}
