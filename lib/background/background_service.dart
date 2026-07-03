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

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'jband_monitor_service',
    'JBand Monitoring Service',
    description:
        'Keeps the BLE connection and vital sync alive in the background.',
    importance: Importance.low,
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

  BandSessionService? session;

  service.on('stopService').listen((event) {
    session?.disconnect();
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
        age: profile.age,
        sex: profile.gender == 'Male' ? 1 : 0,
        heightCm: profile.height,
        weightKg: profile.weight,
        stepLengthCm: (profile.height * 0.415).toInt(),
      ),
      onIngest: (state) {
        final store = AuthTokenStore();
        final repo = AuthRepository(
            baseUrl: 'https://vitalvue-api.genesysailabs.com', store: store);
        final interceptor =
            AuthInterceptor(store: store, repository: repo, onLogout: () {});
        return BandVitalsApi(
          baseUrl: 'https://vitalvue-api.genesysailabs.com',
          authInterceptor: interceptor,
        ).ingest(
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
        );
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
          age: profile.age,
          sex: profile.gender == 'Male' ? 1 : 0,
          heightCm: profile.height,
          weightKg: profile.weight,
          stepLengthCm: (profile.height * 0.415).toInt(),
        ),
        onIngest: (state) {
          final store = AuthTokenStore();
          final repo = AuthRepository(
              baseUrl: 'https://vitalvue-api.genesysailabs.com', store: store);
          final interceptor =
              AuthInterceptor(store: store, repository: repo, onLogout: () {});
          return BandVitalsApi(
            baseUrl: 'https://vitalvue-api.genesysailabs.com',
            authInterceptor: interceptor,
          ).ingest(
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
          );
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
