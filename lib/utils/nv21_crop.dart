import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

/// Ritaglio dell'area VISIBILE del frame camera prima di darlo a ML Kit:
/// i pixel nascosti dal cover-crop non vengono mai mostrati all'utente,
/// analizzarli è solo CPU sprecata. Meno pixel = OCR/barcode più veloci
/// a parità di risultato (ML Kit: "il testo deve riempire l'immagine").

/// Frazioni (larghezza, altezza) del preview effettivamente visibili nel
/// box, con il preview renderizzato in `BoxFit.cover`. 1.0 = tutto visibile.
({double fx, double fy}) visibleFractions({
  required Size box,
  required Size preview,
}) {
  if (box.width <= 0 ||
      box.height <= 0 ||
      preview.width <= 0 ||
      preview.height <= 0) {
    return (fx: 1.0, fy: 1.0);
  }
  final scale = max(box.width / preview.width, box.height / preview.height);
  return (
    fx: min(1.0, box.width / (preview.width * scale)),
    fy: min(1.0, box.height / (preview.height * scale)),
  );
}

/// Rettangolo di ritaglio in pixel del sensore (tutti valori pari).
class CropRect {
  final int left;
  final int top;
  final int width;
  final int height;

  const CropRect(this.left, this.top, this.width, this.height);
}

/// Converte le frazioni visibili su schermo in un ritaglio del frame
/// sensore (landscape). In portrait l'asse verticale dello schermo
/// corrisponde alla larghezza del sensore (rotazione 90°/270°); il taglio
/// è centrato quindi il verso della rotazione non conta.
///
/// [margin] allarga il ritaglio su ogni lato come frazione (es. 0.1).
/// Ritorna null se il ritaglio non fa risparmiare abbastanza (>90% visibile).
CropRect? computeVisibleCrop({
  required int sensorWidth,
  required int sensorHeight,
  required double fx,
  required double fy,
  required bool portrait,
  double margin = 0.1,
}) {
  var widthFrac = portrait ? fy : fx;
  var heightFrac = portrait ? fx : fy;
  widthFrac = min(1.0, widthFrac + 2 * margin);
  heightFrac = min(1.0, heightFrac + 2 * margin);

  if (widthFrac >= 0.9 && heightFrac >= 0.9) return null;

  int even(int v) => v & ~1;
  final w = even((sensorWidth * widthFrac).round().clamp(2, sensorWidth));
  final h = even((sensorHeight * heightFrac).round().clamp(2, sensorHeight));
  final left = even((sensorWidth - w) ~/ 2);
  final top = even((sensorHeight - h) ~/ 2);
  return CropRect(left, top, w, h);
}

/// Ritaglia un buffer NV21 (Y pieno + piano VU interlacciato, stride ==
/// width). Coordinate e dimensioni vengono allineate a valori pari
/// (il piano cromatico è campionato 2x2). Ritorna un nuovo buffer compatto.
Uint8List cropNv21(
  Uint8List src,
  int width,
  int height,
  int x,
  int y,
  int w,
  int h,
) {
  x = (x & ~1).clamp(0, width - 2);
  y = (y & ~1).clamp(0, height - 2);
  w = (w & ~1).clamp(2, width - x);
  h = (h & ~1).clamp(2, height - y);

  final out = Uint8List(w * h + w * (h ~/ 2));
  var o = 0;
  // Piano Y
  for (var r = y; r < y + h; r++) {
    final start = r * width + x;
    out.setRange(o, o + w, src, start);
    o += w;
  }
  // Piano VU (mezza altezza, byte V/U interlacciati: offset x identico)
  final vuBase = width * height;
  for (var r = y ~/ 2; r < (y + h) ~/ 2; r++) {
    final start = vuBase + r * width + x;
    out.setRange(o, o + w, src, start);
    o += w;
  }
  return out;
}
