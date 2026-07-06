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

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
