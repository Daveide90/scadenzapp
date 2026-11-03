import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'pdf_fonts.dart';
import 'temp_files.dart';

/// Una riga della lista da reintegrare (dati già pronti per il PDF).
class RestockPdfRow {
  final String name;
  final int quantity;
  final DateTime expirationDate;
  final String cabinetName;

  RestockPdfRow({
    required this.name,
    required this.quantity,
    required this.expirationDate,
    required this.cabinetName,
  });
}

/// PDF generato, pronto da salvare/inviare/condividere.
class RestockPdfResult {
  final String path;
  final List<int> bytes;
  final String fileName;

  /// Armadietti citati nel PDF (per il testo dell'email).
  final List<String> cabinetNames;

  RestockPdfResult({
    required this.path,
    required this.bytes,
    required this.fileName,
    required this.cabinetNames,
  });
}

/// Genera il PDF della lista "farmaci da reintegrare". La consegna
/// (salvataggio, email, condivisione) è gestita dalla schermata.
class RestockPdfService {
  static final _df = DateFormat('dd/MM/yyyy');

  /// Le liste vuote vengono semplicemente saltate. Restituisce null se non
  /// c'è nulla da esportare.
  Future<RestockPdfResult?> generate({
    required List<RestockPdfRow> expired,
    required List<RestockPdfRow> red,
    required List<RestockPdfRow> yellow,
    required int redMonths,
    required int yellowMonths,
  }) async {
    final total = expired.length + red.length + yellow.length;
    if (total == 0) return null;

    final now = DateTime.now();
    final doc = pw.Document(theme: await PdfFonts.theme());

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
                  'Lista farmaci da reintegrare',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Generata il ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          if (expired.isNotEmpty)
            _section('! Scaduti', expired, PdfColors.red900),
          if (red.isNotEmpty)
            _section(
              'In scadenza (entro ${_mLabel(redMonths)})',
              red,
              PdfColors.red400,
            ),
          if (yellow.isNotEmpty)
            _section(
              'Attenzione (entro ${_mLabel(yellowMonths)})',
              yellow,
              PdfColors.amber700,
            ),
          pw.SizedBox(height: 12),
          pw.Divider(color: PdfColors.grey400),
          pw.Text(
            'Totale: $total farmaci',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
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
    // Le liste vecchie non restano in cache: sono in chiaro, il DB no.
    await TempFiles.purgeOldPdfs(dir);
    final fileName =
        'Reintegro_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    final cabinetNames = <String>{
      for (final r in [...expired, ...red, ...yellow]) r.cabinetName,
    }.toList()
      ..sort();

    return RestockPdfResult(
      path: file.path,
      bytes: bytes,
      fileName: fileName,
      cabinetNames: cabinetNames,
    );
  }

  Future<void> share(RestockPdfResult result) => Share.shareXFiles(
        [XFile(result.path, mimeType: 'application/pdf')],
        subject: 'Lista farmaci da reintegrare',
      );

  static String _mLabel(int months) =>
      months == 1 ? '1 mese' : '$months mesi';

  pw.Widget _section(String title, List<RestockPdfRow> rows, PdfColor color) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 14),
        pw.Container(
          width: double.infinity,
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          color: color,
          child: pw.Text(
            '$title  (${rows.length})',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        _table(rows),
      ],
    );
  }

  pw.Widget _table(List<RestockPdfRow> rows) {
    pw.Widget cell(String text, {bool header = false, pw.Alignment? align}) {
      return pw.Container(
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
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(4),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(3),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            cell('Farmaco', header: true),
            cell('Q.tà', header: true, align: pw.Alignment.center),
            cell('Scadenza', header: true, align: pw.Alignment.center),
            cell('Armadietto', header: true),
          ],
        ),
        ...rows.map(
          (r) => pw.TableRow(
            children: [
              cell(r.name),
              cell('${r.quantity}', align: pw.Alignment.center),
              cell(_df.format(r.expirationDate),
                  align: pw.Alignment.center),
              cell(r.cabinetName),
            ],
          ),
        ),
      ],
    );
  }
}
