/// Le regole della password di un backup nuovo (revisione esterna del 3/11, S4).
/// Il ripristino non le applica: i backup fatti prima con 8 caratteri si aprono ancora.
const minBackupPasswordLength = 12;

/// Il problema della password scelta, da mostrare all'utente, oppure null se va bene.
String? backupPasswordProblem(String password, String confirm) {
  if (password.length < minBackupPasswordLength) {
    return 'La password deve avere almeno $minBackupPasswordLength caratteri';
  }
  if (confirm != password) return 'Le due password non coincidono';
  return null;
}
