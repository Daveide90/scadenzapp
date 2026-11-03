/// Dati dell'app mostrati all'utente, in un posto solo.
///
/// Versione e build devono coincidere con `version:` di pubspec.yaml, e la
/// data del catalogo con quella scritta dentro assets/aifa_catalog.db.gz:
/// lo controlla test/intended_use_and_info_test.dart.
library;

const appVersion = '1.4.1';
const appBuild = 11;

/// Giorno in cui è stato scaricato il catalogo AIFA incluso (AAAA-MM-GG).
const aifaCatalogDate = '2026-11-03';

/// La stessa data in formato italiano, per i testi.
String get aifaCatalogDateIt {
  final p = aifaCatalogDate.split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

/// Indirizzo pubblico dell'informativa privacy. Vuoto finché non è
/// pubblicata: la voce nelle Impostazioni compare quando c'è.
const privacyPolicyUrl = '';
