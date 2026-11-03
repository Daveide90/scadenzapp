import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/utils/aic_utils.dart';

/// Codifica un AIC in Code 32 (solo per i test di roundtrip).
String encodeCode32(String aic) {
  const alphabet = '0123456789BCDFGHJKLMNPQRSTUVWXYZ';
  var value = int.parse(aic);
  final chars = <String>[];
  for (var i = 0; i < 6; i++) {
    chars.insert(0, alphabet[value % 32]);
    value ~/= 32;
  }
  return chars.join();
}

void main() {
  group('decodeCode32', () {
    test('vettore noto: 10RNGP -> 034329045', () {
      expect(decodeCode32('10RNGP'), '034329045');
    });

    test('accetta la A iniziale del bollino', () {
      expect(decodeCode32('A10RNGP'), '034329045');
    });

    test('minuscole accettate', () {
      expect(decodeCode32('10rngp'), '034329045');
    });

    test('roundtrip con vari AIC', () {
      for (final aic in ['000000000', '012345678', '999999999', '042719038']) {
        expect(decodeCode32(encodeCode32(aic)), aic, reason: aic);
      }
    });

    test('rifiuta lunghezza sbagliata', () {
      expect(decodeCode32('10RNG'), isNull);
      expect(decodeCode32('10RNGPXX'), isNull);
      expect(decodeCode32(''), isNull);
    });

    test('rifiuta caratteri fuori alfabeto (vocali)', () {
      expect(decodeCode32('10RNGE'), isNull);
      expect(decodeCode32('AAAAAA'), isNull); // A non è nell'alfabeto base32
    });

    test('rifiuta valori oltre 999999999', () {
      expect(decodeCode32('ZZZZZZ'), isNull); // 32^6-1 > 999999999
    });
  });

  group('extractAicCandidates', () {
    test('trova 9 cifre in una riga con keyword AIC', () {
      expect(extractAicCandidates(['AIC 034329045']), ['034329045']);
    });

    test('ricompone cifre separate da spazi vicino ad AIC', () {
      expect(extractAicCandidates(['A.I.C. 034 329 045']), ['034329045']);
    });

    test('le righe con AIC hanno priorità', () {
      final result = extractAicCandidates([
        '123456789',
        'AIC: 034329045',
      ]);
      expect(result.first, '034329045');
      expect(result, contains('123456789'));
    });

    test('ignora sequenze più lunghe di 9 cifre (es. EAN-13)', () {
      expect(extractAicCandidates(['8012345678903']), isEmpty);
    });

    test('ignora sequenze più corte e deduplica', () {
      expect(
        extractAicCandidates(['LOT 12345678', '034329045', '034329045']),
        ['034329045'],
      );
    });
  });

  group('extractAicWindows', () {
    test('finestre di 9 cifre da un EAN-13', () {
      final windows = extractAicWindows('8012345678903');
      expect(windows, contains('123456789'));
      expect(windows.length, 5);
    });

    test('valore Data Matrix GS1 con AI (01)', () {
      // (01) + GTIN-14 "08012345678903": deve contenere la finestra dell'AIC
      final windows = extractAicWindows('0108012345678903172812');
      expect(windows, contains('801234567'));
      expect(windows, isNot(contains('80123456789031'))); // solo 9 cifre
    });

    test('stringa senza abbastanza cifre', () {
      expect(extractAicWindows('ABC123'), isEmpty);
    });
  });

  group('extractDosageFromDescrizione', () {
    test('dosaggio in coda alla descrizione (formato vecchio)', () {
      expect(extractDosageFromDescrizione('20 CPR RIV 500 MG'), '500 mg');
    });

    test('dosaggio con separatore migliaia', () {
      expect(extractDosageFromDescrizione('30 CPR 1.000 MG'), '1.000 mg');
    });

    test('grammi', () {
      expect(
        extractDosageFromDescrizione('POLVERE PER TISANA-SCATOLA 80 G'),
        '80 g',
      );
    });

    test('unità prima del numero non matcha', () {
      expect(extractDosageFromDescrizione('10 BUSTINE FILTRO G 2'), isNull);
    });

    test('il volume del flacone non è un dosaggio', () {
      expect(
        extractDosageFromDescrizione('FLACONE 100 ML 5 MG/ML'),
        '5 mg/ml',
      );
    });

    test('sciroppo: principio attivo, non il volume del flacone', () {
      expect(
        extractDosageFromDescrizione('40 MG/5 ML SCIROPPO- FLACONE DA 200ML'),
        '40 mg/5 ml',
      );
    });

    test('fiale: concentrazione, non il volume della fiala', () {
      expect(
        extractDosageFromDescrizione(
            '7,5 MG/ML SOLUZIONE INIETTABILE- 20 FIALE IN LDPE DA 10 ML'),
        '7,5 mg/ml',
      );
    });

    test('dose per volume (mg/N ml)', () {
      expect(
        extractDosageFromDescrizione(
            '1000 MG/10 ML SOLUZIONE PER INFUSIONE- 5 FIALE 10 ML'),
        '1000 mg/10 ml',
      );
    });

    test('compresse: dosaggio prima del confezionamento', () {
      expect(
        extractDosageFromDescrizione(
            '20 MG COMPRESSE RIVESTITE CON FILM- 90 COMPRESSE IN BLISTER PA/AL/PVC/AL'),
        '20 mg',
      );
    });

    test('associazione con +', () {
      expect(
        extractDosageFromDescrizione('ADULTI 500 MG + 200 MG SUPPOSTE- 6 SUPPOSTE'),
        '500 mg + 200 mg',
      );
    });

    test('associazione senza spazi con /', () {
      expect(
        extractDosageFromDescrizione(
            '50MG/850MG -COMPRESSA RIVESTITA CON FILM - USO ORALE - BLISTER (PA/AL/PVC/AL) 30 COMPRESSE'),
        '50mg/850mg',
      );
    });

    test('unità internazionali per volume', () {
      expect(
        extractDosageFromDescrizione(
            '5.000 U.I./1 ML SOLUZIONE INIETTABILE- 10 FIALE 1 ML'),
        '5.000 u.i./1 ml',
      );
    });

    test('taglia del contenitore ("DA ...") non è un dosaggio', () {
      expect(
        extractDosageFromDescrizione(
            'GRANULI- 1 CONTENITORE MULTIDOSE IN PP DA 4 G (80 GRANULI) CON TAPPO DISPENSATORE IN PS'),
        isNull,
      );
    });

    test('solo volumi delle fiale -> null', () {
      expect(
        extractDosageFromDescrizione(
            'BAMBINI SOLUZIONE INIETTABILE- 6 FIALE I DA 1 ML + 6 FIALE II DA 1 ML'),
        isNull,
      );
    });

    test('la percentuale della soluzione idroalcolica (omeopatici) non è un dosaggio', () {
      expect(
        extractDosageFromDescrizione(
            '5 CH GOCCE ORALI, SOLUZIONE- 1 FLACONE CONTAGOCCE IN VETRO IN SOLUZIONE IDROALCOLICA AL 50% V/V DA 10 ML'),
        isNull,
      );
    });

    test('la percentuale di una crema è un dosaggio', () {
      expect(extractDosageFromDescrizione('CREMA AL 5%- TUBO DA 50 G'), '5%');
      expect(
        extractDosageFromDescrizione('1 TUBO DI CREMA DA 10 G AL 1%'),
        '1%',
      );
    });

    test('numeri attaccati a lettere (sigle) ignorati', () {
      expect(
        extractDosageFromDescrizione(
            'N17G35E SOLUZIONE PER INFUSIONE- 1 SACCA DA 500 ML+500 ML'),
        isNull,
      );
    });
  });

  group('mapAifaForm', () {
    test('singolare AIFA -> plurale app', () {
      expect(mapAifaForm('Compressa rivestita'), 'compresse rivestite');
      expect(mapAifaForm('Compressa'), 'compresse');
      expect(mapAifaForm('Capsula molle'), 'capsule molli');
      expect(mapAifaForm('Supposta'), 'supposte');
    });

    test('forme dirette', () {
      expect(mapAifaForm('Soluzione iniettabile'), 'soluzione iniettabile');
      expect(mapAifaForm('Sciroppo'), 'sciroppo');
      expect(mapAifaForm('Collirio'), 'collirio');
      expect(mapAifaForm('Spray nasale'), 'spray nasale');
    });

    test('forma sconosciuta -> null', () {
      expect(mapAifaForm('Tisana'), isNull);
      expect(mapAifaForm(''), isNull);
    });
  });

  group('isAicCandidate', () {
    test('esattamente 9 cifre', () {
      expect(isAicCandidate('034329045'), isTrue);
      expect(isAicCandidate(' 034329045 '), isTrue);
      expect(isAicCandidate('03432904'), isFalse);
      expect(isAicCandidate('0343290456'), isFalse);
      expect(isAicCandidate('Tachipirina'), isFalse);
    });
  });
}
