import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/models/medicine.dart';
import 'package:scadenzapp/utils/expiry_utils.dart';
import 'package:scadenzapp/widgets/medicine_tile.dart';

/// Rapporto di contrasto WCAG 2.1 fra due colori opachi.
double contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double lum(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final l1 = lum(a), l2 = lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// Il colore come appare su bianco con l'opacità data (le tinte dei riquadri).
Color tint(Color c, double alpha) => Color.alphaBlend(
    c.withValues(alpha: alpha), Colors.white);

/// Minimo delle linee guida di accessibilità per il testo normale (AA).
const _min = 4.5;

void main() {
  test('il testo di ogni stato si legge su bianco e sulla sua tinta', () {
    final dates = {
      ExpiryStatus.expired: DateTime.now().subtract(const Duration(days: 3)),
      ExpiryStatus.critical: DateTime.now().add(const Duration(days: 10)),
      ExpiryStatus.warning: DateTime.now().add(const Duration(days: 70)),
      ExpiryStatus.ok: DateTime.now().add(const Duration(days: 400)),
    };
    for (final e in dates.entries) {
      expect(getExpiryStatus(e.value), e.key);
      final text = getExpiryTextColor(e.value);
      final vivid = getExpiryColor(e.value);
      expect(contrast(text, Colors.white), greaterThanOrEqualTo(_min),
          reason: '${e.key} su bianco');
      expect(contrast(text, tint(vivid, 0.15)), greaterThanOrEqualTo(_min),
          reason: '${e.key} sulla sua tinta');
    }
  });

  test('anche le fasce del reintegro e del controllo', () {
    for (final band in RestockBand.values) {
      expect(contrast(restockTextColor(band), Colors.white),
          greaterThanOrEqualTo(_min),
          reason: '$band');
    }
  });

  testWidgets('nella riga del farmaco nessun testo colorato è illeggibile',
      (tester) async {
    for (final days in [-3, 10, 70, 400]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MedicineTile(
            medicine: Medicine(
              id: 1,
              cabinetId: 1,
              name: 'Paracetamolo 500 mg',
              expirationDate: DateTime.now().add(Duration(days: days)),
              lot: 'A123',
            ),
            onTap: () {},
            onDelete: () {},
          ),
        ),
      ));
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final color = t.style?.color;
        if (color == null) continue;
        expect(contrast(color, Colors.white), greaterThanOrEqualTo(_min),
            reason: '«${t.data}» a $days giorni');
      }
    }
  });
}
