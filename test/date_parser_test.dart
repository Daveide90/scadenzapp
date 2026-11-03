import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/utils/date_parser.dart';

void main() {
  parserTests();
  group('date impossibili', () {
    test('31/04 non diventa il 1 maggio', () {
      final d = parseExpiryDate('SCAD 31/04/2027');
      expect(d, isNot(DateTime(2027, 5, 1)));
      expect(d, DateTime(2027, 4, 30)); // resta aprile 2027
    });

    test('30/02 non diventa marzo', () {
      final d = parseExpiryDate('EXP 30/02/2028');
      expect(d?.month, 2);
    });

    test('una data vera col giorno resta quella', () {
      expect(parseExpiryDate('SCAD 15/06/2027'), DateTime(2027, 6, 15));
    });

    test('tra i candidati non compare un giorno spostato', () {
      final c = findExpiryDateCandidates(['SCAD 31/04/2027']);
      expect(c.map((e) => e.date), isNot(contains(DateTime(2027, 5, 1))));
    });
  });
}

/// Testi tipici di confezioni, con la scadenza attesa.
final _scatole = <String, DateTime?>{
  'SCAD 05/2027': DateTime(2027, 5, 31),
  'EXP 2027-05': DateTime(2027, 5, 31),
  'PROD 03/2025\nSCAD 03/2028': DateTime(2028, 3, 31),
  'SCAD. MAG 2027': DateTime(2027, 5, 31),
  'SCADENZA\n06/2027': DateTime(2027, 6, 30),
  'SCAD 31/12/26': DateTime(2026, 12, 31),
  'SCAD O6/2O27': DateTime(2027, 6, 30),
  'SCAD 03/2025': DateTime(2025, 3, 31), // confezione già scaduta
  'LOT 052027': null, // numero di lotto, non una data
};

void parserTests() {
  group('scatole tipiche', () {
    _scatole.forEach((testo, attesa) {
      test(testo.replaceAll('\n', ' | '), () {
        expect(parseExpiryDate(testo), attesa);
      });
    });
  });

  group('una sola logica', () {
    test('le O lette al posto degli zeri valgono anche senza separatore', () {
      final c = findExpiryDateCandidates(['SCAD O62O27']);
      expect(c.map((e) => e.date), contains(DateTime(2027, 6, 30)));
    });

    test('il primo candidato è sempre la data scelta', () {
      for (final testo in [..._scatole.keys, 'SCAD O62O27']) {
        final righe = testo.split('\n');
        final c = findExpiryDateCandidates(righe);
        expect(c.isEmpty ? null : c.first.date,
            parseExpiryDateFromLines(righe), reason: testo);
      }
    });
  });
}
