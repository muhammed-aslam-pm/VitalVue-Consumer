import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jband_monitor/bloc/patients_event.dart';

import 'auth/auth_interceptor.dart';
import 'auth/auth_repository.dart';
import 'auth/auth_token_store.dart';
import 'bloc/auth_bloc.dart';
import 'bloc/auth_event.dart';
import 'bloc/auth_state.dart';
import 'bloc/band_monitor_bloc.dart';
import 'bloc/band_monitor_event.dart';
import 'bloc/patients_bloc.dart';
import 'cloud/band_vitals_api.dart';
import 'cloud/patients_repository.dart';
import 'cloud/vitals_sse_service.dart';
import 'protocol/jstyle_codec.dart';
import 'ui/pages/band_monitor_page.dart';
import 'ui/pages/login_page.dart';
import 'ui/pages/staff_dashboard_page.dart';
import 'background/background_service.dart';

// ── Configuration — edit these or pass via --dart-define ─────────────────────
const _kApiBaseUrl = String.fromEnvironment(
  'BAND_API_URL',
  defaultValue: 'https://vitalvue-api.genesysailabs.com',
);
const _kPatientId = int.fromEnvironment('PATIENT_ID', defaultValue: 118);
const _kDeviceId =
    String.fromEnvironment('DEVICE_ID', defaultValue: 'jband-dev-01');
const _kPersonalInfo = PersonalInfo(
  sex: 1,
  age: 30,
  heightCm: 175,
  weightKg: 70,
  stepLengthCm: 70,
);

// ─────────────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeBackgroundService();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const JBandMonitorApp());
}

class JBandMonitorApp extends StatefulWidget {
  const JBandMonitorApp({super.key});

  @override
  State<JBandMonitorApp> createState() => _JBandMonitorAppState();
}

class _JBandMonitorAppState extends State<JBandMonitorApp> {
  // ── Singletons created once ───────────────────────────────────────────────
  late final AuthTokenStore _tokenStore;
  late final AuthRepository _authRepo;
  late final AuthBloc _authBloc;
  late final AuthInterceptor _authInterceptor;
  late final BandVitalsApi _vitalsApi;
  late final BandMonitorBloc _bandBloc;
  late final VitalsSseService _sseService;
  late final PatientsRepository _patientsRepo;
  late final PatientsBloc _patientsBloc;

  @override
  void initState() {
    super.initState();
    _tokenStore = AuthTokenStore();
    _authRepo = AuthRepository(baseUrl: _kApiBaseUrl, store: _tokenStore);

    _authBloc = AuthBloc(repository: _authRepo, store: _tokenStore);

    _authInterceptor = AuthInterceptor(
      store: _tokenStore,
      repository: _authRepo,
      // When the refresh token is also expired, force the user back to login.
      onLogout: () => _authBloc.forceLogout(),
    );

    _vitalsApi = BandVitalsApi(
      baseUrl: _kApiBaseUrl,
      authInterceptor: _authInterceptor,
    );

    _bandBloc = BandMonitorBloc(
      vitalsApi: _vitalsApi,
      patientId: _kPatientId,
      deviceId: _kDeviceId,
      personalInfo: _kPersonalInfo,
    );

    _patientsRepo = PatientsRepository(
      baseUrl: _kApiBaseUrl,
      authInterceptor: _authInterceptor,
    );
    _sseService = VitalsSseService(
      baseUrl: _kApiBaseUrl,
      tokenStore: _tokenStore,
    );
    _patientsBloc = PatientsBloc(
      repository: _patientsRepo,
      sseService: _sseService,
    );

    // Check for persisted token on startup.
    _authBloc.add(const AuthCheckStatus());
  }

  @override
  void dispose() {
    _authBloc.close();
    _bandBloc.close();
    _patientsBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _authBloc),
        BlocProvider.value(value: _bandBloc),
        BlocProvider.value(value: _patientsBloc),
      ],
      child: MaterialApp(
        title: 'VitalVue Consumer',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: BlocConsumer<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is AuthAuthenticated) {
              final p = state.profile;
              // Only patients have band biometric context
              if (p.isPatient) {
                context.read<BandMonitorBloc>().add(UpdateBandContext(
                      patientId: p.id,
                      personalInfo: PersonalInfo(
                        sex: (p.gender ?? 'Male').toLowerCase().startsWith('m')
                            ? 1
                            : 0,
                        age: p.age ?? 30,
                        heightCm: p.height ?? 170,
                        weightKg: p.weight ?? 70,
                        stepLengthCm: ((p.height ?? 170) * 0.415).round(),
                      ),
                    ));
              }
            } else if (state is AuthUnauthenticated) {
              context.read<BandMonitorBloc>().add(const DisconnectBand());
              context.read<PatientsBloc>().add(const StopPatients());
            }
          },
          builder: (context, state) {
            if (state is AuthAuthenticated) {
              return state.profile.isPatient
                  ? const BandMonitorPage()
                  : const StaffDashboardPage();
            }
            return switch (state) {
              AuthInitial() => const _SplashScreen(),
              _ => const LoginPage(),
            };
          },
        ),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F1117),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF1A73E8),
        secondary: Color(0xFF00BFA5),
        surface: Color(0xFF1A1D27),
        error: Color(0xFFE53935),
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      useMaterial3: true,
    );
  }
}

// ── Splash shown for the <100 ms token-check ─────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F1117),
      body: Center(
        child: CircularProgressIndicator(
          color: Color(0xFF1A73E8),
          strokeWidth: 2,
        ),
      ),
    );
  }
}
