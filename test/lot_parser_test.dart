import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/utils/lot_parser.dart';

void main() {
  group('findLot', () {
    test('lotto sulla stessa riga della parola chiave', () {
      expect(findLot(['LOTTO 21A034']), '21A034');
      expect(findLot(['Lotto: AB1234']), 'AB1234');
      expect(findLot(['LOT. 7H21K']), '7H21K');
      expect(findLot(['Batch B220145']), 'B220145');
    });

    test('lotto sulla riga sotto alla parola chiave', () {
      expect(findLot(['LOTTO', '21A034']), '21A034');
      expect(findLot(['Lotto n.', 'X99Y12']), 'X99Y12');
    });

    test('accetta trattini e barre, che nei lotti ci sono', () {
      expect(findLot(['LOTTO 21A-034']), '21A-034');
      expect(findLot(['LOT 12/34AB']), '12/34AB');
    });

    test('non scambia la scadenza per un lotto', () {
      expect(findLot(['Scad. 12/2027']), isNull);
      expect(findLot(['LOTTO', '12/2027']), isNull);
      expect(findLot(['LOTTO', 'Scad 03/2028']), isNull);
    });

    test('non prende il codice AIC', () {
      expect(findLot(['AIC 034329045']), isNull);
      expect(findLot(['LOTTO', 'AIC 034329045']), isNull);
    });

    test('scarta valori troppo corti o troppo lunghi', () {
      expect(findLot(['LOTTO A']), isNull);
      expect(findLot(['LOTTO ABCDEFGHIJKLMNOPQRSTUVWXYZ012345']), isNull);
    });

    test('senza parola chiave non si inventa niente', () {
      expect(findLot(['TACHIPIRINA 500 mg', '20 compresse']), isNull);
      expect(findLot([]), isNull);
    });

    test('la parola chiave dentro un altra parola non conta', () {
      expect(findLot(['PILOTTO 123456']), isNull);
    });

    test('restituisce il lotto in maiuscolo, senza punteggiatura in coda', () {
      expect(findLot(['lotto ab12cd.']), 'AB12CD');
    });
  });
}
