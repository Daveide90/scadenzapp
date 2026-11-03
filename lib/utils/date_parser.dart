// Parser date di scadenza da testo OCR.
// Approccio multi-strategia: analizza riga per riga,
// corregge errori OCR, gestisce multi-linea e formati senza separatore.

import 'package:intl/intl.dart';

/// Candidato data visibile dall'esterno
class DateCandidate {
  final DateTime date;
  final int score;
  String get label => DateFormat('MM/yyyy').format(date);
  String get fullLabel => DateFormat('dd/MM/yyyy').format(date);

  DateCandidate({required this.date, required this.score});
}

/// Trova tutte le date candidate nel testo OCR (deduplicate, ordinate per score).
List<DateCandidate> findExpiryDateCandidates(List<String> lines) {
  final candidates = _collectCandidates(lines);

  // Filtra anni implausibili
  candidates.removeWhere((c) => c.date.year < 2020 || c.date.year > 2045);
  if (candidates.isEmpty) return [];

  // Deduplica: stesso mese+anno → tieni score più alto
  final best = <String, _DateCandidate>{};
  for (final c in candidates) {
    final key = '${c.date.year}-${c.date.month}';
    if (!best.containsKey(key) || c.score > best[key]!.score) {
      best[key] = c;
    }
  }

  // Ordina preferendo le date future: una data passata (produzione) non deve
  // mai battere una futura (scadenza). A parità di score vince la più tardiva.
  final sorted = best.values.toList()..sort(_compareCandidates);
  return sorted
      .where((c) => c.score > 0)
      .map((c) => DateCandidate(date: c.date, score: c.score))
      .toList();
}

/// Cerca la data di scadenza nel testo OCR (lista di righe).
/// Usa multiple strategie e ritorna la migliore.
DateTime? parseExpiryDate(String fullText) {
  if (fullText.trim().isEmpty) return null;
  final lines = fullText
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  return parseExpiryDateFromLines(lines);
}

/// La data scelta è sempre il primo candidato di [findExpiryDateCandidates]:
/// una sola logica, così scansione e suggerimenti non possono divergere.
DateTime? parseExpiryDateFromLines(List<String> lines) {
  final candidates = findExpiryDateCandidates(lines);
  return candidates.isEmpty ? null : candidates.first.date;
}

/// Tutte le strategie, riga per riga.
List<_DateCandidate> _collectCandidates(List<String> lines) {
  final candidates = <_DateCandidate>[];

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].toUpperCase().trim();
    if (line.isEmpty) continue;

    // Strategia 1: Parse diretto sulla riga
    _extractAllDates(line, candidates);

    // Strategia 2: Correzione errori OCR e riprova
    final corrected = _ocrCorrectForDate(line);
    if (corrected != line) {
      _extractAllDates(corrected, candidates, scoreBonus: -5); // lieve penalità
    }

    // Strategia 3: Se la riga ha un keyword, combina con la riga successiva
    if (_hasExpiryKeyword(line) && i + 1 < lines.length) {
      final nextLine = lines[i + 1].toUpperCase().trim();
      // La data potrebbe essere sulla riga dopo
      _extractAllDates('$line $nextLine', candidates);
      // Prova anche solo la riga dopo con bonus keyword
      _extractAllDates(nextLine, candidates, forceKeywordContext: true);
      // OCR corrected della riga dopo
      final nextCorrected = _ocrCorrectForDate(nextLine);
      if (nextCorrected != nextLine) {
        _extractAllDates(nextCorrected, candidates, forceKeywordContext: true, scoreBonus: -5);
      }
    }

    // Strategia 4: Date senza separatore (062026, 0626), anche corrette
    _extractNoSeparatorDates(line, candidates);
    if (corrected != line) {
      _extractNoSeparatorDates(corrected, candidates, scoreBonus: -5);
    }
  }

  // Strategia 5: Tutto il testo concatenato come fallback
  if (candidates.isEmpty) {
    final fullText = lines.join(' ').toUpperCase();
    _extractAllDates(fullText, candidates);
    _extractNoSeparatorDates(fullText, candidates);
  }
  return candidates;
}

// ─── Candidato ──────────────────────────────────────────────

class _DateCandidate {
  final DateTime date;
  int score;

  _DateCandidate({required this.date, required this.score});
}

// ─── Prefissi di scadenza ───────────────────────────────────

