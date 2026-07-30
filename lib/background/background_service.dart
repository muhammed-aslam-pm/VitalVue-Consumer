import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../cloud/band_vitals_api.dart';
import '../auth/auth_interceptor.dart';
import '../auth/auth_repository.dart';
import '../auth/auth_token_store.dart';
import '../session/band_session_service.dart';
import '../protocol/jstyle_codec.dart';
import 'background_preferences.dart';
import '../db/vitals_database.dart';
import '../cloud/vitals_sse_service.dart';
import '../cloud/sse_events.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'jband_monitor_service',
    'JBand Monitoring Service',
    description:
        'Keeps the BLE connection and vital sync alive in the background.',
    importance: Importance.low,
  );

  const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
    'critical_alerts_channel',
    'Critical Alerts',
    description: 'Notifications for critical patient vitals',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('warning_beep'),
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_bg_service_small'),
      ),
    );
  }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(alertChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'jband_monitor_service',
      initialNotificationTitle: 'VitalVue Consumer',
      initialNotificationContent: 'Initializing...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Set up notifications for background updates
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // ── Shared Alert pre-feedback: long vibration + warning beep ────────────────
  // Plays vibration and the bundled warning beep concurrently, then holds
  // 700 ms so users hear: [buzz + beep] → voice announcement.
  Future<void> triggerAlertFeedback() async {
    await Future.wait([
      // 1. Long double-buzz: 700 ms on, 150 ms off, 700 ms on.
      () async {
        try {
          final hasVibrator = await Vibration.hasVibrator();
          if (hasVibrator == true) {
            await Vibration.vibrate(pattern: [0, 700, 150, 700]);
          }
        } catch (_) {}
      }(),
      // 2. Play the bundled triple-beep warning tone (not phone ringtone).
      () async {
        try {
          final player = AudioPlayer();
          await player.setVolume(1.0);
          await player.play(AssetSource('sounds/warning_beep.wav'));
          // Wait for the beep to finish (~800 ms) then release.
          await Future.delayed(const Duration(milliseconds: 900));
          await player.dispose();
        } catch (_) {}
      }(),
    ]);
    // Brief pause so TTS voice doesn't overlap the beep tail.
    await Future.delayed(const Duration(milliseconds: 700));
  }

  // --- STAFF/DOCTOR SSE BACKGROUND LOGIC ---
  final profile = await BackgroundPreferences.getProfile();
  if (profile != null && !profile.isPatient) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'VitalVue Monitoring',
        content: 'Monitoring Vitals 24/7',
      );
    }
    
    final tokenStore = AuthTokenStore();
    final sseService = VitalsSseService(
      baseUrl: 'https://vitalvue-api.genesysailabs.com',
      tokenStore: tokenStore,
    );

    final flutterTts = FlutterTts();
    await flutterTts.setVolume(1.0);
    await flutterTts.setSpeechRate(0.5);

    final sseSubscription = sseService.connect().listen((event) async {
      if (event is SseCriticalAlertEvent) {
        final enableTts = await BackgroundPreferences.getEnableTts();
        final enablePush = await BackgroundPreferences.getEnablePush();

        final patientNames = await BackgroundPreferences.getPatientNames();
        final pName = patientNames[event.patientId];
        final nameTxt = pName ?? 'Patient ${event.patientId}';

        final hasRoom = event.roomNumber.isNotEmpty;
        final roomTxtTts =
            hasRoom ? ' in ${event.wardName}, Room ${event.roomNumber}' : '';

        // ── Pre-announcement: long vibration + warning beep ──
        // Always fires regardless of TTS/push settings.
        await triggerAlertFeedback();

        if (enableTts) {
          flutterTts.speak('Critical Alert for $nameTxt. ${event.vitalType}$roomTxtTts.');
        }
        
        if (enablePush) {
          final roomTxtPush = hasRoom ? ' (${event.wardName} - Rm ${event.roomNumber})' : '';
          flutterLocalNotificationsPlugin.show(
            id: event.alertId,
            title: 'Critical Alert: ${event.vitalType} ($nameTxt$roomTxtPush)',
            body: 'Value triggered: ${event.triggeredValue} (${event.severity})',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'critical_alerts_channel',
                'Critical Alerts',
                icon: 'ic_bg_service_small',
                importance: Importance.max,
                priority: Priority.max,
                enableVibration: false, // vibration handled separately
                playSound: true,
                sound: RawResourceAndroidNotificationSound('warning_beep'),
              ),
            ),
          );
        }
      }
    });
    
    service.on('stopService').listen((event) async {
      await sseSubscription.cancel();
      service.stopSelf();
    });

    // Self-stopping watchdog: check every 5s if the user is still logged in.
    // This is needed because invoke('stopService') can be dropped when the
    // main Flutter engine tears down during logout.
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      final p = await BackgroundPreferences.getProfile();
      if (p == null) {
        timer.cancel();
        await sseSubscription.cancel();
        service.stopSelf();
      }
    });

    // For staff, we just run the SSE stream and don't need the BLE stuff below.
    return;
  }
  // --- END STAFF/DOCTOR LOGIC ---

  // --- PATIENT BLE MONITORING LOGIC ---
  BandSessionService? session;

  final patientTts = FlutterTts();
  await patientTts.setVolume(1.0);
  await patientTts.setSpeechRate(0.5);

  bool wasConnected = false;
  bool wasRemoved = false;
  bool isManualDisconnect = false;

  service.on('stopService').listen((event) async {
    isManualDisconnect = true;
    await session?.disconnect();
    service.stopSelf();
  });

  service.on('connectDevice').listen((event) async {
    if (event == null) return;
    isManualDisconnect = false;
    final remoteIdStr = event['remote_id'] as String;
    final deviceId = event['device_id'] as String;

    // Save to preferences so we can auto-reconnect on restart
    await BackgroundPreferences.saveDevice(deviceId, remoteIdStr, deviceId);

    // Disconnect old session if any
    await session?.disconnect();

    final profile = await BackgroundPreferences.getProfile();
    if (profile == null) return;

    final device = BluetoothDevice.fromId(remoteIdStr);

    session = BandSessionService(
      patientId: profile.id,
      deviceId: deviceId,
      personalInfo: PersonalInfo(
        age: profile.age ?? 30,
        sex: (profile.gender ?? 'Male') == 'Male' ? 1 : 0,
        heightCm: profile.height ?? 170,
        weightKg: profile.weight ?? 70,
        stepLengthCm: ((profile.height ?? 170) * 0.415).toInt(),
      ),
      onIngest: (state) async {
        final store = AuthTokenStore();
        final repo = AuthRepository(
            baseUrl: 'https://vitalvue-api.genesysailabs.com', store: store);
        final interceptor =
            AuthInterceptor(store: store, repository: repo, onLogout: () {});
        final api = BandVitalsApi(
          baseUrl: 'https://vitalvue-api.genesysailabs.com',
          authInterceptor: interceptor,
        );
        
        final db = VitalsDatabase.instance;
        
        final vitalData = {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'patient_id': profile.id,
          'device_id': deviceId,
          'hr': state.hr,
          'spo2': state.spo2,
          'tempC': state.tempC,
          'bpSys': state.systolic ?? 0,
          'bpDia': state.diastolic ?? 0,
          'hrv': state.hrv ?? 0,
          'stress': (state.stress ?? 0).toString(),
          'steps': state.steps,
          'calories': state.calories,
          'distanceKm': state.distanceKm,
          'battery': state.battery,
          'isRemoved': state.isRemoved,
          'isIngested': 0,
        };

        final id = await db.insertVital(vitalData);

        final success = await api.ingest(
          patientId: profile.id,
          deviceId: deviceId,
          hr: state.hr,
          spo2: state.spo2,
          tempC: state.tempC,
          bpSys: state.systolic ?? 0,
          bpDia: state.diastolic ?? 0,
          hrv: state.hrv ?? 0,
          stress: (state.stress ?? 0).toString(),
          steps: state.steps,
          calories: state.calories,
          distanceKm: state.distanceKm,
          battery: state.battery,
          isRemoved: state.isRemoved,
          isConnected: state.connectionStatus == BleConnectionStatus.connected,
        );

        if (success) {
          await db.markAsIngested(id);
        }

        await db.deleteOldVitals();
      },
    );

    session!.stateStream.listen((state) async {
      // Broadcast state back to UI
      service.invoke('vitals_update', {
        'status': state.connectionStatus.name,
        'hr': state.hr,
        'spo2': state.spo2,
        'tempC': state.tempC,
        'bpSys': state.systolic,
        'bpDia': state.diastolic,
        'hrv': state.hrv,
        'stress': state.stress,
        'steps': state.steps,
        'calories': state.calories,
        'distanceKm': state.distanceKm,
        'battery': state.battery,
        'isRemoved': state.isRemoved,
      });

      final isConnected = state.connectionStatus == BleConnectionStatus.connected;
      final isDisconnected = state.connectionStatus == BleConnectionStatus.disconnected;

      // ── Accidental Disconnect Detection ──
      if (wasConnected && isDisconnected && !isManualDisconnect) {
        wasConnected = false;
        final enableTts = await BackgroundPreferences.getEnableTts();
        final enablePush = await BackgroundPreferences.getEnablePush();

        await triggerAlertFeedback();

        if (enableTts) {
          await patientTts.speak(
              'Warning: Your band was disconnected accidentally. Attempting to reconnect.');
        }

        if (enablePush) {
          flutterLocalNotificationsPlugin.show(
            id: 991,
            title: 'Band Disconnected',
            body: 'Your band lost connection accidentally. Attempting to reconnect...',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'critical_alerts_channel',
                'Critical Alerts',
                icon: 'ic_bg_service_small',
                importance: Importance.max,
                priority: Priority.max,
                enableVibration: false,
                playSound: true,
                sound: RawResourceAndroidNotificationSound('warning_beep'),
              ),
            ),
          );
        }
      } else if (isConnected) {
        wasConnected = true;
      }

      // ── Off-Wrist Detection ──
      if (!wasRemoved && state.isRemoved) {
        wasRemoved = true;
        final enableTts = await BackgroundPreferences.getEnableTts();
        final enablePush = await BackgroundPreferences.getEnablePush();

        await triggerAlertFeedback();

        if (enableTts) {
          await patientTts.speak(
              'Warning: Band off wrist detected. Please put your band back on.');
        }

        if (enablePush) {
          flutterLocalNotificationsPlugin.show(
            id: 992,
            title: 'Band Off-Wrist Detected',
            body: 'Please ensure your band is worn securely on your wrist.',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'critical_alerts_channel',
                'Critical Alerts',
                icon: 'ic_bg_service_small',
                importance: Importance.max,
                priority: Priority.max,
                enableVibration: false,
                playSound: true,
                sound: RawResourceAndroidNotificationSound('warning_beep'),
              ),
            ),
          );
        }
      } else if (wasRemoved && !state.isRemoved) {
        wasRemoved = false;
      }

      if (service is AndroidServiceInstance) {
        if (isConnected) {
          flutterLocalNotificationsPlugin.show(
            id: 888,
            title: 'JBand Connected',
            body: 'HR: ${state.hr} bpm | Temp: ${state.tempC}°C',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'jband_monitor_service',
                'JBand Monitoring Service',
                icon: 'ic_bg_service_small',
                ongoing: true,
              ),
            ),
          );
        } else {
          flutterLocalNotificationsPlugin.show(
            id: 888,
            title: 'JBand Disconnected',
            body: 'Attempting to reconnect...',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'jband_monitor_service',
                'JBand Monitoring Service',
                icon: 'ic_bg_service_small',
                ongoing: true,
              ),
            ),
          );
        }
      }
    });

    final connected = await session!.connect(device);
    if (connected) {
      try {
        final store = AuthTokenStore();
        final repo = AuthRepository(
            baseUrl: 'https://vitalvue-api.genesysailabs.com', store: store);
        final interceptor =
            AuthInterceptor(store: store, repository: repo, onLogout: () {});
        final api = BandVitalsApi(
          baseUrl: 'https://vitalvue-api.genesysailabs.com',
          authInterceptor: interceptor,
        );
        api.changeDevice(deviceId).then((success) {
          if (success) {
            // ignore: avoid_print
            print('[Background] Successfully registered device $deviceId to patient');
          }
        }).catchError((e) {
          // ignore: avoid_print
          print('[Background] Error calling changeDevice: $e');
        });
      } catch (_) {}
    }
  });

  // Check if we have a saved device to reconnect automatically on boot
  final savedDevice = await BackgroundPreferences.getDevice();
  if (savedDevice != null) {
    service.invoke('connectDevice', {
      'remote_id': savedDevice['mac'],
      'device_id': savedDevice['id'],
    });
  }
}

