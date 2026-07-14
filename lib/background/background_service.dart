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

        final hasRoom = event.roomNumber.isNotEmpty;

        if (enableTts) {
          final roomTxt = hasRoom ? ' in ${event.wardName}, Room ${event.roomNumber}' : ' for Patient ${event.patientId}';
          flutterTts.speak('Critical Alert. ${event.vitalType}$roomTxt.');
        }
        
        if (enablePush) {
          final roomTxtPush = hasRoom ? ' (${event.wardName} - Rm ${event.roomNumber})' : ' (Patient ${event.patientId})';
          flutterLocalNotificationsPlugin.show(
            id: event.alertId,
            title: 'Critical Alert: ${event.vitalType}$roomTxtPush',
            body: 'Value triggered: ${event.triggeredValue} (${event.severity})',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'critical_alerts_channel',
                'Critical Alerts',
                icon: 'ic_bg_service_small',
                importance: Importance.max,
                priority: Priority.max,
                enableVibration: true,
                playSound: true,
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

  BandSessionService? session;

  service.on('stopService').listen((event) async {
    await session?.disconnect();
    service.stopSelf();
  });

  service.on('connectDevice').listen((event) async {
    if (event == null) return;
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

        /*
        final uningested = await db.getUningestedVitals();
        for (var row in uningested) {
          if (row['_id'] == id) continue;
          
          final syncSuccess = await api.ingest(
            patientId: row['patient_id'],
            deviceId: row['device_id'],
            hr: row['hr'],
            spo2: row['spo2'],
            tempC: row['tempC'],
            bpSys: row['bpSys'],
            bpDia: row['bpDia'],
            hrv: row['hrv'],
            stress: row['stress'],
            steps: row['steps'],
            calories: row['calories'],
            distanceKm: row['distanceKm'],
            battery: row['battery'],
            isRemoved: row['isRemoved'] == 1,
          );
          
          if (syncSuccess) {
            await db.markAsIngested(row['_id']);
          } else {
            break;
          }
        }
        */
        await db.deleteOldVitals();
      },
    );

    session!.stateStream.listen((state) {
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

      if (service is AndroidServiceInstance) {
        if (state.connectionStatus == BleConnectionStatus.connected) {
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

    await session!.connect(device);
  });

  // Check if we have a saved device to reconnect automatically on boot
  final savedDevice = await BackgroundPreferences.getDevice();
  if (savedDevice != null) {
    service.invoke('connectDevice', {
      'remote_id': savedDevice['mac'],
      'device_id': savedDevice['id'],
    });
    // simulate receiving it
    final remoteIdStr = savedDevice['mac']!;
    final deviceId = savedDevice['id']!;

    final profile = await BackgroundPreferences.getProfile();
    if (profile != null) {
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

          /*
          final uningested = await db.getUningestedVitals();
          for (var row in uningested) {
            if (row['_id'] == id) continue;
            
            final syncSuccess = await api.ingest(
              patientId: row['patient_id'],
              deviceId: row['device_id'],
              hr: row['hr'],
              spo2: row['spo2'],
              tempC: row['tempC'],
              bpSys: row['bpSys'],
              bpDia: row['bpDia'],
              hrv: row['hrv'],
              stress: row['stress'],
              steps: row['steps'],
              calories: row['calories'],
              distanceKm: row['distanceKm'],
              battery: row['battery'],
              isRemoved: row['isRemoved'] == 1,
            );
            
            if (syncSuccess) {
              await db.markAsIngested(row['_id']);
            } else {
              break;
            }
          }
          */
          await db.deleteOldVitals();
        },
      );

      session!.stateStream.listen((state) {
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

        if (service is AndroidServiceInstance) {
          flutterLocalNotificationsPlugin.show(
            id: 888,
            title: state.connectionStatus == BleConnectionStatus.connected
                ? 'JBand Connected'
                : 'JBand Monitoring',
            body: state.connectionStatus == BleConnectionStatus.connected
                ? 'HR: ${state.hr} bpm | Temp: ${state.tempC}°C'
                : 'Connecting...',
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
      });
      await session!.connect(device);
    }
  }
}
