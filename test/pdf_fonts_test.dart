import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:scadenzapp/models/cabinet_check.dart';
import 'package:scadenzapp/services/check_report_pdf_service.dart';
import 'package:scadenzapp/services/pdf_fonts.dart';
import 'package:scadenzapp/services/restock_pdf_service.dart';

/// Lettere che Helvetica, il carattere di serie del pacchetto pdf, non ha:
/// nomi rumeni (con virgola e con cediglia) e polacchi, euro, trattino,
/// apostrofo e virgolette curve, maggiore o uguale, puntini.
const _letters = 'ȘșȚțŞşĂăÂâÎîŁłŚśŻżŹźĆćĄąĘęŃńŐőŰű€–’“”≥…';

String _ascii(List<int> bytes) => String.fromCharCodes(bytes);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scadenzapp_pdf_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('il carattere dei PDF ha le lettere dei nomi rumeni e polacchi',
      () async {
    final theme = await PdfFonts.theme();
    final style = theme.defaultTextStyle;
    for (final font in [style.fontNormal!, style.fontBold!]) {
      final pdfFont = font.getFont(pw.Context(document: PdfDocument()));
      final missing = _letters.runes
          .where((r) => !pdfFont.isRuneSupported(r))
          .map(String.fromCharCode)
          .join();
      expect(missing, isEmpty, reason: 'mancano: $missing');
    }
  });

  test('il report dei controlli incorpora il carattere', () async {
    final result = await CheckReportPdfService().generate(
      month: DateTime(2026, 11, 1),
      rows: [
        CheckReportRow(
          check: CabinetCheck(
            cabinetId: 1,
            operator: 'Ștefan Mărgărit',
            checkedCount: 3,
            expiredFound: 1,
            expiringFound: 0,
            performedAt: DateTime(2026, 11, 2, 9),
          ),
          cabinetName: 'Carrello – emergenza',
        ),
      ],
      operator: 'Łukasz Wiśniewski',
    );
    expect(_ascii(result!.bytes), contains('Roboto'));
    expect(_ascii(result.bytes), isNot(contains('Helvetica')));
  });

  test('la lista di reintegro incorpora il carattere', () async {
    final result = await RestockPdfService().generate(
      expired: [
        RestockPdfRow(
          name: 'Paracetamolo 500 mg',
          quantity: 2,
          expirationDate: DateTime(2026, 10, 31),
          cabinetName: 'Armadio dell’ambulatorio',
        ),
      ],
      red: const [],
      yellow: const [],
      redMonths: 1,
      yellowMonths: 3,
    );
    expect(_ascii(result!.bytes), contains('Roboto'));
    expect(_ascii(result.bytes), isNot(contains('Helvetica')));
  });
}
