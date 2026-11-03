import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/settings_service.dart';

class IntendedUseSection {
  const IntendedUseSection(this.title, this.body);

  final String title;
  final String body;
}

/// Cosa è ScadenzApp e cosa non è. Lo stesso contenuto va nella scheda di
/// Google Play: la destinazione d'uso dichiarata da chi distribuisce un
/// software decide se è un dispositivo medico (regolamento UE 2017/745) e
/// fissa i limiti dell'uso. Se cambia qui, va cambiato anche lì.
List<IntendedUseSection> get intendedUseSections => [
      const IntendedUseSection(
        'A cosa serve',
        'ScadenzApp tiene l\'inventario delle scadenze dei farmaci negli '
            'armadietti: confezioni, quantità, lotti e date di scadenza. '
            'Avvisa quando una scadenza si avvicina, prepara la lista dei '
            'farmaci da reintegrare e il report dei controlli.',
      ),
      const IntendedUseSection(
        'Non è un dispositivo medico',
        'ScadenzApp non è un dispositivo medico. Non dà indicazioni su '
            'diagnosi, terapie, dosaggi o somministrazioni e non va usata per '
            'decidere se un farmaco si può dare a un paziente: per questo '
            'valgono la confezione, il foglietto illustrativo e le procedure '
            'della struttura.',
      ),
      const IntendedUseSection(
        'La confezione fa fede',
        'La data e il lotto letti dalla fotocamera possono essere sbagliati, '
            'e anche quelli scritti a mano. Prima di salvare controlla sempre '
            'quello che è stampato sulla confezione.',
      ),
      IntendedUseSection(
        'Dati AIFA',
        'I nomi dei farmaci vengono dagli open data dell\'AIFA (Agenzia '
            'Italiana del Farmaco) scaricati il $aifaCatalogDateIt: possono '
            'mancare farmaci nuovi, revoche o cambi di confezione successivi. '
            'L\'AIFA non è coinvolta in quest\'app.',
      ),
      const IntendedUseSection(
        'Ritiri e allerte',
        'L\'app non riceve i ritiri di lotti né le allerte sui farmaci: per '
            'quelli valgono le comunicazioni ufficiali (AIFA, Ministero della '
            'Salute, farmacia, struttura). La ricerca per lotto serve a '
            'trovare in fretta le confezioni da togliere.',
      ),
      const IntendedUseSection(
        'Le notifiche possono non arrivare',
        'Dipendono dalle impostazioni del telefono: notifiche spente, '
            'risparmio energetico, data o ora sbagliate possono ritardarle o '
            'bloccarle. Non sostituiscono i controlli periodici degli '
            'armadietti.',
      ),
      const IntendedUseSection(
        'Report e liste',
        'Il report dei controlli e la lista di reintegro aiutano il lavoro; '
            'non sostituiscono i registri, le procedure e le responsabilità '
            'previsti dalla struttura.',
      ),
      const IntendedUseSection(
        'I dati stanno solo su questo telefono',
        'L\'app non ha accesso a Internet e non manda dati a nessuno. Se il '
            'telefono si rompe o l\'app viene disinstallata, i dati si '
            'recuperano solo da un backup salvato fuori dall\'app.',
      ),
      const IntendedUseSection(
        'Senza garanzie',
        'ScadenzApp è gratuita e viene fornita così com\'è, senza garanzie, '
            'nei limiti consentiti dalla legge.',
      ),
    ];

/// Al primo avvio (e dopo l'aggiornamento che l'ha introdotto) l'app dice
/// cos'è e cosa non è, una volta sola.
Future<void> showIntendedUseNoticeIfNeeded(BuildContext context,
    {SettingsService? settings}) async {
  final s = settings ?? SettingsService();
  try {
    if (await s.getIntendedUseAcknowledged()) return;
  } catch (_) {
    return; // impostazioni illeggibili: meglio non bloccare l'avvio
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.info_outline, size: 40),
      title: const Text('Prima di iniziare'),
      content: const SingleChildScrollView(
        child: Text(
          'ScadenzApp tiene l\'inventario delle scadenze dei farmaci negli '
          'armadietti.\n\n'
          'Non è un dispositivo medico e non dice se un farmaco si può usare. '
          'La data stampata sulla confezione fa fede: controllala sempre prima '
          'di salvare quella letta dalla fotocamera.\n\n'
          'I dati stanno solo su questo telefono: salva i backup fuori '
          'dall\'app.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.push(ctx,
              MaterialPageRoute(builder: (_) => const IntendedUseScreen())),
          child: const Text('Leggi tutto'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              await s.setIntendedUseAcknowledged();
            } catch (_) {
              // non salvato: lo si rivedrà al prossimo avvio
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Ho capito'),
        ),
      ],
    ),
  );
}

class IntendedUseScreen extends StatelessWidget {
  const IntendedUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = intendedUseSections;
    return Scaffold(
      appBar: AppBar(title: const Text('Uso previsto e avvertenze')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, i) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sections[i].title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(sections[i].body, style: const TextStyle(height: 1.4)),
          ],
        ),
      ),
    );
  }
}
