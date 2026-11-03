import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/cabinet_check.dart';
import 'pdf_fonts.dart';
import 'temp_files.dart';

/// Un controllo pronto per il report (già abbinato al nome dell'armadietto).
class CheckReportRow {
  CheckReportRow({required this.check, required this.cabinetName});

  final CabinetCheck check;
  final String cabinetName;
}

/// Report generato, pronto da salvare, inviare o condividere.
class CheckReportResult {
  CheckReportResult({
    required this.path,
    required this.bytes,
    required this.fileName,
    required this.periodLabel,
  });

  final String path;
  final List<int> bytes;
  final String fileName;
  final String periodLabel;
}

/// Report mensile dei controlli agli armadietti: chi ha controllato cosa,
/// quando e con quale esito, con in fondo lo spazio per la firma.
class CheckReportPdfService {
  static final _df = DateFormat('dd/MM/yyyy');
  static final _dfTime = DateFormat('dd/MM/yyyy HH:mm');

  static const monthNames = [
    'gennaio',
    'febbraio',
    'marzo',
    'aprile',
    'maggio',
    'giugno',
    'luglio',
    'agosto',
    'settembre',
    'ottobre',
    'novembre',
    'dicembre',
  ];

  static String monthLabel(DateTime month) =>
      '${monthNames[month.month - 1]} ${month.year}';

  /// [month] è un giorno qualsiasi del mese da riportare. [operator] è chi
  /// firma il report, che può non coincidere con chi ha fatto i controlli.
  Future<CheckReportResult?> generate({
    required DateTime month,
    required List<CheckReportRow> rows,
    required String operator,
    List<String> cabinetsWithoutChecks = const [],
    String? notes,
  }) async {
    final periodLabel = monthLabel(month);
    final now = DateTime.now();
    final doc = pw.Document(theme: await PdfFonts.theme());

    final byCabinet = <String, List<CabinetCheck>>{};
    for (final r in rows) {
      byCabinet.putIfAbsent(r.cabinetName, () => []).add(r.check);
    }
    final totalExpired =
        rows.fold<int>(0, (s, r) => s + r.check.expiredFound);
    final totalRemoved =
        rows.fold<int>(0, (s, r) => s + r.check.removedCount);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Report controlli armadietti',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Periodo: $periodLabel  ·  generato il ${_dfTime.format(now)}',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          _summary(
            checks: rows.length,
            cabinets: byCabinet.length,
            expired: totalExpired,
            removed: totalRemoved,
          ),
          if (rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 24),
              child: pw.Text(
                'Nessun controllo registrato in questo periodo.',
                style: const pw.TextStyle(fontSize: 11),
              ),
            )
          else
            ...byCabinet.entries.map((e) => _cabinetSection(e.key, e.value)),
          if (cabinetsWithoutChecks.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              'Armadietti senza controlli nel periodo: ${cabinetsWithoutChecks.join(', ')}',
              style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.red900,
                  fontWeight: pw.FontWeight.bold),
            ),
          ],
          if (notes != null && notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text('Note',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(notes.trim(), style: const pw.TextStyle(fontSize: 10)),
          ],
          pw.SizedBox(height: 28),
          _signature(operator),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Pag. ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );

    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    // I report contengono nomi di operatori: i vecchi non restano in cache.
    await TempFiles.purgeOldPdfs(dir);
    final fileName =
        'Controlli_${DateFormat('yyyy-MM').format(month)}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    return CheckReportResult(
      path: file.path,
      bytes: bytes,
      fileName: fileName,
      periodLabel: periodLabel,
    );
  }

  Future<void> share(CheckReportResult result) => Share.shareXFiles(
        [XFile(result.path, mimeType: 'application/pdf')],
        subject: 'Report controlli armadietti ${result.periodLabel}',
      );

  pw.Widget _summary({
    required int checks,
    required int cabinets,
    required int expired,
    required int removed,
  }) {
    pw.Widget box(String label, String value) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 6),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text(label,
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey700)),
              ],
            ),
          ),
        );

    return pw.Row(children: [
      box('controlli', '$checks'),
      box('armadietti', '$cabinets'),
      box('scaduti trovati', '$expired'),
      box('confezioni tolte', '$removed'),
    ]);
  }

  pw.Widget _cabinetSection(String cabinetName, List<CabinetCheck> checks) {
    pw.Widget cell(String text, {bool header = false, pw.Alignment? align}) =>
        pw.Container(
          alignment: align ?? pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 14),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          color: PdfColors.grey300,
          child: pw.Text(
            '$cabinetName  (${checks.length} controlli)',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.6),
            1: pw.FlexColumnWidth(2.6),
            2: pw.FlexColumnWidth(1.1),
            3: pw.FlexColumnWidth(1.1),
            4: pw.FlexColumnWidth(1.1),
            5: pw.FlexColumnWidth(3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                cell('Data', header: true),
                cell('Operatore', header: true),
                cell('Verif.', header: true, align: pw.Alignment.center),
                cell('Scaduti', header: true, align: pw.Alignment.center),
                cell('Tolte', header: true, align: pw.Alignment.center),
                cell('Note', header: true),
              ],
            ),
            ...checks.map(
              (c) => pw.TableRow(
                children: [
                  cell(_df.format(c.performedAt)),
                  cell(c.operator),
                  cell('${c.checkedCount}', align: pw.Alignment.center),
                  cell('${c.expiredFound}', align: pw.Alignment.center),
                  cell('${c.removedCount}', align: pw.Alignment.center),
                  cell(c.notes ?? ''),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _signature(String operator) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Report compilato da',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 2),
              pw.Text(operator,
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 200, child: pw.Divider(thickness: 0.5)),
              pw.Text('Firma',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
            ],
          ),
        ],
      );
}
