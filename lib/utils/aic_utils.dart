/// Funzioni pure per il riconoscimento dei codici AIC
/// (Autorizzazione all'Immissione in Commercio, 9 cifre per confezione).
library;

/// Alfabeto base-32 del Code 32 (bollino farmaceutico): cifre + consonanti,
/// escluse le vocali A E I O.
const String _code32Alphabet = '0123456789BCDFGHJKLMNPQRSTUVWXYZ';

/// Vero se il testo è esattamente un AIC plausibile (9 cifre).
bool isAicCandidate(String text) =>
    RegExp(r'^\d{9}$').hasMatch(text.trim());

/// Decodifica il valore di un bollino farmaceutico letto come Code 39
/// (standard Code 32) nell'AIC a 9 cifre. Ritorna null se non valido.
///
/// Il bollino codifica 6 caratteri base-32; alcuni lettori antepongono
/// la "A" mostrata nella parte leggibile.
String? decodeCode32(String raw) {
  var s = raw.trim().toUpperCase();
  if (s.length == 7 && s.startsWith('A')) s = s.substring(1);
  if (s.length != 6) return null;

  var value = 0;
  for (final ch in s.split('')) {
    final idx = _code32Alphabet.indexOf(ch);
    if (idx < 0) return null;
    value = value * 32 + idx;
  }
  if (value > 999999999) return null;
  return value.toString().padLeft(9, '0');
}

/// Estrae candidati AIC (sequenze isolate di 9 cifre) dalle righe OCR.
/// Le righe che contengono la keyword "AIC" hanno priorità; per quelle
/// vengono ricomposte anche cifre separate da spazi/punti/trattini.
List<String> extractAicCandidates(List<String> ocrLines, {int max = 5}) {
  final nineDigits = RegExp(r'(?<!\d)\d{9}(?!\d)');
  final aicKeyword = RegExp(r'A\.?\s?I\.?\s?C\.?', caseSensitive: false);
  final priority = <String>[];
  final others = <String>[];

  for (final line in ocrLines) {
    final hasKeyword = aicKeyword.hasMatch(line);
    final targets = <String>[line];
    if (hasKeyword) {
      // Ricompone "034 329 045" / "034.329.045" in un'unica sequenza
      targets.add(line.replaceAll(RegExp(r'(?<=\d)[ .\-](?=\d)'), ''));
    }
    for (final t in targets) {
      for (final m in nineDigits.allMatches(t)) {
        (hasKeyword ? priority : others).add(m.group(0)!);
      }
    }
  }

  final seen = <String>{};
  final result = <String>[];
  for (final c in [...priority, ...others]) {
    if (seen.add(c)) result.add(c);
    if (result.length >= max) break;
  }
  return result;
}

/// Estrae tutte le finestre di 9 cifre dai run numerici di un barcode
/// (EAN-13, GS1 Data Matrix...). La validazione vera è il lookup nel catalogo.
List<String> extractAicWindows(String barcodeValue, {int max = 10}) {
  final result = <String>[];
  final seen = <String>{};
  for (final m in RegExp(r'\d{9,}').allMatches(barcodeValue)) {
    final run = m.group(0)!;
    for (var i = 0; i + 9 <= run.length; i++) {
      final w = run.substring(i, i + 9);
      if (seen.add(w)) result.add(w);
      if (result.length >= max) return result;
    }
  }
  return result;
}

/// Estrae il dosaggio del PRINCIPIO ATTIVO da una DESCRIZIONE confezione
/// AIFA (es. "40 MG/5 ML SCIROPPO- FLACONE DA 200ML" → "40 mg/5 ml").
///
/// Nel catalogo la forza del principio attivo viene all'inizio e il
/// confezionamento in coda: prende la PRIMA occorrenza valida. Un volume
/// da solo (ml) o una taglia di contenitore ("DA 4 G") non sono dosaggi.
String? extractDosageFromDescrizione(String descrizione) {
  const number = r'\d+(?:[.,]\d+)*';
  // Unità di forza del principio attivo (il ml da solo è un volume).
  const paUnit = r'(?:MCG|µG|MG|U\.?I\.?|G|%)';
  // Una dose: "500 MG", "7,5 MG/ML", "40 MG/5 ML", "50MG/850MG",
  // "5.000 U.I./1 ML" (secondo termine: volume o altra forza).
  const dose = '$number\\s*$paUnit(?:\\s*/\\s*(?:$number\\s*)?(?:ML|$paUnit))?';
  final pattern = RegExp(
    // Anche associazioni col +: "500 MG + 200 MG".
    '(?<![A-Za-z0-9.,])($dose(?:\\s*\\+\\s*$dose)*)(?![A-Za-z0-9])',
    caseSensitive: false,
  );
  for (final m in pattern.allMatches(descrizione)) {
    // "DA 4 G" / "DA 10 ML" è la taglia del contenitore, non il dosaggio;
    // "IDROALCOLICA AL 50%" (omeopatici) è il grado alcolico dell'eccipiente.
    final before = descrizione.substring(0, m.start).trimRight().toUpperCase();
    if (before.endsWith(' DA') || before == 'DA') continue;
    if (before.endsWith('IDROALCOLICA AL')) continue;
    return m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }
  return null;
}

/// Mappa la FORMA farmaceutica AIFA (singolare) su una forma dell'app
/// (le voci del dropdown del ConfirmSheet). Null se non riconosciuta.
String? mapAifaForm(String forma) {
  final f = forma.toLowerCase();
  if (f.contains('compress')) {
    if (f.contains('riv')) return 'compresse rivestite';
    if (f.contains('efferv')) return 'compresse effervescenti';
    return 'compresse';
  }
  if (f.contains('capsul')) {
    if (f.contains('moll')) return 'capsule molli';
    return 'capsule';
  }
  if (f.contains('bustin')) return 'bustine';
  if (f.contains('fial')) return 'fiale';
  if (f.contains('gocce') || f.contains('goccia')) return 'gocce';
  if (f.contains('sciropp')) return 'sciroppo';
  if (f.contains('sospensione') && f.contains('oral')) {
    return 'sospensione orale';
  }
  if (f.contains('soluzione')) {
    if (f.contains('iniettabile')) return 'soluzione iniettabile';
    if (f.contains('oral')) return 'soluzione orale';
    return null;
  }
  if (f.contains('spray')) {
    if (f.contains('nasal')) return 'spray nasale';
    return 'spray';
  }
  if (f.contains('crema')) return 'crema';
  if (f.contains('gel')) return 'gel';
  if (f.contains('pomata')) return 'pomata';
  if (f.contains('unguento')) return 'unguento';
  if (f.contains('supposta') || f.contains('supposte')) return 'supposte';
  if (f.contains('cerott')) return 'cerotti';
  if (f.contains('collirio')) return 'collirio';
  if (f.contains('collutorio')) return 'collutorio';
  if (f.contains('granulato')) return 'granulato';
  if (f.contains('polvere')) return 'polvere';
  if (f.contains('ovul')) return 'ovuli';
  if (f.contains('inalat')) return 'inalatore';
  if (f.contains('aerosol')) return 'aerosol';
  if (f.contains('siring')) return 'siringa';
  return null;
}
