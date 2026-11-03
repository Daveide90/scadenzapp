import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/services/backup_password.dart';

void main() {
  test('11 caratteri non bastano', () {
    expect(backupPasswordProblem('a' * 11, 'a' * 11),
        'La password deve avere almeno 12 caratteri');
  });

  test('12 caratteri ripetuti uguali vanno bene', () {
    expect(backupPasswordProblem('a' * 12, 'a' * 12), isNull);
  });

  test('la conferma diversa si segnala', () {
    expect(backupPasswordProblem('a' * 12, 'b' * 12),
        'Le due password non coincidono');
  });

  test('prima la lunghezza, poi la conferma', () {
    expect(backupPasswordProblem('corta', 'diversa'),
        'La password deve avere almeno 12 caratteri');
  });
}
