import 'package:flutter/foundation.dart';
import '../data/medicine_names.dart';

class MatchResult {
  final String dbName;          // nome nel database (MAIUSCOLO)
  final String activeIngredient; // principio attivo
  final double score;
  final String candidate;       // testo OCR che ha matchato

  MatchResult({
    required this.dbName,
    required this.activeIngredient,
    required this.score,
    required this.candidate,
  });

  /// Principio attivo tra parentesi, solo se diverso dal nome
  String? get genericLabel {
    if (dbName == activeIngredient) return null;
    if (candidate.toUpperCase() == activeIngredient) return null;
    return activeIngredient.toLowerCase();
  }

  /// Nome da mostrare nel chip suggerimento
  String get chipLabel {
    final generic = genericLabel;
    if (generic != null) {
      return '$dbName ($generic)';
    }
    return dbName;
  }

  /// Nome per il campo testo: nome DB (title case) + dosaggio + forma + principio attivo
  String nameForField({String? dosage, String? form}) {
    var name = _titleCase(dbName);
    if (dosage != null) name = '$name $dosage';
    if (form != null) name = '$name $form';
    final generic = genericLabel;
    if (generic != null) {
      name = '$name ($generic)';
    }
    return name;
  }

  static String _titleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }
}

/// Versione async che esegue il matching in un Isolate.
Future<List<MatchResult>> findMedicineMatchesAsync(
  List<String> ocrLines, {
  int maxResults = 5,
  double minScore = 0.55,
  List<Map<String, dynamic>> customMedicines = const [],
}) {
  return compute(
    _findMatchesIsolate,
    _MatchRequest(ocrLines, maxResults, minScore, customMedicines),
  );
}

class _MatchRequest {
  final List<String> ocrLines;
  final int maxResults;
  final double minScore;
  final List<Map<String, dynamic>> customMedicines;
  _MatchRequest(this.ocrLines, this.maxResults, this.minScore, this.customMedicines);
}

/// Entry point per l'Isolate (funzione top-level-compatibile)
List<MatchResult> _findMatchesIsolate(_MatchRequest req) {
  return findMedicineMatches(req.ocrLines,
      maxResults: req.maxResults, minScore: req.minScore,
      customMedicines: req.customMedicines);
}

/// Trova i migliori match nel database per il testo OCR.
/// Cerca sia nel database AIFA che nei farmaci custom dell'utente.
List<MatchResult> findMedicineMatches(
  List<String> ocrLines, {
  int maxResults = 5,
  double minScore = 0.55,
  List<Map<String, dynamic>> customMedicines = const [],
}) {
  final bestByName = <String, MatchResult>{};

  // Costruisci un database unificato: AIFA + custom
  final allMedicines = <String, String>{...medicineDatabase};
  for (final cm in customMedicines) {
    final name = cm['name'] as String;
    final ingredient = (cm['active_ingredient'] as String?) ?? '';
    allMedicines.putIfAbsent(name, () => ingredient);
  }

  for (final line in ocrLines) {
    final normalized = _normalize(line);
    if (normalized.length < 3) continue;

    // Genera candidati: riga intera, singole parole, coppie
    final words = normalized.split(RegExp(r'\s+'));
    final candidates = <String>[normalized];

    for (final w in words) {
      if (w.length >= 4) candidates.add(w);
    }
    for (int i = 0; i < words.length - 1; i++) {
      candidates.add('${words[i]} ${words[i + 1]}');
    }

    for (final candidate in candidates) {
      if (candidate.length < 3) continue;

      for (final entry in allMedicines.entries) {
        final dbName = entry.key;
        final nameScore = _similarity(candidate, dbName);
        if (nameScore >= minScore) {
          final bonus = (candidate.length >= 6 && nameScore >= 0.7) ? 0.05 : 0.0;
          final score = (nameScore + bonus).clamp(0.0, 1.0);

          final existing = bestByName[dbName];
          if (existing == null || score > existing.score) {
            bestByName[dbName] = MatchResult(
              dbName: dbName,
              activeIngredient: entry.value,
              score: score,
              candidate: candidate,
            );
          }

          // Early exit: match perfetto trovato
          if (score >= 1.0) break;
        }
      }
    }
  }

  final sorted = bestByName.values.toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  return sorted.take(maxResults).toList();
}

