import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/utils/expiry_utils.dart';

void main() {
  // Data di riferimento fissa per test deterministici.
  final now = DateTime(2026, 6, 1);

  RestockBand band(DateTime expiry, {int red = 1, int yellow = 3}) =>
      classifyRestock(expiry, redMonths: red, yellowMonths: yellow, now: now);

  group('classifyRestock (default rosso=1 mese, giallo=3 mesi)', () {
    test('scaduto ieri -> expired', () {
      expect(band(DateTime(2026, 5, 31)), RestockBand.expired);
    });

    test('scade oggi -> red (non scaduto)', () {
      expect(band(DateTime(2026, 6, 1)), RestockBand.red);
    });

    test('scade fra 2 settimane -> red', () {
      expect(band(DateTime(2026, 6, 15)), RestockBand.red);
    });

    test('scade esattamente al limite rosso (1 mese) -> red', () {
      expect(band(DateTime(2026, 7, 1)), RestockBand.red);
    });

    test('scade poco oltre il limite rosso -> yellow', () {
      expect(band(DateTime(2026, 7, 2)), RestockBand.yellow);
    });

    test('scade al limite giallo (3 mesi) -> yellow', () {
      expect(band(DateTime(2026, 9, 1)), RestockBand.yellow);
    });

    test('scade oltre il limite giallo -> none', () {
      expect(band(DateTime(2026, 9, 2)), RestockBand.none);
    });
  });

  group('classifyRestock con soglie personalizzate (rosso=2, giallo=6)', () {
    test('scade fra ~6 settimane -> red (entro 2 mesi)', () {
      expect(band(DateTime(2026, 7, 15), red: 2, yellow: 6), RestockBand.red);
    });

    test('scade fra 5 mesi -> yellow (entro 6 mesi)', () {
      expect(band(DateTime(2026, 11, 1), red: 2, yellow: 6), RestockBand.yellow);
    });

    test('scade fra 7 mesi -> none', () {
      expect(band(DateTime(2027, 1, 1), red: 2, yellow: 6), RestockBand.none);
    });
  });

  test('addMonths normalizza overflow di giorno', () {
    // 31 gennaio + 1 mese -> Dart normalizza (febbraio non ha 31 giorni).
    final r = addMonths(DateTime(2026, 1, 31), 1);
    expect(r.month, 3); // 2026-02-31 -> 2026-03-03
  });

  group('getExpiryStatus', () {
    tearDown(() {
      ExpiryThresholds.redMonths = 1;
      ExpiryThresholds.yellowMonths = 3;
    });

    test('ora legale: scaduto il 28 marzo, il 29 è «scaduto» (B3)', () {
      // Il 28/3/2027 l'Italia passa all'ora legale: fra le due mezzanotti
      // ci sono 23 ore, e inDays dava 0 («in scadenza»).
      expect(getExpiryStatus(DateTime(2027, 3, 28), now: DateTime(2027, 3, 29, 9)),
          ExpiryStatus.expired);
    });

    test('usa le soglie scelte dall\'utente, come il reintegro (B2)', () {
      ExpiryThresholds.redMonths = 2;
      final now = DateTime(2026, 6, 1);
      // Fra 45 giorni: con 30 giorni fissi era «Attenzione», con 2 mesi è
      // «In scadenza», come nella schermata del reintegro.
      expect(getExpiryStatus(DateTime(2026, 7, 16), now: now),
          ExpiryStatus.critical);
      expect(getExpiryStatus(DateTime(2026, 6, 1), now: now),
          ExpiryStatus.critical); // scade oggi: non ancora scaduto
      expect(getExpiryStatus(DateTime(2026, 8, 20), now: now),
          ExpiryStatus.warning);
      expect(getExpiryStatus(DateTime(2027, 1, 1), now: now), ExpiryStatus.ok);
    });
  });
}
