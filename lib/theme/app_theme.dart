import 'package:flutter/material.dart';

/// I colori dell'app, in un posto solo.
///
/// Il verde principale è quello dell'icona e dello splash: se cambia lì,
/// cambia qui, e l'app resta coordinata.
class AppColors {
  const AppColors._();

  /// Verde dell'icona (adaptive icon background e splash).
  static const primary = Color(0xFF055029);

  /// Verde più chiaro per accenti e stati attivi.
  static const secondary = Color(0xFF2E7D32);

  /// Verde tenue dei riempimenti, come nelle illustrazioni.
  static const mint = Color(0xFFE8F5E9);

  /// Scaduto: rosso scuro, la cosa più grave da vedere in lista.
  static const expired = Color(0xFFB71C1C);

  /// In scadenza (fascia rossa).
  static const expiring = Color(0xFFEF5350);

  /// Attenzione (fascia gialla).
  static const warning = Color(0xFFFFA000);
}

/// Tema chiaro dell'app. L'app resta sempre chiara: si usa in reparto,
/// spesso con luce forte, e il contrasto alto è più leggibile.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      floatingLabelStyle: const TextStyle(color: AppColors.primary),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.grey.shade200,
      space: 1,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.primary),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.primary),
  );
}
