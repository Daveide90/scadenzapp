import 'dart:math';
import 'dart:ui';

/// Converte un tocco sul riquadro della fotocamera nel punto normalizzato
/// (0..1) del preview, per `setFocusPoint`/`setExposurePoint`.
///
/// Il preview è mostrato in cover-crop (`BoxFit.cover`): riempie il box
/// ritagliando al centro la parte che non entra. Il tocco va quindi
/// riproiettato sulle coordinate del frame intero, non del box.
///
/// [box] = dimensioni del widget su schermo; [preview] = dimensioni del
/// preview già orientato come mostrato. Null se una dimensione non è valida.
Offset? mapTapToPreviewPoint({
  required Offset tap,
  required Size box,
  required Size preview,
}) {
  if (box.width <= 0 ||
      box.height <= 0 ||
      preview.width <= 0 ||
      preview.height <= 0) {
    return null;
  }
  final scale = max(box.width / preview.width, box.height / preview.height);
  final displayedW = preview.width * scale;
  final displayedH = preview.height * scale;
  final offX = (displayedW - box.width) / 2;
  final offY = (displayedH - box.height) / 2;
  final x = (tap.dx + offX) / displayedW;
  final y = (tap.dy + offY) / displayedH;
  return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
}
