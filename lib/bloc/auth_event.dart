import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

/// App startup — check for stored tokens.
class AuthCheckStatus extends AuthEvent {
  const AuthCheckStatus();
}

/// User typed their User ID and pressed Next.
class AuthInitiateLogin extends AuthEvent {
  const AuthInitiateLogin(this.userId);
  final String userId;
  @override
  List<Object?> get props => [userId];
}

/// User submitted the OTP code.
class AuthVerifyOtp extends AuthEvent {
  const AuthVerifyOtp({required this.userId, required this.otp});
  final String userId;
  final String otp;
  @override
  List<Object?> get props => [userId, otp];
}

/// User tapped Logout, or refresh token expired.
class AuthLogout extends AuthEvent {
  const AuthLogout();
}
