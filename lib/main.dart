import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/cabinet_provider.dart';
import 'providers/medicine_provider.dart';
import 'screens/home_screen.dart';
import 'legal/licenses.dart';
import 'screens/lock_screen.dart';
import 'services/app_lock.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';
import 'utils/expiry_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerExtraLicenses();
  // Prima di disegnare: chi ha spento il blocco non deve vederlo comparire.
  await AppLock.load();
  await _loadExpiryThresholds();
  final notificationService = NotificationService();
  await notificationService.init();
  runApp(const ScadenzApp());
  // Reschedule notifiche in background, non blocca l'avvio
  notificationService.rescheduleAll();
}

/// Le soglie dei colori scelte nel reintegro valgono in tutta l'app.
Future<void> _loadExpiryThresholds() async {
  try {
    final settings = SettingsService();
    ExpiryThresholds.redMonths = await settings.getRedMonths();
    ExpiryThresholds.yellowMonths = await settings.getYellowMonths();
  } catch (_) {
    // restano quelle di serie
  }
}

class ScadenzApp extends StatelessWidget {
  const ScadenzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CabinetProvider()),
        ChangeNotifierProxyProvider<CabinetProvider, MedicineProvider>(
          create: (_) => MedicineProvider(),
          update: (_, cabinetProvider, medicineProvider) {
            medicineProvider!.onDataChanged = cabinetProvider.markNeedsReload;
            return medicineProvider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'ScadenzApp',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        // Il blocco avvolge il Navigator: copre anche le schermate aperte
        // sopra la home e i dialoghi.
        builder: (context, child) =>
            LockScreen(child: child ?? const SizedBox.shrink()),
        home: const HomeScreen(),
      ),
    );
  }
}
