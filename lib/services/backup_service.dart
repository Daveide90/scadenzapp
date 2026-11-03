import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:pointycastle/export.dart' as pc;
import '../database/database_helper.dart';
import 'notification_service.dart';

/// Contenuto di un backup decifrato ma NON ancora applicato: permette di
/// mostrare all'utente cosa sta per ripristinare prima di toccare i dati.
class BackupInfo {
  final Map<String, dynamic> data;
  final String type; // 'full' | 'cabinet'
  final String? cabinetName; // solo per type == 'cabinet'
  final int cabinetCount;
  final int medicineCount;
  final DateTime? createdAt;

  BackupInfo({
    required this.data,
    required this.type,
    required this.cabinetName,
    required this.cabinetCount,
    required this.medicineCount,
    required this.createdAt,
  });

  bool get isFull => type != 'cabinet';
}

class BackupService {
  /// Formato 2 (dal 3/11/2026): una sola derivazione PBKDF2-SHA256 a 600.000
  /// iterazioni (OWASP), da cui si ricavano chiave di cifratura e chiave HMAC;
  /// l'HMAC copre intestazione, sale, IV e dati. Il formato 1 (210.000
  /// iterazioni, HMAC solo sui dati) resta leggibile.
  static const _version = 2;
  static const _magic = 'SCADENZAPP_BK';
  static const _pbkdf2IterationsV1 = 210000;
  static const _pbkdf2IterationsV2 = 600000;

  final _db = DatabaseHelper();

  /// Rende un nome armadietto usabile in un nome file.
  static String slugify(String name) {
    final slug = name
        .replaceAll(RegExp(r'[^A-Za-z0-9àèéìóòù]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isEmpty) return 'armadietto';
    return slug.length > 24 ? slug.substring(0, 24) : slug;
  }

  /// Crea un backup cifrato. Ritorna il path del file.
  Future<String> createBackup({
    required String password,
    int? cabinetId,
  }) async {
    final Map<String, dynamic> data;
    if (cabinetId != null) {
      data = await _db.exportCabinetBackup(cabinetId);
    } else {
      data = await _db.exportFullBackup();
    }

    data['_meta'] = {
      'version': _version,
      'type': cabinetId != null ? 'cabinet' : 'full',
      'created_at': DateTime.now().toIso8601String(),
    };

    // Lavoro CPU-intensivo (gzip + PBKDF2 600k + AES + HMAC) in un ISOLATE
    // separato: sul main thread bloccherebbe la UI per secondi → app freezata / ANR.
    final output = await Isolate.run(() => encryptBlob(data, password));

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    // Nome file parlante: si capisce dal nome se è completo o di quale armadietto.
    final String path;
    if (cabinetId != null) {
      final cabinets = data['cabinets'] as List? ?? const [];
      final name = cabinets.isNotEmpty
          ? (cabinets.first as Map)['name'] as String? ?? 'armadietto'
          : 'armadietto';
      path = '${dir.path}/ScadenzApp_armadietto_${slugify(name)}_$ts.bak';
    } else {
      path = '${dir.path}/ScadenzApp_COMPLETO_$ts.bak';
    }
    await File(path).writeAsBytes(output);

    return path;
  }

  /// Decifra e legge un backup SENZA applicarlo: serve per mostrare
  /// all'utente tipo e contenuto prima della conferma di ripristino.
  Future<BackupInfo> readBackup({
    required String filePath,
    required String password,
  }) async {
    final bytes = await File(filePath).readAsBytes();

    // Verifica/decifra/decomprime/parse in un ISOLATE (PBKDF2 + AES + gunzip):
    // lavoro pesante che bloccherebbe la UI. L'accesso al DB resta sul main.
    final data = await Isolate.run(() => decryptAndDecode(bytes, password));

    final meta = data['_meta'] as Map<String, dynamic>?;
    final type = (meta?['type'] as String?) ?? 'full';
    final cabinets = data['cabinets'] as List? ?? const [];
    final medicines = data['medicines'] as List? ?? const [];
    final createdAt = DateTime.tryParse(meta?['created_at'] as String? ?? '');
    final cabinetName = type == 'cabinet' && cabinets.isNotEmpty
        ? (cabinets.first as Map)['name'] as String?
        : null;

    return BackupInfo(
      data: data,
      type: type,
      cabinetName: cabinetName,
      cabinetCount: cabinets.length,
      medicineCount: medicines.length,
      createdAt: createdAt,
    );
  }

  /// Applica un backup già letto con [readBackup].
  Future<String> applyBackup(BackupInfo info) async {
    if (info.type == 'cabinet') {
      await _db.restoreCabinetBackup(info.data);
    } else {
      await _db.restoreFullBackup(info.data);
    }
    // Gli avvisi dei farmaci di prima vanno via, quelli del backup arrivano.
    unawaited(NotificationService().rescheduleAll());
    return info.type == 'cabinet' ? 'armadietto' : 'completo';
  }

  // ---------- Funzioni pure, eseguite in un isolate separato ----------

  /// JSON → gzip → AES-256-CBC + HMAC-SHA256, impacchettato in un blob
  /// (formato 2).
  static Uint8List encryptBlob(Map<String, dynamic> data, String password) {
    final jsonStr = jsonEncode(data);
    final compressed = Uint8List.fromList(gzip.encode(utf8.encode(jsonStr)));

    // Salt + IV casuali
    final rng = Random.secure();
    final salt = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    final ivBytes = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));

    final keys = _deriveV2(password, salt);

    // AES-256-CBC encrypt
    final encrypter =
        Encrypter(AES(Key(keys.enc), mode: AESMode.cbc, padding: 'PKCS7'));
    final encrypted = encrypter.encryptBytes(compressed, iv: IV(ivBytes));

    // Pack: magic(13) + version(1) + salt(32) + iv(16) + hmac(32) + data.
    // HMAC-SHA256 (Encrypt-then-MAC) su tutto tranne sé stesso.
    final header = BytesBuilder()
      ..add(utf8.encode(_magic))
      ..addByte(_version)
      ..add(salt)
      ..add(ivBytes);
    final headerBytes = header.toBytes();
    final digest = crypto.Hmac(crypto.sha256, keys.mac)
        .convert([...headerBytes, ...encrypted.bytes]);

    final output = BytesBuilder()
      ..add(headerBytes)
      ..add(Uint8List.fromList(digest.bytes))
      ..add(encrypted.bytes);
    return output.toBytes();
  }