const _expiryKeywords = [
  'SCAD', 'SCADENZA', 'EXP', 'EXPIRY', 'EXPIRY DATE',
  'BB', 'BEST BEFORE', 'USE BY', 'USARE ENTRO',
  'UTILIZZARE ENTRO', 'DA CONSUMARSI', 'CONSUMARSI ENTRO',
  'VAL', 'VALIDITA',
  '\u23F3', '\u231B', // ⏳ ⌛
];

/// Parole vicine che indicano NON è una data scadenza
const _noiseKeywords = [
  'LOT', 'LOTTO', 'BATCH', 'AIC', 'REF', 'SN',
  'CODICE', 'COD', 'QTA', 'PZ', 'ATC', 'NR',
];

// Keyword corte (≤3 caratteri, es. BB, VAL, EXP) richiedono un confine
// di parola: altrimenti "ABBOTT" matcha "BB" e "VALSARTAN" matcha "VAL",
// gonfiando erroneamente lo score. Compilate una volta sola: il parser gira
// a ogni fotogramma della scansione.
final _shortKeywordRes = [
  for (final kw in _expiryKeywords)
    if (kw.length <= 3 && RegExp(r'[A-Z]').hasMatch(kw))
      RegExp('(?<![A-Z])${RegExp.escape(kw)}(?![A-Z])'),
];
final _longKeywords = [
  for (final kw in _expiryKeywords)
    if (!(kw.length <= 3 && RegExp(r'[A-Z]').hasMatch(kw))) kw,
];

bool _hasExpiryKeyword(String text) =>
    _longKeywords.any(text.contains) ||
    _shortKeywordRes.any((re) => re.hasMatch(text));

bool _isNearNoiseKeyword(String text, int pos) {
  final start = (pos - 15).clamp(0, text.length);
  final context = text.substring(start, pos);
  for (final kw in _noiseKeywords) {
    if (context.contains(kw)) return true;
  }
  return false;
}

// ─── Correzione OCR ─────────────────────────────────────────

/// Corregge errori OCR comuni nei contesti numerici.
/// Solo i caratteri adiacenti a cifre vengono corretti.
String _ocrCorrectForDate(String text) {
  if (text.isEmpty) return text;
  final buf = StringBuffer();

  for (int i = 0; i < text.length; i++) {
    final c = text[i];
    final nearDigit = _hasNearbyDigit(text, i);

    if (nearDigit) {
      switch (c) {
        case 'O':
        case 'o':
          buf.write('0');
          break;
        case 'l':
        case 'I':
          buf.write('1');
          break;
        case 'Z':
        case 'z':
          buf.write('2');
          break;
        case 'S':
        case 's':
          // Solo se circondato da cifre (non 'SCAD')
          if (_isDigit(text, i - 1) && _isDigit(text, i + 1)) {
            buf.write('5');
          } else {
            buf.write(c);
          }
          break;
        case 'B':
          // Solo se circondato da cifre (non 'BB', 'BEST BEFORE')
          if (_isDigit(text, i - 1) && _isDigit(text, i + 1)) {
            buf.write('8');
          } else {
            buf.write(c);
          }
          break;
        default:
          buf.write(c);
      }
    } else {
      buf.write(c);
    }
  }
  return buf.toString();
}

bool _hasNearbyDigit(String text, int pos) {
  for (int d = -2; d <= 2; d++) {
    final p = pos + d;
    if (p >= 0 && p < text.length && p != pos) {
      final c = text.codeUnitAt(p);
      if (c >= 48 && c <= 57) return true; // 0-9
    }
  }
  return false;
}

bool _isDigit(String text, int pos) {
  if (pos < 0 || pos >= text.length) return false;
  final c = text.codeUnitAt(pos);
  return c >= 48 && c <= 57;
}

// ─── Estrazione date con separatore ─────────────────────────

void _extractAllDates(
  String text,
  List<_DateCandidate> out, {
  bool forceKeywordContext = false,
  int scoreBonus = 0,
}) {
  // Pattern con prefisso esplicito + MM/YYYY o MM-YYYY
  _tryPrefixedDates(text, out, scoreBonus);

  // Pattern con prefisso + nome mese
  _tryPrefixedMonthNames(text, out, scoreBonus);

  // Nome mese + anno (senza prefisso)
  _tryMonthNameDates(text, out, forceKeywordContext, scoreBonus);

  // DD/MM/YYYY
  _tryFullDates(text, out, forceKeywordContext, scoreBonus);

  // DD/MM/YY (anno a 2 cifre, giorno-primo, locale EU)
  _tryFullDatesShortYear(text, out, forceKeywordContext, scoreBonus);

  // MM/YYYY
  _tryMMYYYY(text, out, forceKeywordContext, scoreBonus);

  // MM/YY
  _tryMMYY(text, out, forceKeywordContext, scoreBonus);

  // YYYY/MM (anno-primo senza keyword)
  _tryYYYYMM(text, out, forceKeywordContext, scoreBonus);
}

