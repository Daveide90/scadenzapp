/// Ricerca del numero di lotto nel testo letto dalla confezione.
///
/// Serve quando la scatola non ha il Data Matrix: il lotto è comunque
/// stampato in chiaro, di solito accanto alla scadenza, preceduto da
/// "Lotto", "Lot" o "Batch".
library;

/// Parole che introducono il lotto, in italiano e nelle diciture che
/// compaiono sulle confezioni estere.
final _keyword = RegExp(
  r'(?:^|[^A-Za-z])(?:LOTTO|LOT|BATCH|CH\.?B)\b\.?\s*(?:N[.°]?\s*)?[:\-]?\s*(.*)$',
  caseSensitive: false,
);

/// Un lotto plausibile: lettere, cifre, trattini e barre.
final _value = RegExp(r'^[A-Z0-9][A-Z0-9\-/]{1,18}[A-Z0-9]$');

/// Una data va scartata: accanto al lotto c'è quasi sempre la scadenza, ed è
/// l'errore più facile da fare. Attenzione però a non buttare via i lotti che
/// contengono una barra (12/34AB): la data è fatta di sole cifre.
final _looksLikeDate = RegExp(r'^\d{1,4}\s*[/.\-]\s*\d{1,4}(\s*[/.\-]\s*\d{1,4})?$');

/// Righe che parlano d'altro e non vanno lette come lotto.
final _otherCode = RegExp(r'\b(AIC|EAN|GTIN|REG|SCAD|EXP)\b', caseSensitive: false);

/// Cerca il lotto fra le [lines] lette dall'OCR.
///
/// Il valore può stare sulla stessa riga della parola chiave o su quella
/// successiva (capita quando l'etichetta va a capo). Senza parola chiave non
/// si tira a indovinare: un codice qualsiasi sulla scatola non è un lotto.
String? findLot(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    final match = _keyword.firstMatch(lines[i]);
    if (match == null) continue;

    // Prima il resto della riga, poi la riga sotto.
    final candidates = <String>[
      match.group(1) ?? '',
      if (i + 1 < lines.length) lines[i + 1],
    ];

    for (final raw in candidates) {
      final lot = _clean(raw);
      if (lot != null) return lot;
    }
  }
  return null;
}

String? _clean(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (_otherCode.hasMatch(text)) return null;

  // Il lotto è il primo pezzo utile: dopo può esserci altro (es. la scadenza).
  text = text.split(RegExp(r'\s+')).first;
  // Punteggiatura di contorno lasciata dall'OCR.
  text = text.replaceAll(RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$'), '');
  if (_looksLikeDate.hasMatch(text)) return null;
  final lot = text.toUpperCase();

  if (!_value.hasMatch(lot)) return null;
  // Solo cifre e lungo come un AIC: è più probabile sia un altro codice.
  if (lot.length == 9 && RegExp(r'^\d+$').hasMatch(lot)) return null;
  return lot;
}