/// Estrai dosaggio dal testo OCR
String? extractDosage(String ocrText) {
  final pattern = RegExp(
    r'(\d+[.,]?\d*)\s*(mg/ml|mg|mcg|µg|g|ml|ui|%)',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(ocrText);
  return match?.group(0)?.trim();
}

/// Estrai forma farmaceutica dal testo OCR
String? extractForm(String ocrText) {
  final upper = ocrText.toUpperCase();
  // Forme composte prima (più specifiche)
  const composte = {
    'COMPRESSE RIVESTITE': 'compresse rivestite',
    'COMPRESSE EFFERVESCENTI': 'compresse effervescenti',
    'COMPRESSE OROSOLUBILI': 'compresse orosolubili',
    'CAPSULE MOLLI': 'capsule molli',
    'CAPSULE RIGIDE': 'capsule rigide',
    'RILASCIO PROLUNGATO': 'rilascio prolungato',
    'RILASCIO MODIFICATO': 'rilascio modificato',
    'SPRAY NASALE': 'spray nasale',
    'SPRAY ORALE': 'spray orale',
    'SOLUZIONE ORALE': 'soluzione orale',
    'SOLUZIONE INIETTABILE': 'soluzione iniettabile',
    'SOSPENSIONE ORALE': 'sospensione orale',
    'POLVERE PER SOLUZIONE': 'polvere per soluzione',
    'USO ORALE': 'uso orale',
    'USO CUTANEO': 'uso cutaneo',
  };
  for (final e in composte.entries) {
    if (upper.contains(e.key)) return e.value;
  }
  // Forme semplici
  const semplici = {
    'COMPRESSE': 'compresse',
    'COMPRESSA': 'compresse',
    'CAPSULE': 'capsule',
    'CAPSULA': 'capsule',
    'BUSTINE': 'bustine',
    'BUSTINA': 'bustine',
    'FIALE': 'fiale',
    'FIALA': 'fiale',
    'GOCCE': 'gocce',
    'SCIROPPO': 'sciroppo',
    'SPRAY': 'spray',
    'CREMA': 'crema',
    'GEL': 'gel',
    'POMATA': 'pomata',
    'UNGUENTO': 'unguento',
    'SUPPOSTE': 'supposte',
    'SUPPOSTA': 'supposte',
    'CEROTTI': 'cerotti',
    'CEROTTO': 'cerotti',
    'COLLIRIO': 'collirio',
    'COLLUTORIO': 'collutorio',
    'SOSPENSIONE': 'sospensione',
    'GRANULATO': 'granulato',
    'POLVERE': 'polvere',
    'OVULI': 'ovuli',
    'INALATORE': 'inalatore',
    'AEROSOL': 'aerosol',
    'SIRINGA': 'siringa',
    'INIEZIONE': 'iniezione',
  };
  for (final e in semplici.entries) {
    if (upper.contains(e.key)) return e.value;
  }
  return null;
}

// ─── Utilità interne ────────────────────────────────────────────

String _normalize(String text) {
  return text
      .toUpperCase()
      .replaceAll(RegExp(r'[®™°]'), '')
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Coppie di caratteri che l'OCR confonde spesso (dopo uppercase)
const _ocrConfusablePairs = [
  ['I', 'L'], // I maiuscola ↔ l minuscola
  ['I', '1'], // I ↔ 1
  ['O', '0'], // O ↔ zero
  ['B', '8'], // B ↔ 8
  ['S', '5'], // S ↔ 5
];

bool _isOcrConfusable(String a, String b) {
  for (final pair in _ocrConfusablePairs) {
    if ((a == pair[0] && b == pair[1]) || (a == pair[1] && b == pair[0])) {
      return true;
    }
  }
  return false;
}

double _similarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0.0;

  final shorter = a.length <= b.length ? a : b;
  final longer = a.length > b.length ? a : b;

  // Contenimento esatto
  if (longer.contains(shorter) && shorter.length >= 4) {
    return (shorter.length / longer.length).clamp(0.65, 1.0);
  }

  // Prefisso comune (con tolleranza OCR)
  final maxLen = a.length > b.length ? a.length : b.length;
  final prefixLen = _commonPrefixLength(a, b);
  final prefixScore = prefixLen / maxLen;
  if (prefixScore >= 0.75) return prefixScore;

  // Levenshtein con costo ridotto per confusioni OCR
  final dist = _ocrLevenshtein(a, b);
  final levScore = 1.0 - (dist / maxLen);

  // Trigram
  final triScore = _trigramSimilarity(a, b);

  return levScore > triScore ? levScore : triScore;
}

int _commonPrefixLength(String a, String b) {
  final minLen = a.length < b.length ? a.length : b.length;
  int i = 0;
  while (i < minLen && a[i] == b[i]) {
    i++;
  }
  return i;
}

/// Levenshtein con costo ridotto (0.3) per sostituzioni OCR confusabili
double _ocrLevenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length.toDouble();
  if (b.isEmpty) return a.length.toDouble();

  var prev = List<double>.generate(b.length + 1, (i) => i.toDouble());
  var curr = List<double>.filled(b.length + 1, 0);

  for (int i = 1; i <= a.length; i++) {
    curr[0] = i.toDouble();
    for (int j = 1; j <= b.length; j++) {
      final ca = a[i - 1];
      final cb = b[j - 1];
      final double cost;
      if (ca == cb) {
        cost = 0;
      } else if (_isOcrConfusable(ca, cb)) {
        cost = 0.3; // confusione OCR → costo ridotto
      } else {
        cost = 1;
      }
      curr[j] = _min3d(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
    }
    final temp = prev;
    prev = curr;
    curr = temp;
  }
  return prev[b.length];
}

double _min3d(double a, double b, double c) {
  if (a <= b && a <= c) return a;
  if (b <= c) return b;
  return c;
}

Set<String> _trigrams(String s) {
  if (s.length < 3) return {s};
  final result = <String>{};
  for (int i = 0; i <= s.length - 3; i++) {
    result.add(s.substring(i, i + 3));
  }
  return result;
}

double _trigramSimilarity(String a, String b) {
  final ta = _trigrams(a);
  final tb = _trigrams(b);
  if (ta.isEmpty && tb.isEmpty) return 1.0;
  final intersection = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return union > 0 ? intersection / union : 0.0;
}
