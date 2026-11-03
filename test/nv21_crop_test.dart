import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/utils/nv21_crop.dart';

void main() {
  group('visibleFractions', () {
    test('box con le stesse proporzioni: tutto visibile', () {
      final f = visibleFractions(
          box: const Size(100, 200), preview: const Size(100, 200));
      expect(f.fx, 1.0);
      expect(f.fy, 1.0);
    });

    test('box più basso: si vede una fascia verticale', () {
      // Preview 100x200 in box 100x100 → visibile il 50% dell\'altezza.
      final f = visibleFractions(
          box: const Size(100, 100), preview: const Size(100, 200));
      expect(f.fx, 1.0);
      expect(f.fy, closeTo(0.5, 1e-9));
    });

    test('box più stretto: si vede una fascia orizzontale', () {
      final f = visibleFractions(
          box: const Size(100, 100), preview: const Size(200, 100));
      expect(f.fx, closeTo(0.5, 1e-9));
      expect(f.fy, 1.0);
    });

    test('dimensioni non valide -> tutto visibile (nessun crop)', () {
      final f =
          visibleFractions(box: Size.zero, preview: const Size(100, 100));
      expect(f.fx, 1.0);
      expect(f.fy, 1.0);
    });
  });

  group('cropNv21', () {
    // Frame sintetico 8x4: Y = 32 byte (valore = indice), VU = 8x2 = 16 byte
    // (valore = 100 + indice).
    Uint8List makeFrame() {
      final bytes = Uint8List(8 * 4 + 8 * 2);
      for (var i = 0; i < 32; i++) {
        bytes[i] = i;
      }
      for (var i = 0; i < 16; i++) {
        bytes[32 + i] = 100 + i;
      }
      return bytes;
    }

    test('crop centrale 4x2', () {
      // x=2, y=2, w=4, h=2 (tutti pari).
      final out = cropNv21(makeFrame(), 8, 4, 2, 2, 4, 2);
      expect(out.length, 4 * 2 + 4 * 1);
      // Y: righe 2..3, colonne 2..5 → indici 18,19,20,21 e 26,27,28,29
      expect(out.sublist(0, 8), [18, 19, 20, 21, 26, 27, 28, 29]);
      // VU: riga cromatica 1 (y/2), colonne 2..5 → 100 + (8+2..8+5)
      expect(out.sublist(8), [110, 111, 112, 113]);
    });

    test('crop identità restituisce il frame originale', () {
      final frame = makeFrame();
      final out = cropNv21(frame, 8, 4, 0, 0, 8, 4);
      expect(out, frame);
    });

    test('coordinate dispari vengono allineate a pari', () {
      // x=1 → arrotonda a 0; w=5 → 4 (il VU è campionato 2x2).
      final out = cropNv21(makeFrame(), 8, 4, 1, 0, 5, 4);
      expect(out.length, 4 * 4 + 4 * 2);
    });
  });

  group('computeVisibleCrop', () {
    test('portrait: la frazione verticale su schermo taglia la larghezza sensore', () {
      // Sensore landscape 1280x720; su schermo (portrait) si vede il 50%
      // dell\'altezza → nel sensore va tagliata la larghezza (asse x).
      final crop = computeVisibleCrop(
        sensorWidth: 1280,
        sensorHeight: 720,
        fx: 1.0,
        fy: 0.5,
        portrait: true,
        margin: 0.0,
      );
      expect(crop, isNotNull);
      expect(crop!.width, 640);
      expect(crop.height, 720);
      expect(crop.left, 320);
      expect(crop.top, 0);
    });

    test('margine di sicurezza allarga il ritaglio', () {
      final crop = computeVisibleCrop(
        sensorWidth: 1280,
        sensorHeight: 720,
        fx: 1.0,
        fy: 0.5,
        portrait: true,
        margin: 0.1,
      );
      expect(crop!.width, greaterThan(640));
      expect(crop.width, lessThan(1280));
    });

    test('quasi tutto visibile -> null (crop non conviene)', () {
      final crop = computeVisibleCrop(
        sensorWidth: 1280,
        sensorHeight: 720,
        fx: 0.98,
        fy: 0.95,
        portrait: true,
        margin: 0.1,
      );
      expect(crop, isNull);
    });

    test('risultato sempre pari e dentro i bounds', () {
      final crop = computeVisibleCrop(
        sensorWidth: 1280,
        sensorHeight: 720,
        fx: 0.63,
        fy: 0.41,
        portrait: true,
        margin: 0.1,
      );
      expect(crop, isNotNull);
      expect(crop!.left % 2, 0);
      expect(crop.top % 2, 0);
      expect(crop.width % 2, 0);
      expect(crop.height % 2, 0);
      expect(crop.left + crop.width, lessThanOrEqualTo(1280));
      expect(crop.top + crop.height, lessThanOrEqualTo(720));
    });
  });
}
