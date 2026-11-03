import 'dart:io';

/// I PDF generati (reintegro, controlli) vengono scritti nella cartella
/// temporanea per poter essere condivisi. Contengono nomi di farmaci e di
/// operatori e, a differenza del database, non sono cifrati: vanno tolti
/// appena non servono più, invece di accumularsi nella cache dell'app.
class TempFiles {
  const TempFiles._();

  /// Cancella dalla cartella [dir] i PDF più vecchi di [maxAge].
  ///
  /// Non solleva mai: è pulizia, non deve impedire la generazione del file.
  static Future<void> purgeOldPdfs(
    Directory dir, {
    Duration maxAge = const Duration(hours: 6),
  }) async {
    try {
      if (!await dir.exists()) return;
      final now = DateTime.now();
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.pdf')) {
          continue;
        }
        final stat = await entity.stat();
        if (now.difference(stat.modified) > maxAge) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Cartella non leggibile o file già rimosso: non è un problema.
    }
  }
}
