import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../bloc/auth_bloc.dart';
import '../../bloc/auth_event.dart';
import '../../bloc/auth_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userIdCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _userIdFocus = FocusNode();
  final _otpFocus = FocusNode();

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _otpCtrl.dispose();
    _userIdFocus.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: Stack(
        children: [
          _BackgroundBlobs(),
          SafeArea(
            child: BlocConsumer<AuthBloc, AuthState>(
              listener: _handleStateChange,
              builder: (context, state) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 40),
                        _buildCard(context, state),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleStateChange(BuildContext context, AuthState state) {
    if (state is AuthOtpSent) {
      // Move focus to OTP field automatically.
      Future.delayed(300.ms, () {
        if (mounted) _otpFocus.requestFocus();
      });
    }
    if (state is AuthError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.message),
          backgroundColor: const Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF1A73E8).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFF1A73E8).withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.monitor_heart_rounded,
              color: Color(0xFF1A73E8), size: 36),
        )
            .animate()
            .scale(
                begin: const Offset(0.7, 0.7),
                duration: 600.ms,
                curve: Curves.elasticOut)
            .fadeIn(duration: 400.ms),
        const SizedBox(height: 20),
        Text(
          'VitalVue Consumer',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
        const SizedBox(height: 6),
        Text(
          'VitalVue Healthcare Platform',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 14,
          ),
        ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
      ],
    );
  }

  Widget _buildCard(BuildContext context, AuthState state) {
    final isOtpStep = state is AuthOtpSent ||
        (state is AuthError && state.previousState is AuthOtpSent);
    final isLoading = state is AuthLoading;
    final userId = isOtpStep
        ? (state is AuthOtpSent
            ? state.userId
            : (state as AuthError).previousState is AuthOtpSent
                ? ((state).previousState as AuthOtpSent).userId
                : _userIdCtrl.text)
        : _userIdCtrl.text;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: AnimatedSwitcher(
            duration: 350.ms,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position:
                    Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                        .animate(animation),
                child: child,
              ),
            ),
            child: isOtpStep
                ? _buildOtpForm(context, userId, isLoading)
                : _buildUserIdForm(context, isLoading),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 300.ms, duration: 400.ms)
        .slideY(begin: 0.1, end: 0, duration: 400.ms);
  }

  // ── Step 1: User ID form ──────────────────────────────────────────────────

  Widget _buildUserIdForm(BuildContext context, bool isLoading) {
    return Column(
      key: const ValueKey('userid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Staff Login',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter your Staff / Nurse / Doctor ID to receive an OTP.',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
        ),
        const SizedBox(height: 24),
        _AuthField(
          controller: _userIdCtrl,
          focusNode: _userIdFocus,
          label: 'User ID',
          hint: 'e.g. NUR-001 or DR-042',
          icon: Icons.badge_rounded,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) =>
              _submitUserId(context),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
          ],
        ),
        const SizedBox(height: 20),
        _AuthButton(
          label: 'Send OTP',
          icon: Icons.send_rounded,
          isLoading: isLoading,
          onPressed: () => _submitUserId(context),
        ),
      ],
    );
  }

  void _submitUserId(BuildContext context) {
    final uid = _userIdCtrl.text.trim();
    if (uid.isEmpty) return;
    context.read<AuthBloc>().add(AuthInitiateLogin(uid));
  }

  // ── Step 2: OTP form ──────────────────────────────────────────────────────

  Widget _buildOtpForm(
      BuildContext context, String userId, bool isLoading) {
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: isLoading
                  ? null
                  : () => context.read<AuthBloc>().add(const AuthLogout()),
              child: Icon(Icons.arrow_back_rounded,
                  color: Colors.white.withValues(alpha: 0.5), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Enter OTP',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        RichText(
          text: TextSpan(
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
            children: [
              const TextSpan(text: 'An OTP was sent to the contact registered for '),
              TextSpan(
                text: userId,
                style: const TextStyle(
                    color: Color(0xFF1A73E8), fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _AuthField(
          controller: _otpCtrl,
          focusNode: _otpFocus,
          label: 'OTP Code',
          hint: '6-digit code',
          icon: Icons.lock_rounded,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          onSubmitted: (_) => _submitOtp(context, userId),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 20),
        _AuthButton(
          label: 'Verify & Login',
          icon: Icons.verified_rounded,
          isLoading: isLoading,
          onPressed: () => _submitOtp(context, userId),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: isLoading
                ? null
                : () => context
                    .read<AuthBloc>()
                    .add(AuthInitiateLogin(userId)),
            child: Text(
              'Resend OTP',
              style: TextStyle(
                  color: const Color(0xFF1A73E8).withValues(alpha: 0.8),
                  fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  void _submitOtp(BuildContext context, String userId) {
    final otp = _otpCtrl.text.trim();
    if (otp.length < 4) return;
    context.read<AuthBloc>().add(AuthVerifyOtp(userId: userId, otp: otp));
  }
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.autofocus = false,
    this.maxLength,
    this.onSubmitted,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool autofocus;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLength: maxLength,
      onSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF1A73E8), size: 20),
        labelStyle:
            TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
        hintStyle:
            TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 14),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: Color(0xFF1A73E8), width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1A73E8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Icon(icon, size: 18),
        label: Text(
          isLoading ? 'Please wait…' : label,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
      ),
    );
  }
}

class _BackgroundBlobs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -120,
          left: -80,
          child: _blob(const Color(0x201A73E8), 300),
        ),
        Positioned(
          bottom: -60,
          right: -80,
          child: _blob(const Color(0x157C4DFF), 280),
        ),
      ],
    );
  }

  Widget _blob(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: const SizedBox.expand(),
        ),
      );
}
