import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/cabinet.dart';
import '../models/cabinet_check.dart';
import '../models/medicine.dart';
import '../models/medicine_search_hit.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  // resetOnError:false (default) -> su errore di lettura LANCIA invece di rigenerare la chiave
  // (che renderebbe il DB cifrato irrecuperabile). NON attivare encryptedSharedPreferences:
  // cambierebbe backend e renderebbe illeggibili le chiavi gia' salvate sui device esistenti.
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );
  static const _dbKeyName = 'scadenzapp_db_key';

  Database? _database;
  // Memoizza la FUTURE di apertura: il getter non è atomico tra gli await, quindi
  // più primi-chiamanti concorrenti (es. home loadCabinets + reschedule notifiche
  // all'avvio) potrebbero lanciare _initDatabase() in parallelo → race sul file
  // durante migrazione/self-heal. Condividendo la stessa future apriamo una volta sola.
  Future<Database>? _opening;

  /// Solo per i test e per generare le schermate della scheda dello store:
  /// usa un database già aperto (in memoria, con dati inventati) al posto di
  /// quello cifrato del telefono.
  @visibleForTesting
  void useDatabaseForTests(Database db) {
    _database = db;
    _opening = null;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _opening ??= _initDatabase();
    try {
      _database = await _opening!;
      return _database!;
    } finally {
      _opening = null;
    }
  }

  /// Genera o recupera la chiave di cifratura del DB
  Future<String> _getOrCreateDbKey() async {
    String? key;
    try {
      key = await _secureStorage.read(key: _dbKeyName);
    } catch (_) {
      // Chiave illeggibile (keystore invalidato): rimuovila e rigenerane una.
      // Il vecchio DB cifrato diventa irrecuperabile e verrà ricreato dal self-heal.
      try {
        await _secureStorage.delete(key: _dbKeyName);
      } catch (_) {}
    }
    if (key == null) {
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      key = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await _secureStorage.write(key: _dbKeyName, value: key);
    }
    return key;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'scadenzapp.db');
    final dbKey = await _getOrCreateDbKey();

    // Migrazione: se il DB esiste non cifrato, cifralo
    await _migrateUnencryptedDb(path, dbKey);

    try {
      return await _openVersioned(path, dbKey);
    } catch (_) {
      // Recupero #1: DB cifrato con user_version errato (esito del vecchio bug di
      // migrazione) → ripara la versione SENZA perdere i dati, poi riprova.
      if (await _repairUserVersion(path, dbKey)) {
        try {
          return await _openVersioned(path, dbKey);
        } catch (_) {/* irrecuperabile: cade nel reset qui sotto */}
      }
      // Recupero #2 (ultima spiaggia): DB che non si apre (chiave cambiata,
      // file corrotto, migrazione fallita) → si ricrea vuoto così l'app resta
      // utilizzabile, ma il file vecchio si METTE DA PARTE invece di
      // cancellarlo, e la home lo dice all'utente (setAsideFile).
      setAsideFile = await setAsideDbFiles(path, DateTime.now());
      return await _openVersioned(path, dbKey);
    }
  }

  Future<Database> _openVersioned(String path, String key) {
    return openDatabase(
      path,
      password: key,
      version: 4,
      onCreate: createSchema,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Apre il DB con la chiave SENZA versione (niente onCreate/onUpgrade). Se le tabelle
  /// esistono ma user_version è 0 (DB cifrato creato dalla vecchia migrazione che non
  /// copiava la versione), reimposta user_version così onCreate non riparte più.
  Future<bool> _repairUserVersion(String path, String key) async {
    try {
      final db = await openDatabase(path, password: key);
      final hasCabinets = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='cabinets'"))
          .isNotEmpty;
      final version =
          Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;
      var repaired = false;
      if (hasCabinets && version == 0) {
        // Rileva la versione REALE dello schema: hardcodare 3 sarebbe sbagliato se il
        // DB cifrato ha uno schema più vecchio (v1/v2), perché onUpgrade non girerebbe
        // mai per completare la migrazione. Una volta impostata la versione corretta,
        // l'onUpgrade di _openVersioned porta a termine la migrazione.
        final medicineCols = await db.rawQuery('PRAGMA table_info(medicines)');
        final hasForm = medicineCols.any((c) => c['name'] == 'form');
        final hasLot = medicineCols.any((c) => c['name'] == 'lot');
        final hasCustom = (await db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='custom_medicines'"))
            .isNotEmpty;
        final hasChecks = (await db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='cabinet_checks'"))
            .isNotEmpty;
        final hasSyncCode = (await db.rawQuery('PRAGMA table_info(cabinets)'))
            .any((c) => c['name'] == 'sync_code');
        final detected = (hasLot && hasChecks)
            ? 4
            : (hasForm && hasCustom)
                ? 3
                : (hasSyncCode ? 2 : 1);
        await db.execute('PRAGMA user_version = $detected');
        repaired = true;
      }
      await db.close();
      return repaired;
    } catch (_) {
      // Non si apre nemmeno con la chiave: chiave errata o file corrotto.
      return false;
    }
  }

  /// Se all'apertura il database di prima non si è potuto leggere: il nome
  /// del file messo da parte. La home lo segnala una volta.
  String? setAsideFile;

  /// Rinomina il database e i suoi file accessori in
  /// `<nome>.non-leggibile-AAAAMMGG-HHMMSS`. Ritorna il nuovo nome, o null se
  /// non c'era niente da spostare.
  static Future<String?> setAsideDbFiles(String path, DateTime now) async {
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final aside = '$path.non-leggibile-$stamp';
    var moved = false;
    for (final ext in ['', '-journal', '-wal', '-shm']) {
      final f = File('$path$ext');
      if (await f.exists()) {
        await f.rename('$aside$ext');
        moved = true;
      }
    }
    return moved ? aside : null;
  }

  /// Migra un DB non cifrato a cifrato (solo al primo avvio post-update)
  Future<void> _migrateUnencryptedDb(String path, String key) async {
    try {
      // Prova ad aprire senza password — se funziona, è non cifrato
      final plainDb = await openDatabase(path, readOnly: true);
      final int srcVersion;
      try {
        await plainDb.query('cabinets', limit: 1); // test lettura: lancia se cifrato
        // user_version del DB in chiaro: va ricopiato a mano nel DB cifrato (vedi sotto).
        srcVersion =
            Sqflite.firstIntValue(await plainDb.rawQuery('PRAGMA user_version')) ?? 0;
      } finally {
        // Chiudi SEMPRE plainDb: nel caso (normale) di DB già cifrato la query lancia
        // e senza questo finally l'handle perderebbe a ogni avvio.
        try {
          await plainDb.close();
        } catch (_) {}
      }

      // DB non cifrato trovato: cifra con sqlcipher_export
      final tmpPath = '$path.encrypted';
      // Un .encrypted lasciato da una migrazione interrotta farebbe fallire
      // l'export ("table already exists") per sempre.
      final leftover = File(tmpPath);
      if (await leftover.exists()) await leftover.delete();
      final db = await openDatabase(path);
      await db.execute("ATTACH DATABASE '$tmpPath' AS encrypted KEY '$key'");
      await db.execute("SELECT sqlcipher_export('encrypted')");
      // IMPORTANTE: sqlcipher_export NON copia user_version. Senza questa riga il DB
      // cifrato nasce a versione 0 e openDatabase(version:N) richiama onCreate su tabelle
      // già esistenti → "table already exists" → il DB non si apre più.
      await db.execute("PRAGMA encrypted.user_version = $srcVersion");
      await db.execute("DETACH DATABASE encrypted");
      await db.close();

      // Sostituisci il vecchio DB. Cancella anche i sidecar in chiaro (-journal/-wal/-shm):
      // altrimenti restano su disco copie NON cifrate delle pagine del database.
      for (final ext in ['', '-journal', '-wal', '-shm']) {
        final f = File('$path$ext');
        if (await f.exists()) await f.delete();
      }
      await File(tmpPath).rename(path);
    } catch (_) {
      // DB gia' cifrato o non esiste ancora — niente da fare
    }
  }

  /// Schema completo (versione 4) con i 4 armadietti di partenza.
  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE cabinets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        position INTEGER NOT NULL,
        sync_code TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE medicines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cabinet_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        expiration_date TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        added_at TEXT NOT NULL,
        form TEXT,
        dosage TEXT,
        unit TEXT,
        lot TEXT,
        FOREIGN KEY (cabinet_id) REFERENCES cabinets(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE custom_medicines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE,
        active_ingredient TEXT,
        form TEXT,
        dosage TEXT,
        unit TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(name, dosage, form)
      )
    ''');

    await db.execute('''
      CREATE TABLE cabinet_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cabinet_id INTEGER NOT NULL,
        snapshot_data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (cabinet_id) REFERENCES cabinets(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(_createChecksTable);

    // Default cabinets
    for (int i = 0; i < 4; i++) {
      await db.insert('cabinets', {
        'name': 'Armadietto ${i + 1}',
        'position': i,
        'sync_code': Cabinet.generateSyncCode(),
      });
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add sync_code column
      await db.execute('ALTER TABLE cabinets ADD COLUMN sync_code TEXT');
      // Generate sync codes for existing cabinets
      final existing = await db.query('cabinets');
      for (final row in existing) {
        await db.update(
          'cabinets',
          {'sync_code': Cabinet.generateSyncCode()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      // Create snapshots table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cabinet_snapshots (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cabinet_id INTEGER NOT NULL,
          snapshot_data TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (cabinet_id) REFERENCES cabinets(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE medicines ADD COLUMN form TEXT');
      await db.execute('ALTER TABLE medicines ADD COLUMN dosage TEXT');
      await db.execute('ALTER TABLE medicines ADD COLUMN unit TEXT');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS custom_medicines (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL COLLATE NOCASE,
          active_ingredient TEXT,
          form TEXT,
          dosage TEXT,
          unit TEXT,
          created_at TEXT NOT NULL,
          UNIQUE(name, dosage, form)
        )
      ''');
    }
    if (oldVersion < 4) {
      // Lotto della confezione (dal Data Matrix o digitato) + registro dei
      // controlli periodici dell'armadietto.
      await db.execute('ALTER TABLE medicines ADD COLUMN lot TEXT');
      await db.execute(_createChecksTable);
    }
  }

  /// Registro dei controlli periodici di un armadietto: chi ha controllato,
  /// quando, con quale esito. È la base del report mensile.
  static const _createChecksTable = '''
    CREATE TABLE IF NOT EXISTS cabinet_checks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cabinet_id INTEGER NOT NULL,
      performed_at TEXT NOT NULL,
      operator TEXT NOT NULL,
      checked_count INTEGER NOT NULL DEFAULT 0,
      expired_found INTEGER NOT NULL DEFAULT 0,
      expiring_found INTEGER NOT NULL DEFAULT 0,
      removed_count INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      FOREIGN KEY (cabinet_id) REFERENCES cabinets(id) ON DELETE CASCADE
    )
  ''';

  // --- Cabinets ---

  Future<List<Cabinet>> getCabinets() async {
    final db = await database;
    final maps = await db.query('cabinets', orderBy: 'position');
    return maps.map((m) => Cabinet.fromMap(m)).toList();
  }

  Future<int> createCabinet(String name) async {
    final db = await database;
    final maxPos = Sqflite.firstIntValue(
      await db.rawQuery('SELECT MAX(position) FROM cabinets'),
    );
    return db.insert('cabinets', {
      'name': name,
      'position': (maxPos ?? -1) + 1,
      'sync_code': Cabinet.generateSyncCode(),
    });
  }

  Future<void> updateCabinetName(int id, String name) async {
    final db = await database;
    await db.update('cabinets', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteCabinet(int id) async {
    final db = await database;
    await db.delete('cabinets', where: 'id = ?', whereArgs: [id]);
  }

  /// Carica armadietti con count e nearest expiry in una singola query
  Future<List<Cabinet>> getCabinetsWithStats() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT c.*,
        COUNT(m.id) as medicine_count,
        MIN(m.expiration_date) as nearest_expiry
      FROM cabinets c
      LEFT JOIN medicines m ON m.cabinet_id = c.id
      GROUP BY c.id
      ORDER BY c.position
    ''');
    return maps.map((m) {
      final cabinet = Cabinet.fromMap(m);
      cabinet.medicineCount = (m['medicine_count'] as int?) ?? 0;
      final nearest = m['nearest_expiry'] as String?;
      cabinet.nearestExpiry = nearest != null ? DateTime.parse(nearest) : null;
      return cabinet;
    }).toList();
  }

  // --- Medicines ---

  Future<List<MedicineSearchHit>> searchMedicines(String query) async =>
      searchMedicinesIn(await database, query);

  /// Cerca per nome o per lotto in tutti gli armadietti, senza badare alle
  /// maiuscole; prima ciò che scade prima. Serve soprattutto per i ritiri di
  /// lotto: «ce l'ho? dove?». Sotto le 2 lettere non cerca.
  static Future<List<MedicineSearchHit>> searchMedicinesIn(
      Database db, String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    // % e _ sono jolly per LIKE: qui valgono come lettere.
    final escaped = q
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final pattern = '%$escaped%';
    final rows = await db.rawQuery('''
      SELECT m.*, c.name AS cabinet_name
      FROM medicines m JOIN cabinets c ON c.id = m.cabinet_id
      WHERE m.name LIKE ? ESCAPE '\\' OR m.lot LIKE ? ESCAPE '\\'
      ORDER BY m.expiration_date ASC, m.name ASC
      LIMIT 200
    ''', [pattern, pattern]);
    return rows
        .map((r) => MedicineSearchHit(
              medicine: Medicine.fromMap(r),
              cabinetName: r['cabinet_name'] as String,
            ))
        .toList();
  }

  Future<List<Medicine>> getMedicinesByCabinet(int cabinetId) async {
    final db = await database;
    final maps = await db.query(
      'medicines',
      where: 'cabinet_id = ?',
      whereArgs: [cabinetId],
      orderBy: 'expiration_date ASC',
    );
    return maps.map((m) => Medicine.fromMap(m)).toList();
  }

  Future<int> getMedicineCount(int cabinetId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM medicines WHERE cabinet_id = ?',
      [cabinetId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<DateTime?> getNearestExpiry(int cabinetId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MIN(expiration_date) as nearest FROM medicines WHERE cabinet_id = ?',
      [cabinetId],
    );
    final nearest = result.first['nearest'] as String?;
    return nearest != null ? DateTime.parse(nearest) : null;
  }

  Future<int> insertMedicine(Medicine medicine) async {
    final db = await database;
    return db.insert('medicines', medicine.toMap()..remove('id'));
  }

  /// Insert multiplo con batch (molto più veloce per import)
  Future<void> insertMedicines(List<Medicine> medicines) async {
    if (medicines.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final med in medicines) {
      batch.insert('medicines', med.toMap()..remove('id'));
    }
    await batch.commit(noResult: true);
  }

  /// Tutti i farmaci (per reschedule notifiche)
  Future<List<Medicine>> getAllMedicines() async {
    final db = await database;
    final maps = await db.query('medicines');
    return maps.map((m) => Medicine.fromMap(m)).toList();
  }

  Future<void> updateMedicine(Medicine medicine) async {
    final db = await database;
    await db.update(
      'medicines',
      medicine.toMap(),
      where: 'id = ?',
      whereArgs: [medicine.id],
    );
  }

  Future<void> deleteMedicine(int id) async {
    final db = await database;
    await db.delete('medicines', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllMedicinesInCabinet(int cabinetId) async {
    final db = await database;
    await db.delete('medicines', where: 'cabinet_id = ?', whereArgs: [cabinetId]);
  }

  /// Tutti i farmaci che scadono entro [beforeDate], con nome armadietto
  Future<List<Map<String, dynamic>>> getExpiringMedicines(DateTime beforeDate) async {
    final db = await database;
    final dateStr =
        '${beforeDate.year}-${beforeDate.month.toString().padLeft(2, '0')}-${beforeDate.day.toString().padLeft(2, '0')}';
    return db.rawQuery('''
      SELECT m.*, c.name as cabinet_name
      FROM medicines m
      JOIN cabinets c ON c.id = m.cabinet_id
      WHERE m.expiration_date <= ?
      ORDER BY m.expiration_date ASC
    ''', [dateStr]);
  }

  // --- Custom Medicines ---

  Future<int> insertCustomMedicine(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('custom_medicines', data,
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> getCustomMedicines() async {
    final db = await database;
    return db.query('custom_medicines', orderBy: 'name ASC');
  }

  Future<void> deleteCustomMedicine(int id) async {
    final db = await database;
    await db.delete('custom_medicines', where: 'id = ?', whereArgs: [id]);
  }

  // --- Controlli armadietto ---

  Future<int> insertCabinetCheck(CabinetCheck check) async {
    final db = await database;
    return db.insert('cabinet_checks', check.toMap()..remove('id'));
  }

  /// Controlli compresi nell'intervallo [from, to), dal più recente.
  /// Con [cabinetIds] vuoto o nullo prende tutti gli armadietti.
  Future<List<CabinetCheck>> getChecksBetween(
    DateTime from,
    DateTime to, {
    List<int>? cabinetIds,
  }) async {
    final db = await database;
    final where = StringBuffer('performed_at >= ? AND performed_at < ?');
    final args = <Object>[from.toIso8601String(), to.toIso8601String()];
    if (cabinetIds != null && cabinetIds.isNotEmpty) {
      where.write(
          ' AND cabinet_id IN (${List.filled(cabinetIds.length, '?').join(',')})');
      args.addAll(cabinetIds);
    }
    final maps = await db.query(
      'cabinet_checks',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'performed_at DESC',
    );
    return maps.map(CabinetCheck.fromMap).toList();
  }

  /// Ultimo controllo di ogni armadietto, per capire chi è indietro.
  Future<Map<int, CabinetCheck>> getLastCheckPerCabinet() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT c.* FROM cabinet_checks c
      JOIN (
        SELECT cabinet_id, MAX(performed_at) AS last_at
        FROM cabinet_checks GROUP BY cabinet_id
      ) m ON m.cabinet_id = c.cabinet_id AND m.last_at = c.performed_at
    ''');
    return {
      for (final row in maps)
        row['cabinet_id'] as int: CabinetCheck.fromMap(row),
    };
  }

  Future<void> deleteCabinetCheck(int id) async {
    final db = await database;
    await db.delete('cabinet_checks', where: 'id = ?', whereArgs: [id]);
  }

  // --- Full Backup/Restore ---

  Future<Map<String, dynamic>> exportFullBackup() async {
    final db = await database;
    final cabinets = await db.query('cabinets', orderBy: 'position');
    final medicines = await db.query('medicines');
    final customMeds = await db.query('custom_medicines');
    final checks = await db.query('cabinet_checks');
    return {
      'cabinets': cabinets,
      'medicines': medicines,
      'custom_medicines': customMeds,
      'cabinet_checks': checks,
    };
  }

  Future<Map<String, dynamic>> exportCabinetBackup(int cabinetId) async {
    final db = await database;
    final cabinets = await db.query('cabinets', where: 'id = ?', whereArgs: [cabinetId]);
    final medicines = await db.query('medicines', where: 'cabinet_id = ?', whereArgs: [cabinetId]);
    return {
      'cabinets': cabinets,
      'medicines': medicines,
    };
  }

  Future<void> restoreFullBackup(Map<String, dynamic> data) async {
    final db = await database;
    // Valida PRIMA di cancellare qualsiasi cosa: se la lista armadietti è assente o
    // vuota, cancellare tutto e committare un DB vuoto = perdita totale dei dati.
    final cabinets = data['cabinets'];
    if (cabinets is! List || cabinets.isEmpty) {
      throw Exception('Backup completo non valido o vuoto');
    }
    await db.transaction((txn) async {
      // Pulisci tutto
      await txn.delete('medicines');
      await txn.delete('cabinet_snapshots');
      await txn.delete('cabinet_checks');
      await txn.delete('cabinets');
      await txn.delete('custom_medicines');

      // Ripristina armadietti
      for (final c in cabinets) {
        await txn.insert('cabinets', Map<String, dynamic>.from(c as Map));
      }
      // Ripristina farmaci
      for (final m in (data['medicines'] as List)) {
        await txn.insert('medicines', Map<String, dynamic>.from(m as Map));
      }
      // Ripristina farmaci custom (se presenti)
      if (data['custom_medicines'] != null) {
        for (final cm in (data['custom_medicines'] as List)) {
          await txn.insert('custom_medicines', Map<String, dynamic>.from(cm as Map));
        }
      }
      // Registro controlli: assente nei backup fatti prima della v1.3.
      if (data['cabinet_checks'] != null) {
        for (final ck in (data['cabinet_checks'] as List)) {
          await txn.insert('cabinet_checks', Map<String, dynamic>.from(ck as Map));
        }
      }
    });
  }

  /// Ripristina backup di un singolo armadietto (senza toccare gli altri).
  /// Identità stabile = `sync_code` (NON l'id locale, che varia tra device):
  /// l'armadietto con lo stesso sync_code si aggiorna e se ne sostituiscono i
  /// farmaci; il suo registro dei controlli resta.
  Future<void> restoreCabinetBackup(Map<String, dynamic> data) async =>
      restoreCabinetInto(await database, data);

  static Future<void> restoreCabinetInto(
      Database db, Map<String, dynamic> data) async {
    final cabinets = data['cabinets'] as List;
    if (cabinets.isEmpty) throw Exception('Backup armadietto vuoto');

    // L'id locale del backup non è affidabile su un altro device: identità
    // stabile = sync_code (UNIQUE).
    final backupCabinet = Map<String, dynamic>.from(cabinets.first as Map)
      ..remove('id');
    final syncCode = backupCabinet['sync_code'] as String?;

    await db.transaction((txn) async {
      final existing = syncCode == null
          ? const <Map<String, Object?>>[]
          : await txn.query('cabinets',
              columns: ['id'], where: 'sync_code = ?', whereArgs: [syncCode]);

      final int cabinetId;
      if (existing.isNotEmpty) {
        // L'armadietto che c'è già si AGGIORNA, non si cancella: con la
        // cancellazione ON DELETE CASCADE si portava via anche il registro
        // dei controlli, che nel backup di un solo armadietto non c'è.
        cabinetId = existing.first['id'] as int;
        await txn.update('cabinets', {'name': backupCabinet['name']},
            where: 'id = ?', whereArgs: [cabinetId]);
        await txn.delete('medicines',
            where: 'cabinet_id = ?', whereArgs: [cabinetId]);
      } else {
        // Armadietto nuovo: in fondo all'elenco, non alla posizione che
        // aveva sull'altro telefono.
        final maxPos = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT MAX(position) FROM cabinets'));
        cabinetId = await txn.insert('cabinets', {
          ...backupCabinet,
          'position': (maxPos ?? -1) + 1,
        });
      }

      // Farmaci SENZA id (evita collisioni PK), rimappati all'armadietto.
      for (final m in (data['medicines'] as List)) {
        final row = Map<String, dynamic>.from(m as Map)
          ..remove('id')
          ..['cabinet_id'] = cabinetId;
        await txn.insert('medicines', row);
      }
    });
  }
}