final _kwPattern = _expiryKeywords.map(RegExp.escape).join('|');
final _monthPattern = _monthNames.keys.join('|');

// Prefisso + MM sep YYYY (separatore: /, -, ., o spazi)
final _prefixedMonthYear = RegExp('($_kwPattern)\\.?\\s*[:\\-]?\\s*(\\d{1,2})[\\s/\\-\\.]+([\\d]{2,4})');
// Prefisso + YYYY sep MM
final _prefixedYearMonth = RegExp('($_kwPattern)\\.?\\s*[:\\-]?\\s*(\\d{4})[\\s/\\-\\.]+([\\d]{1,2})');
// Prefisso + DD/MM/YYYY
final _prefixedFull = RegExp('($_kwPattern)\\.?\\s*[:\\-]?\\s*(\\d{1,2})[\\s/\\-\\.]+(\\d{1,2})[\\s/\\-\\.]+(\\d{4})');
// Prefisso + nome mese
final _prefixedMonthName = RegExp('($_kwPattern)\\.?\\s*[:\\-]?\\s*($_monthPattern)\\.?\\s*(\\d{2,4})');
// MESE ANNO e ANNO MESE
final _monthNameYear = RegExp('($_monthPattern)\\.?\\s*(\\d{2,4})');
final _yearMonthName = RegExp('(\\d{4})\\s*($_monthPattern)\\.?');

void _tryPrefixedDates(String text, List<_DateCandidate> out, int bonus) {
  for (final m in _prefixedMonthYear.allMatches(text)) {
    final date = _buildDate(m.group(2)!, m.group(3)!);
    if (date != null) {
      out.add(_DateCandidate(date: date, score: 100 + bonus));
    }
  }

  for (final m in _prefixedYearMonth.allMatches(text)) {
    final date = _buildDate(m.group(3)!, m.group(2)!);
    if (date != null) {
      out.add(_DateCandidate(date: date, score: 100 + bonus));
    }
  }

  for (final m in _prefixedFull.allMatches(text)) {
    final day = int.tryParse(m.group(2)!);
    final month = int.tryParse(m.group(3)!);
    final year = int.tryParse(m.group(4)!);
    final date = (day != null && month != null && year != null)
        ? _validDate(year, month, day)
        : null;
    if (date != null) {
      out.add(_DateCandidate(date: date, score: 105 + bonus));
    }
  }
}

void _tryPrefixedMonthNames(String text, List<_DateCandidate> out, int bonus) {
  for (final m in _prefixedMonthName.allMatches(text)) {
    final month = _monthNames[m.group(2)!];
    final year = _parseYear(m.group(3)!);
    if (month != null && year != null) {
      final lastDay = DateTime(year, month + 1, 0).day;
      out.add(_DateCandidate(date: DateTime(year, month, lastDay), score: 110 + bonus));
    }
  }
}

void _tryMonthNameDates(String text, List<_DateCandidate> out, bool forceKw, int bonus) {
  // MESE ANNO
  for (final m in _monthNameYear.allMatches(text)) {
    final month = _monthNames[m.group(1)!];
    final year = _parseYear(m.group(2)!);
    if (month != null && year != null) {
      final lastDay = DateTime(year, month + 1, 0).day;
      final kwNear = forceKw || _hasExpiryKeyword(text);
      out.add(_DateCandidate(date: DateTime(year, month, lastDay), score: (kwNear ? 80 : 50) + bonus));
    }
  }

  // ANNO MESE
  for (final m in _yearMonthName.allMatches(text)) {
    final year = int.tryParse(m.group(1)!);
    final month = _monthNames[m.group(2)!];
    if (year != null && month != null) {
      final lastDay = DateTime(year, month + 1, 0).day;
      final kwNear = forceKw || _hasExpiryKeyword(text);
      out.add(_DateCandidate(date: DateTime(year, month, lastDay), score: (kwNear ? 80 : 50) + bonus));
    }
  }
}

