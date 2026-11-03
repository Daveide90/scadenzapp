import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/models/cabinet_check.dart';
import 'package:scadenzapp/services/check_report_pdf_service.dart';
import 'package:scadenzapp/utils/expiry_utils.dart';

void main() {
  group('CabinetCheck', () {
    test('il controllo è regolare solo se non ha trovato scaduti', () {
      final ok = CabinetCheck(
        cabinetId: 1,
        operator: 'Rossi',
        checkedCount: 10,
        expiredFound: 0,
        expiringFound: 3,
      );
      final ko = CabinetCheck(
        cabinetId: 1,
        operator: 'Rossi',
        checkedCount: 10,
        expiredFound: 1,
        expiringFound: 3,
      );

      expect(ok.isClear, isTrue);
      expect(ko.isClear, isFalse);
    });

    test('andata e ritorno dal database senza perdere nulla', () {
      final original = CabinetCheck(
        cabinetId: 7,
        operator: 'Maria Bianchi',
        checkedCount: 12,
        expiredFound: 2,
        expiringFound: 4,
        removedCount: 2,
        notes: 'tolte due confezioni scadute',
        performedAt: DateTime(2026, 8, 13, 9, 30),
      );

      final rebuilt = CabinetCheck.fromMap({...original.toMap(), 'id': 3});

      expect(rebuilt.id, 3);
      expect(rebuilt.cabinetId, 7);
      expect(rebuilt.operator, 'Maria Bianchi');
      expect(rebuilt.checkedCount, 12);
      expect(rebuilt.expiredFound, 2);
      expect(rebuilt.expiringFound, 4);
      expect(rebuilt.removedCount, 2);
      expect(rebuilt.notes, 'tolte due confezioni scadute');
      expect(rebuilt.performedAt, DateTime(2026, 8, 13, 9, 30));
    });

    test('una riga vecchia senza i conteggi non fa esplodere la lettura', () {
      final rebuilt = CabinetCheck.fromMap({
        'id': 1,
        'cabinet_id': 2,
        'performed_at': '2026-08-01T08:00:00.000',
        'operator': 'Verdi',
        'checked_count': null,
        'expired_found': null,
        'expiring_found': null,
        'removed_count': null,
        'notes': null,
      });

      expect(rebuilt.checkedCount, 0);
      expect(rebuilt.isClear, isTrue);
    });
  });

  group('etichetta del periodo', () {
    test('mese e anno in italiano', () {
      expect(CheckReportPdfService.monthLabel(DateTime(2026, 8)), 'agosto 2026');
      expect(
          CheckReportPdfService.monthLabel(DateTime(2026, 1)), 'gennaio 2026');
      expect(CheckReportPdfService.monthLabel(DateTime(2025, 12)),
          'dicembre 2025');
    });
  });

  group('CheckTally', () {
    test('le confezioni scadute tolte durante il controllo restano nel conto',
        () {
      final tally = CheckTally();
      for (var i = 0; i < 3; i++) {
        tally.recordRemoval(RestockBand.expired);
      }
      // Rimaste nell'armadietto: una in scadenza e due a posto.
      const remaining = [RestockBand.red, RestockBand.none, RestockBand.none];

      expect(tally.expiredFound(remaining), 3);
      expect(tally.expiringFound(remaining), 1);
      expect(tally.removed, 3);
    });

    test('una confezione tolta conta anche tra quelle controllate', () {
      final tally = CheckTally()
        ..recordRemoval(RestockBand.yellow)
        ..recordRemoval(RestockBand.none);
      expect(tally.checked(verified: 5), 7);
      expect(tally.expiringFound(const []), 1);
      expect(tally.expiredFound(const []), 0);
    });
  });
}
