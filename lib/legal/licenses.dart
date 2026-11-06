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
  });
}

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
