/// Lettura dei dati GS1 contenuti nel Data Matrix delle confezioni di
/// farmaci (bollino "serializzato" previsto dalla direttiva antifalsificazione).
///
/// Nel simbolo ci sono, oltre al codice prodotto, anche la **data di
/// scadenza** e il **lotto**: leggerli evita all'operatore di digitarli.
/// Resta comunque possibile scriverli a mano o farli riconoscere dall'OCR,
/// perché non tutte le confezioni hanno il Data Matrix.
library;

/// FNC1 (GS, 0x1D): separatore dei campi a lunghezza variabile.
final String fnc1 = String.fromCharCode(0x1D);

/// Application Identifier a lunghezza fissa che ci interessano
/// (valore = cifre del dato, AI escluso).
const _fixedLength = <String, int>{
  '00': 18, // SSCC
  '01': 14, // GTIN
  '02': 14, // GTIN contenuto
  '11': 6, // data di produzione
  '12': 6, // data di scadenza commerciale
  '13': 6, // data di confezionamento
  '15': 6, // "preferibilmente entro"
  '16': 6, // vendita entro
  '17': 6, // scadenza
  '20': 2, // variante
};

/// AI a lunghezza variabile che leggiamo (terminati da FNC1 o fine stringa).
const _variableAi = <String>{'10', '21', '30', '240', '241', '710', '711'};

/// Dati utili estratti da un simbolo GS1.
class Gs1Data {
  const Gs1Data({this.gtin, this.expiry, this.lot, this.serial});

  /// AI 01: codice prodotto (per i farmaci italiani contiene l'AIC).
  final String? gtin;

  /// AI 17: data di scadenza.
  final DateTime? expiry;

  /// AI 10: numero di lotto.
  final String? lot;

  /// AI 21: numero seriale della singola confezione.
  final String? serial;

  bool get isEmpty =>
      gtin == null && expiry == null && lot == null && serial == null;
}

/// Interpreta il contenuto grezzo di un barcode come stringa GS1.
///
/// Ritorna `null` se non c'è nulla di riconoscibile: un EAN-13 nudo, per
/// esempio, non è una stringa GS1 e va trattato come prima (finestre di
/// 9 cifre + lookup nel catalogo AIFA).
Gs1Data? parseGs1(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  // Prefisso di simbologia: ]d2 (Data Matrix GS1), ]C1, ]e0, ]Q3...
  if (s.startsWith(']') && s.length > 3) s = s.substring(3);

  // Forma "leggibile" con gli AI tra parentesi.
  if (s.contains('(')) {
    s = s.replaceAllMapped(
      RegExp(r'\((\d{2,4})\)'),
      (m) => '$fnc1${m.group(1)}',
    );
  }

  // Prima si tenta la lettura che spiega tutta la stringa; se il simbolo
  // contiene code di dati non standard ci si accontenta di quello che si
  // riesce a leggere dall'inizio.
  final fields = _scan(s, 0) ?? _scanLenient(s);

  String? gtin;
  DateTime? expiry;
  String? lot;
  String? serial;
  for (final f in fields) {
    switch (f.ai) {
      case '01':
        if (RegExp(r'^\d{14}$').hasMatch(f.value)) gtin = f.value;
      case '17':
        expiry ??= _parseGs1Date(f.value);
      case '10':
        if (f.value.isNotEmpty) lot ??= f.value;
      case '21':
        if (f.value.isNotEmpty) serial ??= f.value;
    }
  }

  final data = Gs1Data(gtin: gtin, expiry: expiry, lot: lot, serial: serial);
  return data.isEmpty ? null : data;
}

/// Un campo letto dal simbolo: identificatore e valore.
class _Field {
  const _Field(this.ai, this.value);
  final String ai;
  final String value;
}

/// Lunghezza massima ammessa per i campi a lunghezza variabile.
const _maxVariableLength = 20;

/// Lettura tollerante: va avanti finché riconosce gli AI e si ferma al primo
/// che non conosce, tenendo quello che ha già letto.
List<_Field> _scanLenient(String s) {
  final fields = <_Field>[];
  var i = 0;
  while (i < s.length) {
    if (s[i] == fnc1) {
      i++;
      continue;
    }
    final ai = _readAi(s, i);
    if (ai == null) break;
    i += ai.length;

    final fixed = _fixedLength[ai];
    if (fixed != null) {
      if (i + fixed > s.length) break;
      fields.add(_Field(ai, s.substring(i, i + fixed)));
      i += fixed;
    } else {
      final end = s.indexOf(fnc1, i);
      fields.add(_Field(ai, end == -1 ? s.substring(i) : s.substring(i, end)));
      i = end == -1 ? s.length : end + 1;
    }
  }
  return fields;
}

