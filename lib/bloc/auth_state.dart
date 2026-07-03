import 'package:equatable/equatable.dart';

import '../auth/patient_profile.dart';
abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

/// Waiting to check keystore on first launch.
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Any async operation in flight.
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// Not logged in — show User ID field.
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// User ID accepted, OTP dispatched — show OTP input field.
class AuthOtpSent extends AuthState {
  const AuthOtpSent(this.userId);
  final String userId;
  @override
  List<Object?> get props => [userId];
}

/// Fully authenticated — show band monitor dashboard.
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.profile);
  final PatientProfile profile;
  @override
  List<Object?> get props => [profile];
}

/// Any auth error — show inline message without losing form state.
class AuthError extends AuthState {
  const AuthError({required this.message, this.previousState});
  final String message;
  final AuthState? previousState;
  @override
  List<Object?> get props => [message];
}
