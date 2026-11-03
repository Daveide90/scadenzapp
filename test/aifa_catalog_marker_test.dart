import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/services/aifa_catalog_service.dart';

void main() {
  test('due cataloghi con la stessa lunghezza hanno contrassegni diversi', () {
    final a = Uint8List.fromList(List.filled(1000, 1));
    final b = Uint8List.fromList(List.filled(1000, 2));
    expect(AifaCatalogService.markerFor(a),
        isNot(AifaCatalogService.markerFor(b)));
  });

  test('lo stesso catalogo dà sempre lo stesso contrassegno', () {
    final a = Uint8List.fromList(List.generate(1000, (i) => i % 256));
    expect(AifaCatalogService.markerFor(a),
        AifaCatalogService.markerFor(Uint8List.fromList(a)));
  });
}
