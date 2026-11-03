import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Carattere dei PDF (reintegro e report dei controlli).
///
/// Senza un carattere incorporato il pacchetto pdf usa Helvetica, che copre
/// solo il Latin-1: le lettere che non ha spariscono senza errori, e nel
/// report firmato «Ștefan» usciva «tefan», «Łukasz» usciva «ukasz».
/// Roboto, lo stesso carattere di Android, copre lettere rumene e polacche,
/// euro, trattini e apostrofi curvi. Licenza Apache 2.0, nelle licenze
/// dell'app.
class PdfFonts {
  const PdfFonts._();

  static const regularAsset = 'assets/fonts/Roboto-Regular.ttf';
  static const boldAsset = 'assets/fonts/Roboto-Bold.ttf';

  static Future<pw.ThemeData>? _theme;

  /// Il tema si carica una volta sola per tutta la vita dell'app.
  static Future<pw.ThemeData> theme() => _theme ??= _load();

  static Future<pw.ThemeData> _load() async {
    final regular = pw.Font.ttf(await rootBundle.load(regularAsset));
    final bold = pw.Font.ttf(await rootBundle.load(boldAsset));
    return pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      // I PDF non usano il corsivo: se un giorno servisse, meglio dritto
      // con tutte le lettere che inclinato senza.
      italic: regular,
      boldItalic: bold,
    );
  }
}
