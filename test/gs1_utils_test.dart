import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/utils/gs1_utils.dart';

/// GTIN-14 del bollino di AIC 034329045: '0' + '080' + AIC + cifra di controllo.
const gtin14 = '00800343290451';

void main() {
  group('parseGs1', () {
    test('Data Matrix farmaceutico completo: GTIN, scadenza, lotto, seriale',
        () {
      final d = parseGs1('01${gtin14}1727123110LOTTO123${fnc1}21ABCDEF');

      expect(d, isNotNull);
      expect(d!.gtin, gtin14);
      expect(d.expiry, DateTime(2027, 12, 31));
      expect(d.lot, 'LOTTO123');
      expect(d.serial, 'ABCDEF');
    });

    test('giorno 00 significa fine mese', () {
      expect(parseGs1('17250600')!.expiry, DateTime(2025, 6, 30));
    });

    test('febbraio bisestile con giorno 00', () {
      expect(parseGs1('17240200')!.expiry, DateTime(2024, 2, 29));
    });

    test('accetta la forma con parentesi (alcuni lettori la restituiscono)', () {
      final d = parseGs1('(01)$gtin14(17)271231(10)AB-12');

      expect(d!.gtin, gtin14);
      expect(d.expiry, DateTime(2027, 12, 31));
      expect(d.lot, 'AB-12');
    });

    test('ignora il prefisso di simbologia ]d2', () {
      expect(parseGs1(']d201$gtin14')!.gtin, gtin14);
    });

    test('campo variabile finale senza FNC1 arriva a fine stringa', () {
      final d = parseGs1('1725123110ABC999');
      expect(d!.lot, 'ABC999');
      expect(d.expiry, DateTime(2025, 12, 31));
    });

    test('lotto prima della scadenza, separato da FNC1', () {
      final d = parseGs1('10L-99${fnc1}17261130');
      expect(d!.lot, 'L-99');
      expect(d.expiry, DateTime(2026, 11, 30));
    });

    test('data impossibile: scadenza nulla, il resto resta leggibile', () {
      final d = parseGs1('01${gtin14}17991331');
      expect(d!.gtin, gtin14);
      expect(d.expiry, isNull);
    });

    test('un EAN-13 semplice non è GS1: nessun dato', () {
      expect(parseGs1('0800343290451'), isNull);
    });

    test('stringa vuota o spazzatura: nessun dato', () {
      expect(parseGs1(''), isNull);
      expect(parseGs1('CIAO'), isNull);
    });

    // ML Kit spesso restituisce il contenuto del Data Matrix senza i
    // separatori FNC1: senza di essi un campo variabile "mangerebbe" tutto
    // il resto e scadenza e lotto andrebbero persi.
    test('seriale prima del lotto e della scadenza, senza FNC1', () {
      final d = parseGs1('01${gtin14}21SER9910LOT12317271231');

      expect(d!.gtin, gtin14);
      expect(d.serial, 'SER99');
      expect(d.lot, 'LOT123');
      expect(d.expiry, DateTime(2027, 12, 31));
    });

    test('seriale, scadenza e lotto in coda, senza FNC1', () {
      final d = parseGs1('01${gtin14}21SER991727123110LOT123');

      expect(d!.serial, 'SER99');
      expect(d.expiry, DateTime(2027, 12, 31));
      expect(d.lot, 'LOT123');
    });

    test('lotto che contiene cifre simili a un AI', () {
      final d = parseGs1('01${gtin14}1027103010${String.fromCharCode(0x1D)}17280131');

      expect(d!.lot, '27103010');
      expect(d.expiry, DateTime(2028, 1, 31));
    });

    test('AI sconosciuto a lunghezza ignota interrompe la lettura', () {
      // 91 è di uso interno, lunghezza non nota: si tiene quel che precede.
      expect(parseGs1('1726123091QUALCOSA')!.expiry, DateTime(2026, 12, 30));
    });
  });

  group('isItalianBollino', () {
    // Contenuto reale del Data Matrix di una fustella (Bentelan):
    // targhetta + cifra di controllo + codice di sicurezza.
    test('riconosce il Data Matrix della fustella', () {
      expect(isItalianBollino('06799256350LRUHJ'), isTrue);
    });

    test('riconosce il codice a barre della targhetta', () {
      expect(isItalianBollino('0679925635'), isTrue);
    });

    test('non scambia per fustella un Data Matrix GS1', () {
      expect(isItalianBollino('01${gtin14}17271231'), isFalse);
    });

    test('non scambia per fustella un AIC o un EAN', () {
      expect(isItalianBollino('034329045'), isFalse);
      expect(isItalianBollino('0800343290451'), isFalse);
    });
  });

  group('aicFromGtin', () {
    test('estrae le 9 cifre AIC dal GTIN-14 italiano (prefisso 080)', () {
      expect(aicFromGtin(gtin14), '034329045');
    });

    test('funziona anche col GTIN-13 senza lo zero iniziale', () {
      expect(aicFromGtin('0800343290451'), '034329045');
    });

    test('GTIN non italiano: nessun AIC', () {
      expect(aicFromGtin('05000112345678'), isNull);
    });

    test('lunghezza sbagliata o non numerico: nessun AIC', () {
      expect(aicFromGtin('080034'), isNull);
      expect(aicFromGtin('0080034329045X'), isNull);
    });
  });
}
