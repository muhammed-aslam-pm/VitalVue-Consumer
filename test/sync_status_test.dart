import 'package:flutter_test/flutter_test.dart';
import 'package:jband_monitor/bloc/band_monitor_state.dart';
import 'package:jband_monitor/session/band_session_service.dart';
import 'package:jband_monitor/ble/band_ble_client.dart';
import 'package:jband_monitor/db/vitals_database.dart';
import 'package:sqflite/sqflite.dart';

class FakeDatabase extends Fake implements Database {
  String? lastRawQuery;
  List<Map<String, dynamic>> rawQueryResult = [];

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    lastRawQuery = sql;
    return rawQueryResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BandMonitorState Sync Status', () {
    test('BandIdleState has default isSyncing = false and syncRemaining = 0', () {
      const state = BandIdleState();
      expect(state.isSyncing, isFalse);
      expect(state.syncRemaining, 0);
    });

    test('BandConnectedState preserves isSyncing and syncRemaining via copyWith', () {
      const vitals = BandState(hr: 75, spo2: 98);
      const connected = BandConnectedState(vitals, isSyncing: true, syncRemaining: 42);

      expect(connected.isSyncing, isTrue);
      expect(connected.syncRemaining, 42);

      final updatedVitals = connected.copyWith(
        vitals: const BandState(hr: 80, spo2: 99),
      );
      expect(updatedVitals.isSyncing, isTrue);
      expect(updatedVitals.syncRemaining, 42);
      expect(updatedVitals.vitals.hr, 80);

      final syncFinished = updatedVitals.copyWith(
        isSyncing: false,
        syncRemaining: 0,
      );
      expect(syncFinished.isSyncing, isFalse);
      expect(syncFinished.syncRemaining, 0);
    });

    test('BandConnectingState and BandDisconnectedState carry sync properties', () {
      const connecting = BandConnectingState('JCV5', isSyncing: true, syncRemaining: 15);
      expect(connecting.isSyncing, isTrue);
      expect(connecting.syncRemaining, 15);
      expect(connecting.deviceName, 'JCV5');

      const disconnected = BandDisconnectedState(reason: 'Lost signal', isSyncing: false, syncRemaining: 0);
      expect(disconnected.isSyncing, isFalse);
      expect(disconnected.syncRemaining, 0);
      expect(disconnected.reason, 'Lost signal');
    });
  });

  group('VitalsDatabase.getUningestedCount', () {
    late FakeDatabase fakeDb;

    setUp(() {
      fakeDb = FakeDatabase();
      VitalsDatabase.setDatabaseForTesting(fakeDb);
    });

    tearDown(() {
      VitalsDatabase.setDatabaseForTesting(null);
    });

    test('returns count from rawQuery when uningested records exist', () async {
      fakeDb.rawQueryResult = [{'count': 128}];

      final count = await VitalsDatabase.instance.getUningestedCount();
      expect(count, 128);
      expect(fakeDb.lastRawQuery, 'SELECT COUNT(*) as count FROM vitals WHERE isIngested = 0');
    });

    test('returns 0 when rawQuery returns empty list', () async {
      fakeDb.rawQueryResult = [];

      final count = await VitalsDatabase.instance.getUningestedCount();
      expect(count, 0);
    });
  });
}