void _tryFullDates(String text, List<_DateCandidate> out, bool forceKw, int bonus) {
  final p = RegExp(r'(?<!\d)(\d{1,2})[\s/\-\.]+(\d{1,2})[\s/\-\.]+(\d{4})(?!\d)');
  for (final m in p.allMatches(text)) {
    final day = int.tryParse(m.group(1)!);
    final month = int.tryParse(m.group(2)!);
    final year = int.tryParse(m.group(3)!);
    if (day == null || month == null || year == null) continue;
    final date = _validDate(year, month, day);
    if (date == null) continue;
    if (_isNearNoiseKeyword(text, m.start)) continue;

    final kwNear = forceKw || _hasExpiryKeyword(text);
    out.add(_DateCandidate(date: date, score: (kwNear ? 70 : 35) + bonus));
  }
}

void _tryFullDatesShortYear(String text, List<_DateCandidate> out, bool forceKw, int bonus) {
  // DD/MM/YY giorno-primo (locale EU): es. 31/12/26, 31-12-26, 01.06.27.
  // Anno a 2 cifre risolto col pivot di secolo (_parseYear): 26 → 2026.
  final p = RegExp(r'(?<!\d)(\d{1,2})[\s/\-\.]+(\d{1,2})[\s/\-\.]+(\d{2})(?!\d)');
  for (final m in p.allMatches(text)) {
    final day = int.tryParse(m.group(1)!);
    final month = int.tryParse(m.group(2)!);
    final year = _parseYear(m.group(3)!);
    if (day == null || month == null || year == null) continue;
    final date = _validDate(year, month, day);
    if (date == null) continue;
    if (year < 2020 || year > 2045) continue;
    if (_isNearNoiseKeyword(text, m.start)) continue;

    final kwNear = forceKw || _hasExpiryKeyword(text);
    out.add(_DateCandidate(date: date, score: (kwNear ? 70 : 35) + bonus));
  }
}

void _tryMMYYYY(String text, List<_DateCandidate> out, bool forceKw, int bonus) {
  final p = RegExp(r'(?<!\d)(\d{2})[\s/\-\.]+(\d{4})(?!\d)');
  for (final m in p.allMatches(text)) {
    final month = int.tryParse(m.group(1)!);
    if (month == null || month < 1 || month > 12) continue;
    if (_isNearNoiseKeyword(text, m.start)) continue;

    final date = _buildDate(m.group(1)!, m.group(2)!);
    if (date == null) continue;

    final kwNear = forceKw || _hasExpiryKeyword(text);
    out.add(_DateCandidate(date: date, score: (kwNear ? 65 : 30) + bonus));
  }
}

void _tryMMYY(String text, List<_DateCandidate> out, bool forceKw, int bonus) {
  final p = RegExp(r'(?<!\d)(\d{2})[\s/\-\.]+(\d{2})(?!\d)');
  for (final m in p.allMatches(text)) {
    final month = int.tryParse(m.group(1)!);
    if (month == null || month < 1 || month > 12) continue;
    if (_isNearNoiseKeyword(text, m.start)) continue;

    final date = _buildDate(m.group(1)!, m.group(2)!);
    if (date == null) continue;

    // MM/YY molto ambiguo: richiede keyword vicina o contesto forte
    final kwNear = forceKw || _hasExpiryKeyword(text);
    out.add(_DateCandidate(date: date, score: (kwNear ? 45 : 8) + bonus));
  }
}

void _tryYYYYMM(String text, List<_DateCandidate> out, bool forceKw, int bonus) {
  final p = RegExp(r'(?<!\d)(\d{4})[\s/\-\.]+(\d{1,2})(?!\d)');
  for (final m in p.allMatches(text)) {
    final year = int.tryParse(m.group(1)!);
    final month = int.tryParse(m.group(2)!);
    if (year == null || month == null) continue;
    if (year < 2020 || year > 2045) continue;
    if (month < 1 || month > 12) continue;
    if (_isNearNoiseKeyword(text, m.start)) continue;

    final lastDay = DateTime(year, month + 1, 0).day;
    final kwNear = forceKw || _hasExpiryKeyword(text);
    out.add(_DateCandidate(
      date: DateTime(year, month, lastDay),
      score: (kwNear ? 60 : 25) + bonus,
    ));
  }
}

// ─── Date senza separatore ──────────────────────────────────

