import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';

/// Licenze che Flutter non raccoglie da solo: Flutter elenca i pacchetti
/// Dart, non le librerie Android dentro l'APK, i caratteri incorporati e i
/// dati. MIT, BSD e Apache chiedono che l'avviso accompagni il software
/// distribuito; i dati AIFA (CC BY 4.0) chiedono fonte, licenza e modifiche.
/// Da chiamare una volta, prima di runApp.
void registerExtraLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Dati dei farmaci (AIFA)'],
      aifaAttribution,
    );
    yield LicenseEntryWithLineBreaks(
      const ['Roboto'],
      'Carattere Roboto, Copyright Google, usato nei PDF.\n\n'
      '${await rootBundle.loadString('assets/licenses/apache-2.0.txt')}',
    );
    yield LicenseEntryWithLineBreaks(
      const ['SQLCipher'],
      await rootBundle.loadString('assets/licenses/sqlcipher.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['SLF4J'],
      await rootBundle.loadString('assets/licenses/slf4j.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['Google ML Kit e Google Play services'],
      await rootBundle.loadString('assets/licenses/google-mlkit.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['Librerie Android'],
      await rootBundle.loadString('assets/licenses/android-apache.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['Librerie Android: avvisi (NOTICE)'],
      await rootBundle.loadString('assets/licenses/android-notice.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['Protocol Buffers (dentro Tink)'],
      'Tink, la libreria di cifratura di Google usata per le chiavi, '
      'contiene una copia di Protocol Buffers.\n\n'
      '${await rootBundle.loadString('assets/licenses/protobuf.txt')}',
    );
    yield LicenseEntryWithLineBreaks(
      const ['Material Icons'],
      'Icone Material Design, Copyright Google, nel carattere '
      'MaterialIcons-Regular incluso da Flutter.\n\n'
      '${await rootBundle.loadString('assets/licenses/apache-2.0.txt')}',
    );
    // I componenti open source dentro ML Kit e Google Play services: i
    // testi vengono dai file third_party_licenses delle librerie stesse,
    // una licenza per componente, sotto una sola voce.
    final google = jsonDecode(
            await rootBundle.loadString('assets/licenses/google-componenti.json'))
        as Map<String, dynamic>;
    yield LicenseEntryWithLineBreaks(
      const [googleComponentsPackage],
      '${google['fonte']}\n\nCon la sola Apache License 2.0 (testo intero '
      'nella voce «Librerie Android»): '
      '${(google['solo_apache'] as List).join(', ')}.',
    );
    for (final voce in google['voci'] as List) {
      yield LicenseEntryWithLineBreaks(
        const [googleComponentsPackage],
        '${voce['nomi']}\n\n${voce['testo']}',
      );
    }
  });
}

/// Voce della pagina Licenze con i componenti dentro ML Kit e Play services.
const googleComponentsPackage = 'Componenti dentro ML Kit e Google Play services';

/// Citazione dei dati AIFA come chiede la licenza CC BY 4.0: autore, fonte,
/// licenza e cosa è stato cambiato.
String get aifaAttribution =>
    'Nomi, dosaggi, forme e codici AIC dei farmaci: Agenzia Italiana del '
    'Farmaco (AIFA), open data «Confezioni dei farmaci» '
    '(https://drive.aifa.gov.it/farmaci/confezioni_fornitura.csv), '
    'scaricati il $aifaCatalogDateIt.\n\n'
    'Licenza Creative Commons Attribuzione 4.0 Internazionale (CC BY 4.0): '
    'https://creativecommons.org/licenses/by/4.0/deed.it\n\n'
    'Modifiche: tenute solo le confezioni autorizzate; nomi, dosaggi e forme '
    'riorganizzati per la ricerca nell\'app.\n\n'
    'L\'AIFA non è coinvolta in ScadenzApp e non ne garantisce i contenuti.';
