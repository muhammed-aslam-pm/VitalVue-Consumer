import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Simple FIFO async mutex lock to serialize database writes without external packages
class _AsyncLock {
  Future<void>? _last;
  Future<T> synchronized<T>(Future<T> Function() action) async {
    final prev = _last;
    final completer = Completer<void>();
    _last = completer.future;
    if (prev != null) {
      try {
        await prev;
      } catch (_) {}
    }
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}

class VitalsDatabase {
  static final VitalsDatabase instance = VitalsDatabase._init();
  static Database? _database;
  final _AsyncLock _writeLock = _AsyncLock();

  VitalsDatabase._init();

  @visibleForTesting
  static void setDatabaseForTesting(Database? db) {
    _database = db;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('vitals_history.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          await db.execute('DROP TABLE IF EXISTS vitals');
          await _createDB(db, newVersion);
        }
      },
      onOpen: (db) async {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_vitals_dedup ON vitals(device_id, isIngested, timestamp)',
        );
      },
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const integerType = 'INTEGER DEFAULT 0';
    const realType = 'REAL DEFAULT 0.0';
    const boolType = 'INTEGER DEFAULT 0';
    const textType = "TEXT DEFAULT '0'";

    await db.execute('''
CREATE TABLE vitals (
  _id $idType,
  timestamp $integerType,
  patient_id $integerType,
  device_id $textType,
  hr $integerType,
  spo2 $integerType,
  tempC $realType,
  bpSys $integerType,
  bpDia $integerType,
  hrv $integerType,
  stress $textType,
  steps $integerType,
  calories $realType,
  distanceKm $realType,
  battery $integerType,
  isRemoved $boolType,
  isIngested $boolType,
  UNIQUE(timestamp, device_id)
  )
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_vitals_dedup ON vitals(device_id, isIngested, timestamp)',
    );
  }

  Future<int> upsertVital(Map<String, dynamic> vital) async {
    return await _writeLock.synchronized(() async {
      final db = await instance.database;
      final mapped = Map<String, dynamic>.from(vital);
      if (mapped.containsKey('isRemoved')) {
        mapped['isRemoved'] = mapped['isRemoved'] == true ? 1 : 0;
      }
      if (mapped.containsKey('isIngested')) {
        mapped['isIngested'] = mapped['isIngested'] == true ? 1 : 0;
      }

      final timestamp = mapped['timestamp'];
      final deviceId = mapped['device_id'];
      
      if (timestamp != null && deviceId != null) {
        final existing = await db.query(
          'vitals',
          where: 'timestamp = ? AND device_id = ?',
          whereArgs: [timestamp, deviceId],
        );

        if (existing.isNotEmpty) {
          final existingRow = existing.first;
          final updateMap = <String, dynamic>{};
          mapped.forEach((key, value) {
            if (value == null) return;
            if (value is num && value <= 0) {
              final oldVal = existingRow[key];
              if (oldVal != null && oldVal is num && oldVal > 0) {
                return; // Keep existing valid positive value
              }
            }
            if (key == 'stress' && (value == '0' || value == 0)) {
              final oldVal = existingRow['stress'];
              if (oldVal != null && oldVal != '0' && oldVal != 0) {
                return; // Keep existing valid stress value
              }
            }
            updateMap[key] = value;
          });

          // Preserve isIngested if already ingested and no new vital value changed
          if (existingRow['isIngested'] == 1 && !mapped.containsKey('forceUningested')) {
            bool changed = false;
            for (final k in ['hr', 'spo2', 'tempC', 'bpSys', 'bpDia', 'hrv']) {
              if (updateMap.containsKey(k) && updateMap[k] != existingRow[k]) {
                changed = true;
                break;
              }
            }
            if (!changed) {
              updateMap['isIngested'] = 1;
            }
          }

          return await db.update(
            'vitals',
            updateMap,
            where: 'timestamp = ? AND device_id = ?',
            whereArgs: [timestamp, deviceId],
          );
        }
      }

      try {
        return await db.insert(
          'vitals',
          mapped,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (_) {
        if (timestamp != null && deviceId != null) {
          return await db.update(
            'vitals',
            mapped,
            where: 'timestamp = ? AND device_id = ?',
            whereArgs: [timestamp, deviceId],
          );
        }
        rethrow;
      }
    });
  }

  Future<int> insertVital(Map<String, dynamic> vital) async {
    return await upsertVital(vital);
  }

  Future<int> getUningestedCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM vitals WHERE isIngested = 0');
    if (result.isNotEmpty) {
      return (result.first['count'] as int?) ?? 0;
    }
    return 0;
  }

  Future<List<Map<String, dynamic>>> getUningestedVitals({int? limit}) async {
    final db = await instance.database;
    return await db.query(
      'vitals',
      where: 'isIngested = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }

  /// Checks whether an already-ingested vital record exists for [deviceId]
  /// within [windowMs] of [timestamp].
  ///
  /// Default windowMs = 90,000 ms (±1.5 minutes), covering the 1-minute window
  /// around [timestamp].
  Future<bool> hasIngestedVitalNear({
    required String deviceId,
    required int timestamp,
    int windowMs = 90000,
  }) async {
    final db = await instance.database;
    final start = timestamp - windowMs;
    final end = timestamp + windowMs;
    final results = await db.query(
      'vitals',
      columns: ['_id'],
      where: 'device_id = ? AND timestamp >= ? AND timestamp <= ? AND isIngested = 1',
      whereArgs: [deviceId, start, end],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getVitalsForLast24Hours() async {
    final db = await instance.database;
    final oneDayAgo = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    return await db.query(
      'vitals',
      where: 'timestamp > ?',
      whereArgs: [oneDayAgo],
      orderBy: 'timestamp ASC',
    );
  }

  Future<void> markAsIngested(int id) async {
    final db = await instance.database;
    await db.update(
      'vitals',
      {'isIngested': 1},
      where: '_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markMultipleAsIngested(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final id in ids) {
      batch.update(
        'vitals',
        {'isIngested': 1},
        where: '_id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> getLastValidHr() async {
    final db = await instance.database;
    final maps = await db.query(
      'vitals',
      columns: ['hr'],
      where: 'hr > ?',
      whereArgs: [0],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first['hr'] as int? ?? 0;
    }
    return 0;
  }

  Future<int> getLastValidSpo2() async {
    final db = await instance.database;
    final maps = await db.query(
      'vitals',
      columns: ['spo2'],
      where: 'spo2 > ?',
      whereArgs: [0],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first['spo2'] as int? ?? 0;
    }
    return 0;
  }

  Future<double> getLastValidTempC() async {
    final db = await instance.database;
    final maps = await db.query(
      'vitals',
      columns: ['tempC'],
      where: 'tempC > ?',
      whereArgs: [0.0],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return (maps.first['tempC'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  Future<Map<String, dynamic>?> getLastValidBp() async {
    final db = await instance.database;
    final maps = await db.query(
      'vitals',
      columns: ['bpSys', 'bpDia', 'hrv', 'stress'],
      where: 'bpSys > ? OR (stress IS NOT NULL AND stress != "0")',
      whereArgs: [0],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<void> cleanInvalidZeroRecords() async {
    final db = await instance.database;
    // Delete partial zero records (inserted by old 10-second history sync)
    await db.delete(
      'vitals',
      where: 'tempC = 0 AND (stress = "0" OR stress IS NULL)',
    );
  }

  Future<void> deleteOldVitals() async {
    final db = await instance.database;
    final oneDayAgo = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    final oneHourFromNow = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
    await db.delete(
      'vitals',
      where: 'timestamp <= ? OR timestamp > ?',
      whereArgs: [oneDayAgo, oneHourFromNow],
    );
  }

  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('vitals');
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
