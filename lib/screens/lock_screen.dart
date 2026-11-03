import 'package:flutter/material.dart';
import '../services/app_lock.dart';
import '../theme/app_theme.dart';

/// Blocco dell'app con lo sblocco del telefono.
///
/// Sta in `MaterialApp.builder`, sopra il Navigator: copre anche le schermate
/// aperte sopra la home e i dialoghi. Dopo il primo sblocco l'app resta
/// montata e viene solo nascosta, così allo sblocco si torna dove si era.
class LockScreen extends StatefulWidget {
  final Widget child;
  final DeviceUnlock? deviceUnlock;

  /// Orologio, sostituibile nei test.
  final DateTime Function() now;

  const LockScreen({
    super.key,
    required this.child,
    this.deviceUnlock,
    this.now = DateTime.now,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  late final DeviceUnlock _unlock = widget.deviceUnlock ?? LocalDeviceUnlock();
  bool _authenticated = false;
  bool _everUnlocked = false;
  bool _authenticating = false;
  bool _failed = false;
  DateTime? _pausedAt;

  /// Tempo massimo in background prima di ri-bloccare (2 minuti)
  static const _lockTimeout = Duration(minutes: 2);

  bool get _locked => AppLock.enabled.value && !_authenticated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLock.enabled.addListener(_onSettingChanged);
    if (AppLock.enabled.value) {
      _authenticate();
    } else {
      _everUnlocked = true;
    }
  }

  @override
  void dispose() {
    AppLock.enabled.removeListener(_onSettingChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// La scelta cambia solo dalle Impostazioni, dopo uno sblocco riuscito:
  /// chi la cambia è già dentro l'app.
  void _onSettingChanged() {
    setState(() {
      _authenticated = true;
      _everUnlocked = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Solo la prima volta: al ritorno Flutter ripassa da hidden (paused,
      // hidden, inactive, resumed) e qui riscriveva l'ora di uscita con
      // quella del rientro, così il blocco dopo 2 minuti non scattava mai.
      _pausedAt ??= widget.now();
    } else if (state == AppLifecycleState.resumed) {
      if (AppLock.enabled.value && _authenticated && _pausedAt != null) {
        final elapsed = widget.now().difference(_pausedAt!);
        if (elapsed >= _lockTimeout) {
          setState(() {
            _authenticated = false;
            _failed = false;
          });
          _authenticate();
        }
      }
      _pausedAt = null;
    }
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    _authenticating = true;

    try {
      // Senza un blocco sul telefono non c'è niente da chiedere: l'app si
      // apre, e il blocco torna da solo quando il telefono ne avrà uno.
      final success = !await _unlock.isAvailable() ||
          await _unlock.authenticate('Sblocca ScadenzApp');

      if (mounted) {
        setState(() {
          _authenticated = success;
          _failed = false;
          if (success) _everUnlocked = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!locked || _everUnlocked)
          Offstage(
            key: const ValueKey('app'),
            offstage: locked,
            child: ExcludeFocus(
              excluding: locked,
              child: TickerMode(enabled: !locked, child: widget.child),
            ),
          ),
        if (locked) _buildLock(context),
      ],
    );
  }

  Widget _buildLock(BuildContext context) {
    return Scaffold(
      key: const ValueKey('blocco'),
      backgroundColor: AppColors.primary,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.white70),
              const SizedBox(height: 24),
              const Text(
                'ScadenzApp',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _failed
                    ? 'Lo sblocco non è riuscito. Riprova tra qualche secondo.'
                    : 'Sblocca per accedere',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 16),
              ),
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Sblocca', style: TextStyle(fontSize: 18)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white24,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
