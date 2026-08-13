import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class VitalsDatabase {
  static final VitalsDatabase instance = VitalsDatabase._init();
  static Database? _database;

  VitalsDatabase._init();

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
  }

  Future<int> upsertVital(Map<String, dynamic> vital) async {
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
        return await db.update(
          'vitals',
          mapped,
          where: 'timestamp = ? AND device_id = ?',
          whereArgs: [timestamp, deviceId],
        );
      }
    }
    return await db.insert('vitals', mapped);
  }

  Future<int> insertVital(Map<String, dynamic> vital) async {
    final db = await instance.database;
    // ensure bools are integers
    final mapped = Map<String, dynamic>.from(vital);
    if (mapped.containsKey('isRemoved')) {
      mapped['isRemoved'] = mapped['isRemoved'] == true ? 1 : 0;
    }
    if (mapped.containsKey('isIngested')) {
      mapped['isIngested'] = mapped['isIngested'] == true ? 1 : 0;
    }
    return await db.insert('vitals', mapped);
  }

  Future<List<Map<String, dynamic>>> getUningestedVitals() async {
    final db = await instance.database;
    return await db.query(
      'vitals',
      where: 'isIngested = ?',
      whereArgs: [0],
    );
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
