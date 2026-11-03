import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'settings_service.dart';

/// Lo sblocco del telefono: impronta, volto, PIN o sequenza.
abstract class DeviceUnlock {
  /// Vero se il telefono ha un blocco schermo o un'impronta registrata:
  /// senza, non c'è niente da chiedere.
  Future<bool> isAvailable();

  /// Chiede lo sblocco del telefono; vero se è riuscito.
  Future<bool> authenticate(String reason);
}

class LocalDeviceUnlock implements DeviceUnlock {
  LocalDeviceUnlock([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate(String reason) => _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // accetta anche PIN e sequenza
          stickyAuth: true,
        ),
      );
}

/// La scelta di proteggere l'app con lo sblocco del telefono.
///
/// Di serie è attiva, come nelle versioni senza la scelta. Si cambia dalle
/// Impostazioni e solo dopo uno sblocco riuscito: chi trova l'app aperta
/// non può spegnere il blocco.
class AppLock {
  AppLock._();

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static Future<void> load([SettingsService? settings]) async {
    try {
      enabled.value = await (settings ?? SettingsService()).getAppLockEnabled();
    } catch (_) {
      enabled.value = true; // nel dubbio l'app resta protetta
    }
  }

  static Future<void> setEnabled(bool value, [SettingsService? settings]) async {
    await (settings ?? SettingsService()).setAppLockEnabled(value);
    enabled.value = value;
  }
}
