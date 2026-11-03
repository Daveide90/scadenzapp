import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../utils/aic_utils.dart';

/// Una confezione del catalogo AIFA identificata dal suo AIC.
class AicMedicine {
  final String aic;
  final String denominazione;
  final String descrizione; // es. "20 CPR RIV 500 MG"
  final String pa; // principio attivo
  final String forma; // forma farmaceutica AIFA

  AicMedicine({
    required this.aic,
    required this.denominazione,
    required this.descrizione,
    required this.pa,
    required this.forma,
  });

  String? get dosage => extractDosageFromDescrizione(descrizione);

  /// Forma mappata sulle voci del dropdown dell'app (o null).
  String? get appForm => mapAifaForm(forma);

  /// Nome da mostrare nel campo testo: denominazione (title case)
  /// + principio attivo tra parentesi se diverso.
  String get displayName {
    var name = _titleCase(denominazione);
    if (pa.isNotEmpty &&
        pa.toUpperCase() != 'N.D.' &&
        pa.toUpperCase() != denominazione.toUpperCase()) {
      name = '$name (${pa.toLowerCase()})';
    }
    return name;
  }

  static String _titleCase(String text) => text
      .split(' ')
      .map((w) =>
          w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

/// Catalogo AIFA read-only (asset `aifa_catalog.db.gz`, ~160k confezioni).
///
/// Alla prima richiesta decomprime l'asset nella dir di supporto dell'app
/// (in un Isolate, ri-estrae solo se l'asset cambia) e apre il DB in sola
/// lettura. È separato dal DB cifrato dell'utente: è un catalogo pubblico.
/// Ogni errore rende il servizio silenziosamente non disponibile (lookup
/// → null): il resto dell'app continua a funzionare col matching per nome.
class AifaCatalogService {
  /// Impronta SHA-256 del catalogo compresso.
  static String markerFor(Uint8List compressed) =>
      crypto.sha256.convert(compressed).toString();

  static final AifaCatalogService _instance = AifaCatalogService._();
  factory AifaCatalogService() => _instance;
  AifaCatalogService._();

  static const _assetPath = 'assets/aifa_catalog.db.gz';

  Database? _db;
  Future<Database?>? _opening;

  /// Avvia in anticipo estrazione e apertura (fire-and-forget).
  void warmUp() {
    _open();
  }

  Future<Database?> _open() {
    if (_db != null) return Future.value(_db);
    // Memoizza la future: chiamate concorrenti condividono la stessa apertura.
    return _opening ??= _doOpen().then((db) {
      _db = db;
      return db;
    }).catchError((_) {
      _opening = null; // ritenta alla prossima richiesta
      return null;
    });
  }

  Future<Database?> _doOpen() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'aifa_catalog.db');
    // Contrassegno = impronta del catalogo incluso nell'app: prima era la
    // lunghezza, e un catalogo rigenerato con la stessa lunghezza non si
    // sarebbe mai reinstallato.
    final markerPath = p.join(dir.path, 'aifa_catalog.sha256');

    final assetData = await rootBundle.load(_assetPath);
    final compressed = assetData.buffer
        .asUint8List(assetData.offsetInBytes, assetData.lengthInBytes);
    final assetMarker = await Isolate.run(() => markerFor(compressed));

    final marker = File(markerPath);
    final dbFile = File(dbPath);
    final upToDate = await dbFile.exists() &&
        await marker.exists() &&
        (await marker.readAsString()) == assetMarker;

    if (!upToDate) {
      // Decompressione (~20 MB) fuori dal main isolate per non bloccare la UI.
      final bytes = await Isolate.run<Uint8List>(
          () => Uint8List.fromList(gzip.decode(compressed)));
      final tmp = File('$dbPath.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(dbPath);
      await marker.writeAsString(assetMarker, flush: true);
    }

    return openDatabase(dbPath, readOnly: true);
  }

  /// Cerca una confezione per AIC (9 cifre). Null se non trovata o
  /// se il catalogo non è disponibile.
  Future<AicMedicine?> lookupAic(String aic) async {
    final code = aic.trim();
    if (!isAicCandidate(code)) return null;
    final db = await _open();
    if (db == null) return null;
    try {
      final rows = await db.rawQuery('''
        SELECT c.aic, c.descrizione, f.denominazione, f.pa, f.forma
        FROM confezioni c JOIN farmaci f ON f.cod_farmaco = c.cod_farmaco
        WHERE c.aic = ?
      ''', [code]);
      if (rows.isEmpty) return null;
      final r = rows.first;
      return AicMedicine(
        aic: r['aic'] as String,
        denominazione: r['denominazione'] as String,
        descrizione: r['descrizione'] as String,
        pa: r['pa'] as String,
        forma: r['forma'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}