/// Legge la stringa a partire da [i] restituendo i campi trovati.
///
/// I lettori non sempre riportano i separatori FNC1: senza di essi non si sa
/// dove finisce un campo a lunghezza variabile (lotto, seriale). In quel caso
/// si prova ogni punto di taglio plausibile e si tiene la lettura che spiega
/// più stringa possibile, così scadenza e lotto non vanno persi.
List<_Field>? _scan(String s, int i) {
  if (i >= s.length) return const [];
  if (s[i] == fnc1) return _scan(s, i + 1);

  final ai = _readAi(s, i);
  if (ai == null) return null;
  final start = i + ai.length;

  final fixed = _fixedLength[ai];
  if (fixed != null) {
    if (start + fixed > s.length) return null;
    final rest = _scan(s, start + fixed);
    if (rest == null) return null;
    return [_Field(ai, s.substring(start, start + fixed)), ...rest];
  }

  // Campo a lunghezza variabile: se c'è il separatore la lunghezza è certa.
  final sep = s.indexOf(fnc1, start);
  if (sep != -1) {
    final rest = _scan(s, sep + 1);
    if (rest == null) return null;
    return [_Field(ai, s.substring(start, sep)), ...rest];
  }

  // Nessun separatore: si cerca il taglio che permette di leggere anche il
  // resto. A parità di validità vince quello che riconosce più campi.
  final maxEnd =
      (start + _maxVariableLength) < s.length ? start + _maxVariableLength : s.length;
  List<_Field>? best;
  for (var end = start + 1; end <= maxEnd; end++) {
    final rest = end == s.length ? const <_Field>[] : _scan(s, end);
    if (rest == null) continue;
    final candidate = [_Field(ai, s.substring(start, end)), ...rest];
    if (best == null || candidate.length > best.length) best = candidate;
  }
  // Nessun taglio regge: il campo arriva a fine stringa (caso più comune).
  return best ?? [_Field(ai, s.substring(start))];
}

/// Legge l'AI a partire da [i]: prima prova a 2 cifre (i più comuni),
/// poi a 3 e 4. Ritorna null se non è un AI che sappiamo trattare.
String? _readAi(String s, int i) {
  for (final len in [2, 3, 4]) {
    if (i + len > s.length) break;
    final ai = s.substring(i, i + len);
    if (!RegExp(r'^\d+$').hasMatch(ai)) return null;
    if (_fixedLength.containsKey(ai) || _variableAi.contains(ai)) return ai;
  }
  return null;
}

/// Data GS1 in formato YYMMDD. Il giorno `00` vale "fine mese".
DateTime? _parseGs1Date(String v) {
  if (!RegExp(r'^\d{6}$').hasMatch(v)) return null;
  final year = 2000 + int.parse(v.substring(0, 2));
  final month = int.parse(v.substring(2, 4));
  final day = int.parse(v.substring(4, 6));
  if (month < 1 || month > 12 || day > 31) return null;

  // Giorno 0 → ultimo giorno del mese (il farmaco è valido fino a fine mese).
  final lastOfMonth = DateTime(year, month + 1, 0).day;
  if (day == 0) return DateTime(year, month, lastOfMonth);
  if (day > lastOfMonth) return null;
  return DateTime(year, month, day);
}

/// Riconosce il contenuto del bollino farmaceutico italiano (la fustella).
///
/// Dentro non c'è né la scadenza né il lotto né l'AIC: c'è il numero di
/// targhetta della singola scatola (9 cifre più una di controllo) e, nel
/// Data Matrix, un codice di sicurezza alfanumerico. Esempio reale letto da
/// una confezione: `06799256350LRUHJ`.
///
/// Serve saperlo riconoscere perché quel numero è lungo come un AIC: cercare
/// lì dentro un codice di 9 cifre significa rischiare di identificare un
/// farmaco diverso da quello che si ha in mano.
bool isItalianBollino(String raw) {
  final s = raw.trim();
  return RegExp(r'^\d{10}$').hasMatch(s) ||
      RegExp(r'^\d{10}[A-Z0-9]{4,8}$', caseSensitive: false).hasMatch(s);
}

/// Ricava il codice AIC a 9 cifre dal GTIN di una confezione italiana.
///
/// I farmaci italiani usano il prefisso GS1 `080`: il GTIN-13 è
/// `080` + AIC (9 cifre) + cifra di controllo, e il GTIN-14 antepone uno 0.
String? aicFromGtin(String gtin) {
  var g = gtin.trim();
  if (!RegExp(r'^\d+$').hasMatch(g)) return null;
  if (g.length == 14 && g.startsWith('0')) g = g.substring(1);
  if (g.length != 13 || !g.startsWith('080')) return null;
  return g.substring(3, 12);
}
