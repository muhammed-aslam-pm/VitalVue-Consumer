import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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

  const defaultDsn =
      'https://dd4d1111c317b961e3f1f6e80430ea9a@o4512067849945088.ingest.us.sentry.io/4512067856105472';
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN', defaultValue: defaultDsn);
      options.tracesSampleRate = 1.0;
      options.enableFramesTracking = false;
      options.enableAutoSessionTracking = false;
    },
  );

  PlatformDispatcher.instance.onError = (error, stack) {
    Sentry.captureException(error, stackTrace: stack, withScope: (scope) => scope.setTag('isolate', 'background'));
    return true;
  };
  FlutterError.onError = (details) {
    Sentry.captureException(details.exception, stackTrace: details.stack, withScope: (scope) => scope.setTag('isolate', 'background'));
  };

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

  // Track currently active alert IDs that are being announced.
  final Set<int> activeAlertIds = {};

  // ── Staff alert: Beep Beep + speech × 3, then a final Beep Beep ─────────────
  // Pattern per client spec:
  //   [Beep Beep] "<message>" [Beep Beep] "<message>" [Beep Beep] "<message>" [Beep Beep]
  Future<void> announceRepeat(
    FlutterTts tts,
    String message, {
    int? alertId,
    int times = 3,
  }) async {
    for (int i = 0; i < times; i++) {
      if (alertId != null && !activeAlertIds.contains(alertId)) {
        break;
      }
      // Play beep + vibration.
      await triggerAlertFeedback();
      if (alertId != null && !activeAlertIds.contains(alertId)) {
        break;
      }
      // Speak the message and wait until it finishes.
      final completer = Completer<void>();
      tts.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
      });
      await tts.speak(message);
      // Guard: resolve after 10 s max in case the completion handler isn't fired.
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
      if (alertId != null && !activeAlertIds.contains(alertId)) {
        break;
      }
      // Small gap between repetitions.
      await Future.delayed(const Duration(milliseconds: 400));
    }
    // Final Beep Beep after the last repetition, only if not silenced/dismissed.
    if (alertId == null || activeAlertIds.contains(alertId)) {
      await triggerAlertFeedback();
    }
    if (alertId != null) {
      activeAlertIds.remove(alertId);
    }
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

    // Helper to look up a patient name from cached preferences.
    Future<String> resolvePatientName(int patientId) async {
      final patientNames = await BackgroundPreferences.getPatientNames();
      return patientNames[patientId] ?? 'Patient $patientId';
    }

    // Helper to build the room string for a TTS announcement.
    String roomLabel(String wardName, String roomNumber) {
      if (roomNumber.isEmpty) return '';
      return '$wardName, Room $roomNumber';
    }

    final sseSubscription = sseService.connect().listen((event) async {
      if (event is SseCriticalAlertEvent) {
        final enableTts = await BackgroundPreferences.getEnableTts();
        final enablePush = await BackgroundPreferences.getEnablePush();

        final nameTxt = await resolvePatientName(event.patientId);
        final hasRoom = event.roomNumber.isNotEmpty;
        final roomTxt = hasRoom ? roomLabel(event.wardName, event.roomNumber) : '';
        final roomSuffix = hasRoom ? ' $roomTxt' : '';
        final roomTxtPush = hasRoom ? ' (${event.wardName} - Rm ${event.roomNumber})' : '';

        // Add to active set so announceRepeat can check it and we can snooze/cancel it.
        final alertId = event.alertId;
        activeAlertIds.add(alertId);

        // ── Determine alert type from vitalType / triggeredValue fields ───────
        // The server uses a single `critical_alert` SSE event for all alert
        // types. The `vital_type` and `triggered_value` JSON fields tell us what
        // actually happened.
        final vt = event.vitalType.toLowerCase();
        final tv = event.triggeredValue.toLowerCase();
        // ignore: avoid_print
        print('[SSE Alert] vitalType="${event.vitalType}" triggeredValue="${event.triggeredValue}" severity=${event.severity}');
        final isDisconnect = vt.contains('disconnect') ||
            vt.contains('outbound') ||
            vt.contains('out of range') ||
            vt.contains('bluetooth') ||
            vt.contains('connectivity') ||
            tv.contains('disconnect') ||
            tv.contains('outbound') ||
            tv.contains('out of range') ||
            tv.contains('bluetooth');
        final isBandRemoval = (vt.contains('band') && (vt.contains('remov') || vt.contains('off'))) ||
            (tv.contains('band') && (tv.contains('remov') || tv.contains('off')));

        // ── 1. Fire push notification IMMEDIATELY (don't wait for TTS) ────────
        if (enablePush) {
          if (isDisconnect) {
            flutterLocalNotificationsPlugin.show(
              id: event.alertId,
              title: 'Patient Outbound: $nameTxt$roomTxtPush',
              body: 'Band is out of range or disconnected.',
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
          } else if (isBandRemoval) {
            flutterLocalNotificationsPlugin.show(
              id: event.alertId,
              title: 'Band Removed: $nameTxt$roomTxtPush',
              body: 'Patient band was detected off-wrist.',
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
          } else {
            // ── Critical Alert (vital threshold breach) ──
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
                  enableVibration: false,
                  playSound: true,
                  sound: RawResourceAndroidNotificationSound('warning_beep'),
                ),
              ),
            );
          }
        }

        // ── 2. Play the correct TTS announcement (3× repeat) ─────────────────
        if (enableTts) {
          if (isDisconnect) {
            // "Beep Beep – Patient Outbound. {Name}, {Room} is Outbound" × 3
            final ttsMsg = hasRoom
                ? 'Patient Outbound. $nameTxt,$roomSuffix is Outbound.'
                : 'Patient Outbound. $nameTxt is Outbound.';
            await announceRepeat(flutterTts, ttsMsg, alertId: alertId);
          } else if (isBandRemoval) {
            // "Beep Beep – Patient Band Removed. Please attend {Name} {Room}" × 3
            final ttsMsg = hasRoom
                ? 'Patient Band Removed. Please attend $nameTxt$roomSuffix.'
                : 'Patient Band Removed. Please attend $nameTxt.';
            await announceRepeat(flutterTts, ttsMsg, alertId: alertId);
          } else {
            // "Beep Beep – Patient Critical Alert. Please attend {Name} {Room} immediately" × 3
            await announceRepeat(
              flutterTts,
              'Patient Critical Alert. Please attend $nameTxt$roomSuffix immediately.',
              alertId: alertId,
            );
          }
        } else {
          // TTS off — still fire the beep/vibration feedback.
          await triggerAlertFeedback();
        }

      } else if (event is SseAlertSnoozedEvent) {
        // ignore: avoid_print
        print('[SSE Alert Snoozed] alertId=${event.alertId}');
        activeAlertIds.remove(event.alertId);
        await flutterTts.stop();
        try {
          await flutterLocalNotificationsPlugin.cancel(id: event.alertId);
        } catch (_) {}

      } else if (event is SseAlertResolvedEvent) {
        // ignore: avoid_print
        print('[SSE Alert Resolved] alertId=${event.alertId}');
        activeAlertIds.remove(event.alertId);
        await flutterTts.stop();
        try {
          await flutterLocalNotificationsPlugin.cancel(id: event.alertId);
        } catch (_) {}

      } else if (event is SseBluetoothDisconnectEvent) {
        // ── Dedicated bluetooth_disconnect SSE event (future backend support) ──
        final enableTts = await BackgroundPreferences.getEnableTts();
        final enablePush = await BackgroundPreferences.getEnablePush();

        final nameTxt = await resolvePatientName(event.patientId);
        final hasRoom = event.roomNumber.isNotEmpty;
        final roomTxt = hasRoom ? roomLabel(event.wardName, event.roomNumber) : '';
        final ttsMsg = hasRoom
            ? 'Patient Outbound. $nameTxt, $roomTxt is Outbound.'
            : 'Patient Outbound. $nameTxt is Outbound.';

        if (enablePush) {
          final roomTxtPush = hasRoom ? ' (${event.wardName} - Rm ${event.roomNumber})' : '';
          flutterLocalNotificationsPlugin.show(
            id: event.patientId * 10 + 1,
            title: 'Patient Outbound: $nameTxt$roomTxtPush',
            body: 'Band is out of range or disconnected.',
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
        if (enableTts) {
          await announceRepeat(flutterTts, ttsMsg);
        } else {
          await triggerAlertFeedback();
        }

      } else if (event is SseBandRemovalEvent) {
        // ── Dedicated band_removal SSE event (future backend support) ──────────
        final enableTts = await BackgroundPreferences.getEnableTts();
        final enablePush = await BackgroundPreferences.getEnablePush();

        final nameTxt = await resolvePatientName(event.patientId);
        final hasRoom = event.roomNumber.isNotEmpty;
        final roomTxt = hasRoom ? roomLabel(event.wardName, event.roomNumber) : '';
        final ttsMsg = hasRoom
            ? 'Patient Band Removed. Please attend $nameTxt $roomTxt.'
            : 'Patient Band Removed. Please attend $nameTxt.';

        if (enablePush) {
          final roomTxtPush = hasRoom ? ' (${event.wardName} - Rm ${event.roomNumber})' : '';
          flutterLocalNotificationsPlugin.show(
            id: event.patientId * 10 + 2,
            title: 'Band Removed: $nameTxt$roomTxtPush',
            body: 'Patient band was detected off-wrist.',
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
        if (enableTts) {
          await announceRepeat(flutterTts, ttsMsg);
        } else {
          await triggerAlertFeedback();
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
  Timer? patientBandRemovalTimer;

  service.on('stopService').listen((event) async {
    isManualDisconnect = true;
    service.invoke('sync_status', {
      'isSyncing': false,
      'pending': 0,
    });
    patientBandRemovalTimer?.cancel();
    await session?.disconnect();
    service.stopSelf();
  });

  // Disconnect BLE without stopping the service process.
  // This keeps the isolate alive so connectDevice listeners remain registered,
  // avoiding the double-click race on reconnect.
  service.on('disconnectDevice').listen((event) async {
    isManualDisconnect = true;
    service.invoke('sync_status', {
      'isSyncing': false,
      'pending': 0,
    });
    patientBandRemovalTimer?.cancel();
    await session?.disconnect();
    session = null;
    wasConnected = false;
    // Update notification to reflect disconnected state
    flutterLocalNotificationsPlugin.show(
      id: 888,
      title: 'JBand Disconnected',
      body: 'Tap to reconnect',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'jband_monitor_service',
          'JBand Monitoring Service',
          icon: 'ic_bg_service_small',
          ongoing: true,
        ),
      ),
    );
  });

  service.on('connectDevice').listen((event) async {
    if (event == null) return;
    isManualDisconnect = false;
    wasConnected = false;
    wasRemoved = false;
    patientBandRemovalTimer?.cancel();
    final remoteIdStr = event['remote_id'] as String;
    final deviceId = event['device_id'] as String;

    // Save to preferences so we can auto-reconnect on restart
    await BackgroundPreferences.saveDevice(deviceId, remoteIdStr, deviceId);

    // Disconnect old session if any
    await session?.disconnect();

    final profile = await BackgroundPreferences.getProfile();
    if (profile == null) return;

    final device = BluetoothDevice.fromId(remoteIdStr);

    // Cache variables for last reliable vitals in this session
    int lastValidHr = 0;
    double lastValidTempC = 0.0;
    int lastValidSteps = 0;
    double lastValidCalories = 0.0;
    double lastValidDistanceKm = 0.0;
    int lastValidSpo2 = 0;
    int lastValidBpSys = 0;
    int lastValidBpDia = 0;
    int lastValidHrv = 0;
    String lastValidStress = '0';

    try {
      final db = VitalsDatabase.instance;
      lastValidHr = await db.getLastValidHr();
      lastValidSpo2 = await db.getLastValidSpo2();
      lastValidTempC = await db.getLastValidTempC();
      final lastBp = await db.getLastValidBp();
      if (lastBp != null) {
        lastValidBpSys = lastBp['bpSys'] as int? ?? 0;
        lastValidBpDia = lastBp['bpDia'] as int? ?? 0;
        lastValidHrv = lastBp['hrv'] as int? ?? 0;
        lastValidStress = (lastBp['stress'] ?? '0').toString();
      }
      await db.cleanInvalidZeroRecords();
    } catch (e) {
      // ignore: avoid_print
      print('[Background] Failed to load last valid vitals from DB: $e');
    }

    bool isSyncing = false;
    int consecutiveIngestFailures = 0;

    Future<void> syncPendingVitals({
      required BandVitalsApi api,
      required VitalsDatabase db,
      required int patientId,
      required String deviceId,
      required int phoneBattery,
      required int battery,
      required bool isConnected,
      required bool isRemoved,
      bool isHistorySync = false,
    }) async {
      if (isManualDisconnect) {
        // ignore: avoid_print
        print('[Background] Manual disconnect active, skipping bulk sync.');
        return;
      }
      if (isSyncing) {
        // ignore: avoid_print
        print('[Background] syncPendingVitals already in progress, skipping overlapping run.');
        return;
      }
      isSyncing = true;
      bool broadcastedSync = false;
      try {
        final initialPending = await db.getUningestedCount();
        if (initialPending == 0) return;

        // If this is history sync or there are multiple backlog records, broadcast sync status to UI
        if ((isHistorySync || initialPending > 1) && !isManualDisconnect) {
          broadcastedSync = true;
          service.invoke('sync_status', {
            'isSyncing': true,
            'pending': initialPending,
          });
        }

        while (true) {
          if (isManualDisconnect) {
            // ignore: avoid_print
            print('[Background] Manual disconnect active, aborting bulk sync passes.');
            break;
          }
          // Limit each sync pass to 100 items (4 batches of 25) so network calls stay quick
          final uningested = await db.getUningestedVitals(limit: 100);
          if (uningested.isEmpty) break;

          // ignore: avoid_print
          print('[Background] Found ${uningested.length} uningested vital records to sync');

          final ids = <int>[];
          final payloads = <Map<String, dynamic>>[];

          for (final row in uningested) {
            final id = row['_id'] as int?;
            if (id != null) ids.add(id);

            final ts = row['timestamp'] as int?;
            final recordedAt = ts != null
                ? DateTime.fromMillisecondsSinceEpoch(ts)
                : DateTime.now();

            payloads.add(BandVitalsApi.buildVitalPayload(
              patientId: row['patient_id'] as int? ?? patientId,
              deviceId: (row['device_id'] as String?)?.isNotEmpty == true
                  ? row['device_id'] as String
                  : deviceId,
              hr: (row['hr'] as int?) ?? lastValidHr,
              spo2: (row['spo2'] as int?) ?? lastValidSpo2,
              tempC: (row['tempC'] as num?)?.toDouble() ?? lastValidTempC,
              bpSys: (row['bpSys'] as int?) ?? lastValidBpSys,
              bpDia: (row['bpDia'] as int?) ?? lastValidBpDia,
              hrv: (row['hrv'] as int?) ?? lastValidHrv,
              stress: (row['stress'] ?? lastValidStress).toString(),
              steps: (row['steps'] as int?) ?? 0,
              calories: (row['calories'] as num?)?.toDouble() ?? 0.0,
              distanceKm: (row['distanceKm'] as num?)?.toDouble() ?? 0.0,
              battery: (row['battery'] as int?) ?? battery,
              phoneBattery: phoneBattery,
              isConnected: isConnected,
              isRemoved: (row['isRemoved'] == 1) || isRemoved,
              recordedAt: recordedAt,
            ));
          }

          int syncedCount = 0;
          final success = await api.bulkIngest(
            payloads,
            batchSize: 25,
            onBatchSuccess: (startIndex, endIndex) async {
              final batchIds = ids.sublist(startIndex, endIndex);
              await db.markMultipleAsIngested(batchIds);
              syncedCount += batchIds.length;
              if (broadcastedSync && !isManualDisconnect) {
                final remaining = await db.getUningestedCount();
                service.invoke('sync_status', {
                  'isSyncing': true,
                  'pending': remaining,
                });
              }
              // ignore: avoid_print
              print('[Background] ✓ Immediately marked ${batchIds.length} vitals as ingested (progress: $syncedCount/${ids.length})');
            },
          );

          if (success) {
            consecutiveIngestFailures = 0;
            // ignore: avoid_print
            print('[Background] ✓ Synced & marked $syncedCount vitals as ingested');
          } else {
            consecutiveIngestFailures++;
            // ignore: avoid_print
            print('[Background] ✗ Bulk sync interrupted ($syncedCount/${payloads.length} succeeded, remainder will retry)');
            if (consecutiveIngestFailures == 3) {
              Sentry.captureMessage(
                'Cloud Ingestion Failing: 3 consecutive bulk-ingest failures for device $deviceId',
                level: SentryLevel.warning,
                withScope: (scope) {
                  scope.setTag('issue_type', 'bulk_ingest_failure');
                  scope.setTag('device_id', deviceId);
                  scope.setTag('patient_id', patientId.toString());
                },
              );
            }
            break;
          }
        }
      } catch (e, stackTrace) {
        // ignore: avoid_print
        print('[Background] Error during syncPendingVitals: $e');
        Sentry.captureException(e, stackTrace: stackTrace);
      } finally {
        isSyncing = false;
        if (broadcastedSync || isManualDisconnect) {
          service.invoke('sync_status', {
            'isSyncing': false,
            'pending': 0,
          });
        }
      }
    }

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
      onHistoryRecords: (records, cmd, isEnd) async {
        try {
          final db = VitalsDatabase.instance;
          int deduplicatedCount = 0;
          int queuedCount = 0;

          for (final r in records) {
            final minuteAlignedTs = DateTime(
              r.timestamp.year,
              r.timestamp.month,
              r.timestamp.day,
              r.timestamp.hour,
              r.timestamp.minute,
            ).millisecondsSinceEpoch;

            // Check if this time window was already ingested live during active connection
            final alreadyIngested = await db.hasIngestedVitalNear(
              deviceId: deviceId,
              timestamp: minuteAlignedTs,
              windowMs: 90000, // ±1.5 min window
            );

            if (alreadyIngested) {
              deduplicatedCount++;
            } else {
              queuedCount++;
            }

            final recordData = <String, dynamic>{
              'timestamp': minuteAlignedTs,
              'patient_id': profile.id,
              'device_id': deviceId,
              'isIngested': alreadyIngested ? 1 : 0,
            };

            if (r is HistoryBpHrv) {
              recordData['bpSys'] = r.systolic;
              recordData['bpDia'] = r.diastolic;
              recordData['hrv'] = r.hrv;
              recordData['stress'] = r.stress.toString();
              if (r.hr > 0) recordData['hr'] = r.hr;
              if (r.systolic > 0) {
                lastValidBpSys = r.systolic;
                lastValidBpDia = r.diastolic;
              }
              if (r.hrv > 0) lastValidHrv = r.hrv;
              if (r.stress > 0) lastValidStress = r.stress.toString();
            } else if (r is HistorySpo2) {
              recordData['spo2'] = r.spo2;
              if (r.spo2 > 0) lastValidSpo2 = r.spo2;
            } else if (r is HistoryHr) {
              recordData['hr'] = r.hr;
              if (r.hr > 0) lastValidHr = r.hr;
            } else if (r is HistorySteps) {
              recordData['steps'] = r.steps;
              recordData['calories'] = r.calories;
              recordData['distanceKm'] = r.distanceKm;
              if (r.steps > 0) {
                lastValidSteps = r.steps;
                lastValidCalories = r.calories;
                lastValidDistanceKm = r.distanceKm;
              }
            }

            recordData['tempC'] = lastValidTempC;
            recordData['battery'] = session?.currentState.battery ?? -1;

            try {
              await db.upsertVital(recordData);
            } catch (e) {
              // ignore: avoid_print
              print('[Background] Warning: failed to upsert vital record: $e');
            }
          }

          // ignore: avoid_print
          print('[Background] 📦 JBand history sync (cmd 0x${cmd.toRadixString(16)}): $queuedCount records queued for bulk ingest, $deduplicatedCount already covered by live ingest');

          if (isEnd && !isManualDisconnect) {
            final store = AuthTokenStore();
            final repo = AuthRepository(
                baseUrl: 'https://vitalvue-api.genesysailabs.com', store: store);
            final interceptor =
                AuthInterceptor(store: store, repository: repo, onLogout: () {});
            final api = BandVitalsApi(
              baseUrl: 'https://vitalvue-api.genesysailabs.com',
              authInterceptor: interceptor,
            );

            int phoneBattery = -1;
            try {
              phoneBattery = await Battery().batteryLevel;
            } catch (_) {}

            final currentState = session?.currentState ?? const BandState();
            await syncPendingVitals(
              api: api,
              db: db,
              patientId: profile.id,
              deviceId: deviceId,
              phoneBattery: phoneBattery,
              battery: currentState.battery,
              isConnected: currentState.connectionStatus == BleConnectionStatus.connected,
              isRemoved: currentState.isRemoved,
              isHistorySync: true,
            );
          }
        } catch (e, stackTrace) {
          // ignore: avoid_print
          print('[Background] Error in onHistoryRecords: $e');
          Sentry.captureException(e, stackTrace: stackTrace);
        }
      },
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

        // Update the cached values if we received new valid vitals in this state snapshot
        if (state.hr > 0) {
          lastValidHr = state.hr;
        }
        if (state.tempC > 0) {
          lastValidTempC = state.tempC;
        }
        if (state.steps > 0) {
          lastValidSteps = state.steps;
          lastValidCalories = state.calories;
          lastValidDistanceKm = state.distanceKm;
        }
        if (state.spo2 > 0) {
          lastValidSpo2 = state.spo2;
        }
        if (state.systolic != null && state.systolic! > 0) {
          lastValidBpSys = state.systolic!;
          lastValidBpDia = state.diastolic ?? 0;
        }
        if (state.hrv != null && state.hrv! > 0) {
          lastValidHrv = state.hrv!;
        }
        if (state.stress != null && state.stress! > 0) {
          lastValidStress = state.stress!.toString();
        }

        int phoneBattery = -1;
        try {
          phoneBattery = await Battery().batteryLevel;
        } catch (e) {
          // ignore: avoid_print
          print('[Background] Failed to get phone battery level: $e');
        }

        // On manual disconnect or disconnected state, only send a lightweight single disconnect ping.
        // Do NOT insert uningested records into SQLite and do NOT drain historical backlog.
        if (isManualDisconnect || state.connectionStatus == BleConnectionStatus.disconnected) {
          // ignore: avoid_print
          print('[Background] Band disconnected (manual=$isManualDisconnect). Sending single disconnect status to cloud.');
          try {
            await api.ingest(
              patientId: profile.id,
              deviceId: deviceId,
              hr: lastValidHr,
              spo2: lastValidSpo2,
              tempC: lastValidTempC,
              bpSys: lastValidBpSys,
              bpDia: lastValidBpDia,
              hrv: lastValidHrv,
              stress: lastValidStress,
              steps: lastValidSteps,
              calories: lastValidCalories,
              distanceKm: lastValidDistanceKm,
              battery: state.battery,
              phoneBattery: phoneBattery,
              isConnected: false,
              isRemoved: state.isRemoved,
            );
          } catch (e) {
            // ignore: avoid_print
            print('[Background] Failed to send disconnect ingest: $e');
          }
          return;
        }
        
        final vitalData = {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'patient_id': profile.id,
          'device_id': deviceId,
          // Always use cached values so local DB never stores zeros
          'hr': lastValidHr,
          'spo2': lastValidSpo2,
          'tempC': lastValidTempC,
          'bpSys': lastValidBpSys,
          'bpDia': lastValidBpDia,
          'hrv': lastValidHrv,
          'stress': lastValidStress,
          'steps': lastValidSteps,
          'calories': lastValidCalories,
          'distanceKm': lastValidDistanceKm,
          'battery': state.battery,
          'isRemoved': state.isRemoved,
          'isIngested': 0,
        };

        await db.insertVital(vitalData);

        await syncPendingVitals(
          api: api,
          db: db,
          patientId: profile.id,
          deviceId: deviceId,
          phoneBattery: phoneBattery,
          battery: state.battery,
          isConnected: state.connectionStatus == BleConnectionStatus.connected,
          isRemoved: state.isRemoved,
        );

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
        final enableAccidentalAlert =
            await BackgroundPreferences.getEnableAccidentalDisconnectAlert();

        if (enableAccidentalAlert) {
          final enableTts = await BackgroundPreferences.getEnableTts();
          final enablePush = await BackgroundPreferences.getEnablePush();

          if (enableTts) {
            await announceRepeat(patientTts,
                'Warning: Your band was disconnected accidentally. Attempting to reconnect.');
          } else {
            await triggerAlertFeedback();
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
        }
      } else if (isConnected) {
        wasConnected = true;
      }

      // ── Off-Wrist Detection ──
      if (!wasRemoved && state.isRemoved) {
        wasRemoved = true;
        patientBandRemovalTimer?.cancel();
        final enableTts = await BackgroundPreferences.getEnableTts();
        final enablePush = await BackgroundPreferences.getEnablePush();

        if (enableTts) {
          await announceRepeat(patientTts,
              'Warning: Band off wrist detected. Please put your band back on.');
        } else {
          await triggerAlertFeedback();
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

        // Schedule 10-minute follow-up alert if band remains off-wrist
        patientBandRemovalTimer = Timer(const Duration(minutes: 10), () async {
          if (wasRemoved) {
            final followUpTts = await BackgroundPreferences.getEnableTts();
            final followUpPush = await BackgroundPreferences.getEnablePush();

            if (followUpTts) {
              await announceRepeat(patientTts,
                  'Follow-up Warning: Your band has been off-wrist for 10 minutes. Please put your band back on immediately.');
            } else {
              await triggerAlertFeedback();
            }

            if (followUpPush) {
              flutterLocalNotificationsPlugin.show(
                id: 993,
                title: 'Follow-Up: Band Still Off-Wrist',
                body: 'Your band has been off-wrist for over 10 minutes. Please re-wear it immediately.',
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
          }
        });
      } else if (wasRemoved && !state.isRemoved) {
        wasRemoved = false;
        patientBandRemovalTimer?.cancel();
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

