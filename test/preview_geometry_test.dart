import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/utils/preview_geometry.dart';

void main() {
  group('mapTapToPreviewPoint', () {
    test('box con le stesse proporzioni del preview: mapping diretto', () {
      const box = Size(100, 200);
      const preview = Size(100, 200);
      expect(
        mapTapToPreviewPoint(
            tap: const Offset(50, 100), box: box, preview: preview),
        const Offset(0.5, 0.5),
      );
      expect(
        mapTapToPreviewPoint(tap: Offset.zero, box: box, preview: preview),
        const Offset(0, 0),
      );
      expect(
        mapTapToPreviewPoint(
            tap: const Offset(100, 200), box: box, preview: preview),
        const Offset(1, 1),
      );
    });

    test('box più basso del preview (crop verticale, cover)', () {
      // Preview 100x200 dentro un box 100x100: si vede solo la fascia
      // centrale verticale (da 25% a 75% del preview).
      const box = Size(100, 100);
      const preview = Size(100, 200);
      expect(
        mapTapToPreviewPoint(
            tap: const Offset(50, 50), box: box, preview: preview),
        const Offset(0.5, 0.5),
      );
      expect(
        mapTapToPreviewPoint(tap: Offset.zero, box: box, preview: preview),
        const Offset(0, 0.25),
      );
      expect(
        mapTapToPreviewPoint(
            tap: const Offset(100, 100), box: box, preview: preview),
        const Offset(1, 0.75),
      );
    });

    test('box più stretto del preview (crop orizzontale, cover)', () {
      // Preview 200x100 dentro un box 100x100: fascia centrale orizzontale.
      const box = Size(100, 100);
      const preview = Size(200, 100);
      expect(
        mapTapToPreviewPoint(tap: Offset.zero, box: box, preview: preview),
        const Offset(0.25, 0),
      );
      expect(
        mapTapToPreviewPoint(
            tap: const Offset(100, 100), box: box, preview: preview),
        const Offset(0.75, 1),
      );
    });

    test('risultato sempre dentro 0..1 anche con tap fuori dal box', () {
      final p = mapTapToPreviewPoint(
        tap: const Offset(-10, 500),
        box: const Size(100, 100),
        preview: const Size(100, 200),
      )!;
      expect(p.dx, inInclusiveRange(0, 1));
      expect(p.dy, inInclusiveRange(0, 1));
    });

    test('dimensioni non valide -> null', () {
      expect(
        mapTapToPreviewPoint(
            tap: Offset.zero, box: Size.zero, preview: const Size(1, 1)),
        isNull,
      );
      expect(
        mapTapToPreviewPoint(
            tap: Offset.zero, box: const Size(1, 1), preview: Size.zero),
        isNull,
      );
    });
  });
}
