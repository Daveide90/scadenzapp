import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../database/database_helper.dart';
import 'notification_plan.dart';
import '../theme/app_theme.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// True se l'utente ha concesso il permesso notifiche (Android 13+).
  bool notificationsAllowed = false;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    // Imposta il fuso LOCALE: senza questo tz.local resta UTC e le notifiche
    // scatterebbero all'ora sbagliata (in Italia +1/+2h, e il controllo "data futura"
    // diventa inaffidabile sul giorno di confine).
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('Europe/Rome'));
      } catch (_) {}
    }

    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Richiedi il permesso notifiche su Android 13+ (await: non fire-and-forget,
    // così sappiamo se sono abilitate e l'init è deterministico).
    final android = _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      notificationsAllowed =
          await android.requestNotificationsPermission() ?? false;
    }

    _initialized = true;
  }

  /// Il permesso c'è adesso? (si può cambiare da fuori, dalle impostazioni)
  Future<bool> areEnabled() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.areNotificationsEnabled() ?? true;
  }

  /// Richiede il permesso; se Android non mostra più la domanda (rifiutata
  /// già due volte) apre le impostazioni dell'app.
  Future<void> askToEnable() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? false;
    if (!granted) await openAppSettings();
  }

  bool _running = false;
  bool _again = false;

  /// Riprogramma tutti gli avvisi dal database: uno per giorno (vedi
  /// [planNotifications]), così si resta sotto il tetto di Android anche con
  /// centinaia di confezioni. Si chiama all'avvio e dopo ogni modifica dei
  /// farmaci, la cancellazione di un armadietto, un ripristino.
  ///
  /// Non lancia mai: un errore delle notifiche non deve toccare il
  /// salvataggio dei dati. Le richieste che arrivano mentre lavora si
  /// raccolgono in un solo giro successivo.
  Future<void> rescheduleAll() async {
    _again = true;
    if (_running) return;
    _running = true;
    try {
      while (_again) {
        _again = false;
        await _rescheduleOnce();
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _rescheduleOnce() async {
    try {
      // Leggi PRIMA i farmaci: se il DB non si apre, evitiamo di cancellare
      // tutte le notifiche senza poterle ri-programmare.
      final medicines = await DatabaseHelper().getAllMedicines();
      final plan = planNotifications(medicines, now: DateTime.now());
      await _notifications.cancelAll();
      for (final n in plan) {
        try {
          await _notifications.zonedSchedule(
            n.id,
            n.title,
            n.body,
            tz.TZDateTime.from(n.when, tz.local),
            NotificationDetails(
              android: AndroidNotificationDetails(
                'expiry_channel',
                'Scadenze farmaci',
                channelDescription: 'Notifiche scadenza farmaci',
                importance: Importance.high,
                priority: Priority.high,
                // La barra di stato usa solo la trasparenza dell'immagine:
                // con l'icona a colori si vedrebbe un quadrato bianco.
                icon: '@drawable/ic_notification',
                color: AppColors.primary,
                visibility: NotificationVisibility.secret,
                styleInformation: BigTextStyleInformation(n.body),
              ),
              iOS: const DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        } catch (_) {}
      }
    } catch (_) {
      // Mai propagare.
    }
  }
}
