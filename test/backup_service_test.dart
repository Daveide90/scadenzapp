import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/services/backup_service.dart';

void main() {
  cryptoTests();
  group('BackupService.slugify', () {
    test('nome semplice', () {
      expect(BackupService.slugify('Carrello Emergenza'), 'Carrello_Emergenza');
    });

    test('caratteri speciali sostituiti', () {
      expect(
        BackupService.slugify('Frigo Farmaci 2-8°C!'),
        'Frigo_Farmaci_2_8_C',
      );
    });

    test('accentate mantenute', () {
      expect(BackupService.slugify('Unità Cardiologia'), 'Unità_Cardiologia');
    });

    test('nome vuoto o solo simboli -> fallback', () {
      expect(BackupService.slugify(''), 'armadietto');
      expect(BackupService.slugify('***'), 'armadietto');
    });

    test('nomi lunghi troncati a 24', () {
      final slug = BackupService.slugify('A' * 50);
      expect(slug.length, 24);
    });
  });
}

const _password = 'password-di-prova';

Map<String, dynamic> _sample() => {
      'cabinets': [
        {'id': 1, 'name': 'Armadietto 1', 'position': 0, 'sync_code': 'ABC123'}
      ],
      'medicines': <Object>[],
      '_meta': {'version': 2, 'type': 'full'},
    };

void cryptoTests() {
  group('backup cifrato', () {
    test('i backup nuovi sono in formato 2 e si rileggono', () {
      final blob = BackupService.encryptBlob(_sample(), _password);
      expect(blob[13], 2);
      final back = BackupService.decryptAndDecode(blob, _password);
      expect(back['cabinets'], _sample()['cabinets']);
    });

    test('password sbagliata: errore di integrità', () {
      final blob = BackupService.encryptBlob(_sample(), _password);
      expect(
        () => BackupService.decryptAndDecode(blob, 'altra-password'),
        throwsA(predicate((e) => '$e'.contains('Password errata'))),
      );
    });

    test('un IV modificato viene scoperto (l\'HMAC copre anche l\'intestazione)',
        () {
      final blob = BackupService.encryptBlob(_sample(), _password);
      // Byte 4 dell'IV: in CBC cambia il byte 4 del gzip (la data), che gunzip
      // accetterebbe senza accorgersene.
      final tampered = Uint8List.fromList(blob)..[13 + 1 + 32 + 4] ^= 0x01;
      expect(
        () => BackupService.decryptAndDecode(tampered, _password),
        throwsA(predicate((e) => '$e'.contains('Password errata'))),
      );
    });

    test('i backup in formato 1 fatti dalle versioni precedenti si leggono',
        () {
      final old = File('test/fixtures/backup_v1.bak').readAsBytesSync();
      expect(old[13], 1);
      final data = BackupService.decryptAndDecode(old, _password);
      expect((data['medicines'] as List).single['name'], 'TACHIPIRINA');
    });
  });
}