  /// Verifica HMAC → decifra → decomprime → parse JSON.
  /// Lancia un'eccezione su password errata / file corrotto / non valido.
  static Map<String, dynamic> decryptAndDecode(Uint8List bytes, String password) {
    const magicLen = 13; // _magic.length
    const headerLen = magicLen + 1 + 32 + 16;

    if (bytes.length < headerLen + 32) {
      throw Exception('File non valido');
    }

    final magic = utf8.decode(bytes.sublist(0, magicLen));
    if (magic != _magic) {
      throw Exception('File non valido');
    }

    final version = bytes[magicLen];
    if (version != 1 && version != 2) {
      throw Exception('Versione non supportata');
    }

    final salt = Uint8List.fromList(bytes.sublist(magicLen + 1, magicLen + 33));
    final ivBytes = Uint8List.fromList(bytes.sublist(magicLen + 33, headerLen));
    final storedHmac = bytes.sublist(headerLen, headerLen + 32);
    final encryptedBytes = Uint8List.fromList(bytes.sublist(headerLen + 32));

    // Verifica HMAC PRIMA di decifrare
    final Uint8List encKey;
    final List<int> computed;
    if (version == 1) {
      // Formato 1: due PBKDF2 a 210.000 iterazioni, HMAC solo sui dati.
      final hmacKey =
          _pbkdf2(password, salt, 32, _pbkdf2IterationsV1, suffix: 'hmac');
      computed = crypto.Hmac(crypto.sha256, hmacKey).convert(encryptedBytes).bytes;
      encKey = _pbkdf2(password, salt, 32, _pbkdf2IterationsV1);
    } else {
      final keys = _deriveV2(password, salt);
      computed = crypto.Hmac(crypto.sha256, keys.mac).convert(
          [...bytes.sublist(0, headerLen), ...encryptedBytes]).bytes;
      encKey = keys.enc;
    }
    if (!_constantTimeEquals(computed, storedHmac)) {
      throw Exception('Password errata o file corrotto');
    }

    // Limita dimensione ciphertext (10MB max — un DB realistico è molto più piccolo)
    if (encryptedBytes.length > 10 * 1024 * 1024) {
      throw Exception('File di backup troppo grande');
    }

    // Decrypt
    final encrypter = Encrypter(AES(Key(encKey), mode: AESMode.cbc, padding: 'PKCS7'));
    final decrypted = encrypter.decryptBytes(Encrypted(encryptedBytes), iv: IV(ivBytes));

    // Decompress
    final decompressed = gzip.decode(decrypted);
    if (decompressed.length > 50 * 1024 * 1024) {
      throw Exception('Backup troppo grande');
    }

    return jsonDecode(utf8.decode(decompressed)) as Map<String, dynamic>;
  }

  /// Formato 2: una sola PBKDF2 (la parte lenta), poi due chiavi separate
  /// ricavate con HMAC dalla chiave madre (costo trascurabile).
  static ({Uint8List enc, Uint8List mac}) _deriveV2(
      String password, Uint8List salt) {
    final master = _pbkdf2(password, salt, 32, _pbkdf2IterationsV2, suffix: '');
    Uint8List sub(String label) => Uint8List.fromList(
        crypto.Hmac(crypto.sha256, master).convert(utf8.encode(label)).bytes);
    return (enc: sub('scadenzapp-enc'), mac: sub('scadenzapp-mac'));
  }

  /// PBKDF2-HMAC-SHA256
  static Uint8List _pbkdf2(
      String password, Uint8List salt, int keyLen, int iterations,
      {String suffix = 'enc'}) {
    final params = pc.Pbkdf2Parameters(
      Uint8List.fromList(salt + utf8.encode(suffix)),
      iterations,
      keyLen,
    );
    final kdf = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    kdf.init(params);
    return kdf.process(Uint8List.fromList(utf8.encode(password)));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
