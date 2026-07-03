import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/auth_repository.dart';
import '../auth/auth_token_store.dart';
import 'auth_event.dart';
import 'auth_state.dart';

/// Manages the authentication lifecycle.
///
/// Cooperates with [AuthInterceptor]: when the interceptor detects that
/// refresh has failed, it calls the [forceLogout] convenience method which
/// adds an [AuthLogout] event — keeping all auth state changes inside this
/// BLoC.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required AuthRepository repository,
    required AuthTokenStore store,
  })  : _repo = repository,
        _store = store,
        super(const AuthInitial()) {
    on<AuthCheckStatus>(_onCheckStatus);
    on<AuthInitiateLogin>(_onInitiateLogin);
    on<AuthVerifyOtp>(_onVerifyOtp);
    on<AuthLogout>(_onLogout);
  }

  final AuthRepository _repo;
  final AuthTokenStore _store;

  /// Called by [AuthInterceptor] when refresh fails.
  void forceLogout() => add(const AuthLogout());

  // ── Handlers ──────────────────────────────────────────────────────────────

  Future<void> _onCheckStatus(
    AuthCheckStatus _,
    Emitter<AuthState> emit,
  ) async {
    final hasToken = await _store.hasToken;
    if (hasToken) {
      final uid = await _store.userId ?? '';
      emit(AuthAuthenticated(uid));
    } else {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onInitiateLogin(
    AuthInitiateLogin event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      await _repo.initiate(event.userId.trim());
      emit(AuthOtpSent(event.userId.trim()));
    } on AuthException catch (e) {
      emit(AuthError(
        message: e.message,
        previousState: const AuthUnauthenticated(),
      ));
    }
  }

  Future<void> _onVerifyOtp(
    AuthVerifyOtp event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      await _repo.verifyOtp(event.userId, event.otp);
      emit(AuthAuthenticated(event.userId));
    } on AuthException catch (e) {
      emit(AuthError(
        message: e.message,
        previousState: AuthOtpSent(event.userId),
      ));
    }
  }

  Future<void> _onLogout(
    AuthLogout _,
    Emitter<AuthState> emit,
  ) async {
    await _repo.logout();
    emit(const AuthUnauthenticated());
  }
}
