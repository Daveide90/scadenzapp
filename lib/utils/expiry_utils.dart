import 'package:flutter/material.dart';

enum ExpiryStatus { expired, critical, warning, ok }

/// Soglie scelte dall'utente nella schermata del reintegro (rossa 1 o 2
/// mesi, gialla da 3 a 6), valide in tutta l'app: home, armadietti e
/// reintegro colorano allo stesso modo. Caricate all'avvio in main.dart.
class ExpiryThresholds {
  ExpiryThresholds._();
  static int redMonths = 1;
  static int yellowMonths = 3;
}

/// Stato di una scadenza per colori ed etichette. Confronta le date, non le
/// ore: con `difference().inDays` il giorno dopo il cambio dell'ora legale
/// (23 ore) una confezione scaduta risultava ancora «in scadenza».
ExpiryStatus getExpiryStatus(DateTime expirationDate, {DateTime? now}) {
  switch (classifyRestock(
    expirationDate,
    redMonths: ExpiryThresholds.redMonths,
    yellowMonths: ExpiryThresholds.yellowMonths,
    now: now,
  )) {
    case RestockBand.expired:
      return ExpiryStatus.expired;
    case RestockBand.red:
      return ExpiryStatus.critical;
    case RestockBand.yellow:
      return ExpiryStatus.warning;
    case RestockBand.none:
      return ExpiryStatus.ok;
  }
}

Color getExpiryColor(DateTime expirationDate) {
  switch (getExpiryStatus(expirationDate)) {
    case ExpiryStatus.expired:
      return Colors.red;
    case ExpiryStatus.critical:
      return Colors.orange;
    case ExpiryStatus.warning:
      return Colors.amber.shade700;
    case ExpiryStatus.ok:
      return Colors.green;
  }
}

/// Colori per il TESTO delle scadenze (date, etichette, titoli di sezione).
/// Le tinte vive di [getExpiryColor] su bianco vanno da 2,0:1 a 3,7:1, sotto
/// il 4,5:1 che le linee guida di accessibilità (WCAG 2.1, livello AA)
/// chiedono per il testo, e con luce forte non si leggono. Queste stanno
/// sopra 4,5:1 anche sulla tinta chiara dei riquadri. Le tinte vive restano
/// per barre, icone e pallini.
Color expiryTextColorFor(ExpiryStatus status) {
  switch (status) {
    case ExpiryStatus.expired:
      return const Color(0xFFB71C1C);
    case ExpiryStatus.critical:
      return const Color(0xFFBF360C);
    case ExpiryStatus.warning:
      return const Color(0xFF8A5300);
    case ExpiryStatus.ok:
      return const Color(0xFF1B5E20);
  }
}

Color getExpiryTextColor(DateTime expirationDate) =>
    expiryTextColorFor(getExpiryStatus(expirationDate));

/// Come [expiryTextColorFor], per le fasce del reintegro e dei controlli.
Color restockTextColor(RestockBand band) {
  switch (band) {
    case RestockBand.expired:
      return expiryTextColorFor(ExpiryStatus.expired);
    case RestockBand.red:
      return expiryTextColorFor(ExpiryStatus.critical);
    case RestockBand.yellow:
      return expiryTextColorFor(ExpiryStatus.warning);
    case RestockBand.none:
      return const Color(0xFF616161);
  }
}

String getExpiryLabel(DateTime expirationDate) {
  switch (getExpiryStatus(expirationDate)) {
    case ExpiryStatus.expired:
      return 'Scaduto';
    case ExpiryStatus.critical:
      return 'In scadenza';
    case ExpiryStatus.warning:
      return 'Attenzione';
    case ExpiryStatus.ok:
      return 'OK';
  }
}

// --- Classificazione per la schermata "Da reintegrare" ---
// Soglie scelte dall'utente: rossa (1-2 mesi) e gialla (3-6 mesi).

enum RestockBand { expired, red, yellow, none }

/// Aggiunge [months] mesi a [date] in modo mese-accurato (Dart normalizza
/// gli overflow di giorno, es. 31 gen + 1 mese -> inizio marzo).
DateTime addMonths(DateTime date, int months) =>
    DateTime(date.year, date.month + months, date.day);

/// Classifica un farmaco in base alla data di scadenza e alle soglie scelte.
/// - [redMonths]: 1 o 2 (entro quanti mesi conta come "in scadenza", rosso)
/// - [yellowMonths]: 3..6 (entro quanti mesi conta come "attenzione", giallo)
/// [now] è iniettabile per i test (default: adesso).
RestockBand classifyRestock(
  DateTime expirationDate, {
  required int redMonths,
  required int yellowMonths,
  DateTime? now,
}) {
  final base = now ?? DateTime.now();
  final today = DateTime(base.year, base.month, base.day);
  final expiry =
      DateTime(expirationDate.year, expirationDate.month, expirationDate.day);

  if (expiry.isBefore(today)) return RestockBand.expired;

  final redLimit = addMonths(today, redMonths);
  final yellowLimit = addMonths(today, yellowMonths);

  if (!expiry.isAfter(redLimit)) return RestockBand.red; // expiry <= redLimit
  if (!expiry.isAfter(yellowLimit)) return RestockBand.yellow;
  return RestockBand.none;
}

/// Limiti dei calendari: gli stessi del parser delle date (2020-2045),
/// così una data letta dall'OCR si può sempre aprire e correggere.
final firstPickableDate = DateTime(2020);
final lastPickableDate = DateTime(2045, 12, 31);

/// Data iniziale del calendario dentro i limiti.
DateTime clampToPickable(DateTime d) => d.isBefore(firstPickableDate)
    ? firstPickableDate
    : (d.isAfter(lastPickableDate) ? lastPickableDate : d);