void _extractNoSeparatorDates(String text, List<_DateCandidate> out, {int scoreBonus = 0}) {
  // MMYYYY: 062026 (6 cifre, non parte di numero più lungo)
  final p1 = RegExp(r'(?<!\d)(\d{2})(\d{4})(?!\d)');
  for (final m in p1.allMatches(text)) {
    final month = int.tryParse(m.group(1)!);
    final year = int.tryParse(m.group(2)!);
    if (month == null || year == null) continue;
    if (month < 1 || month > 12) continue;
    if (year < 2020 || year > 2045) continue;
    if (_isNearNoiseKeyword(text, m.start)) continue;

    final lastDay = DateTime(year, month + 1, 0).day;
    final kwNear = _hasExpiryKeyword(text);
    // Basso score perché molto ambiguo, ma se c'è keyword va bene
    out.add(_DateCandidate(
      date: DateTime(year, month, lastDay),
      score: (kwNear ? 55 : 12) + scoreBonus,
    ));
  }

  // MMYY: 0626 (4 cifre) - solo con keyword vicina
  final p2 = RegExp(r'(?<!\d)(\d{2})(\d{2})(?!\d)');
  for (final m in p2.allMatches(text)) {
    final month = int.tryParse(m.group(1)!);
    final yearShort = int.tryParse(m.group(2)!);
    if (month == null || yearShort == null) continue;
    if (month < 1 || month > 12) continue;
    if (_isNearNoiseKeyword(text, m.start)) continue;

    final year = yearShort < 80 ? 2000 + yearShort : 1900 + yearShort;
    if (year < 2020 || year > 2045) continue;

    // Solo se vicino a keyword scadenza (troppo ambiguo altrimenti)
    if (!_hasExpiryKeyword(text)) continue;

    final lastDay = DateTime(year, month + 1, 0).day;
    out.add(_DateCandidate(
      date: DateTime(year, month, lastDay),
      score: 35 + scoreBonus,
    ));
  }
}

// ─── Nomi mesi ──────────────────────────────────────────────

final _monthNames = {
  'GEN': 1, 'GENNAIO': 1,
  'FEB': 2, 'FEBBRAIO': 2,
  'MAR': 3, 'MARZO': 3,
  'APR': 4, 'APRILE': 4,
  'MAG': 5, 'MAGGIO': 5,
  'GIU': 6, 'GIUGNO': 6,
  'LUG': 7, 'LUGLIO': 7,
  'AGO': 8, 'AGOSTO': 8,
  'SET': 9, 'SETTEMBRE': 9,
  'OTT': 10, 'OTTOBRE': 10,
  'NOV': 11, 'NOVEMBRE': 11,
  'DIC': 12, 'DICEMBRE': 12,
  // Inglese (solo abbreviazioni diverse dall'italiano)
  'JAN': 1, 'MAY': 5, 'JUN': 6,
  'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'DEC': 12,
};

// ─── Utilità ────────────────────────────────────────────────

/// Data col giorno solo se esiste davvero: DateTime normalizza in silenzio
/// (31/04 diventerebbe il 1 maggio, 30/02 il 2 marzo).
DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1) return null;
  final d = DateTime(year, month, day);
  return (d.month == month && d.day == day) ? d : null;
}

DateTime? _buildDate(String monthStr, String yearStr) {
  final month = int.tryParse(monthStr);
  final year = _parseYear(yearStr);
  if (month == null || year == null) return null;
  if (month < 1 || month > 12) return null;

  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, lastDay);
}

int? _parseYear(String yearStr) {
  var year = int.tryParse(yearStr);
  if (year == null) return null;
  if (year < 100) {
    year += year < 80 ? 2000 : 1900;
  }
  return year;
}

// ─── Preferenza date future ─────────────────────────────────

/// Penalità forte per le date già passate.
/// Su una confezione di farmaci sono spesso stampate SIA la data di
/// produzione (passata) SIA la scadenza (futura): vogliamo che la futura
/// vinca sempre. Confronto a granularità di mese (se il mese è precedente
/// al mese corrente la data è considerata passata).
const _pastPenalty = 1000;

/// true se la data è passata, confrontata a granularità di mese.
bool _isPastMonth(DateTime date) {
  final now = DateTime.now();
  if (date.year != now.year) return date.year < now.year;
  return date.month < now.month;
}

/// Score effettivo usato per l'ordinamento: applica la penalità passato.
/// Non azzera lo score (una data scaduta può comunque essere valida),
/// ma garantisce che una data futura superi sempre una passata.
int _effectiveScore(_DateCandidate c) {
  return _isPastMonth(c.date) ? c.score - _pastPenalty : c.score;
}

/// Ordina i candidati: prima per score effettivo (penalità passato),
/// a parità di score la data più tardiva (futura) vince.
int _compareCandidates(_DateCandidate a, _DateCandidate b) {
  final cmp = _effectiveScore(b).compareTo(_effectiveScore(a));
  if (cmp != 0) return cmp;
  // Tie-break: preferisci la data più lontana nel futuro.
  return b.date.compareTo(a.date);
}
