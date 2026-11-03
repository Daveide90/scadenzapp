# Revisione del codice di ScadenzApp prima della pubblicazione (3/11/2026)

Revisione fatta a mano sul ramo `pre-produzione` dopo il commit `bb3b153`. Letti per intero database, backup, notifiche, provider, modelli, parser delle date, utilità delle scadenze e scheda di conferma; delle schermate (scansione, armadietto, controllo, home) le parti che salvano o cambiano dati. Nessuna correzione fatta: si parte col via dell'autore.

## TL;DR

Dodici rilievi da correggere prima del test chiuso, più nove miglioramenti piccoli. **I cinque gravi** toccano i dati: una data corretta a mano può essere rimessa sbagliata dall'OCR; se il database non si apre l'app lo cancella in silenzio; il report dei controlli conta zero scaduti quando le confezioni scadute vengono tolte durante il controllo; oltre circa 170 confezioni le notifiche smettono di essere programmate senza avviso; dopo aver cancellato un armadietto o ripristinato un backup arrivano avvisi di farmaci che non ci sono più. Lavoro stimato: circa 5 ore per i gravi, 7 per i medi, 2 per i piccoli.

## Gravi: dati sbagliati o persi senza che l'utente lo sappia

| # | Problema | Dove | Correzione | Tempo |
|---|---|---|---|---|
| A1 | **La data scelta a mano viene rimessa dall'OCR.** La scansione si ferma solo col pulsante pausa; se l'utente corregge la data nel calendario e la fotocamera continua a vedere la scatola, dopo 3 letture concordi (circa 9 secondi) l'«auto-correzione» chiama `updateDate` e rimette la data letta, che l'utente salva credendola sua. Il nome è protetto (`_nameManuallyEdited`), la data no. Vale anche per la data del Data Matrix | `scan_screen.dart` 329, 347, 538; `confirm_sheet.dart` 111, 190 | richiamo `onDateEdited` dalla scheda e blocco di OCR e Data Matrix dopo una modifica a mano, come per il nome | 30 min |
| A2 | **Il database illeggibile viene cancellato in silenzio.** Se l'apertura fallisce per qualunque motivo (chiave cambiata, file rovinato, errore in una migrazione futura) il «recupero 2» cancella tutti i file e riparte con 4 armadietti vuoti, senza un messaggio | `database_helper.dart` 80-83 | rinominare il file (`scadenzapp.db.non-leggibile-<data>`) invece di cancellarlo e mostrare in home «I dati di prima non si sono potuti aprire: ripristina un backup» | 1 h |
| A3 | **Il report dei controlli sottostima gli scaduti.** «Togli» durante il controllo cancella subito il farmaco; gli scaduti e gli «in scadenza» si contano al salvataggio sulla lista rimasta. Tre scatole scadute tolte diventano «Scaduti trovati: 0, Rimossi: 3» | `cabinet_check_screen.dart` 69-98, 112-117 | contare la fascia di ogni confezione nel momento in cui si toglie e sommarla ai totali | 30 min |
| A4 | **Tetto delle notifiche.** Tre sveglie per confezione (30 giorni prima, 7 giorni prima, giorno di scadenza); Android ne accetta 500 in attesa per app: oltre circa 170 confezioni con scadenza futura le altre non vengono programmate (l'errore è ignorato in `rescheduleAll`). In più `addMedicine` salva nel database e poi lancia l'errore: la scheda resta aperta, l'utente risalva e crea un doppione | `notification_service.dart` 61-118; `medicine_provider.dart` 21-34; `scan_screen.dart` 864 | una notifica per **giorno** e non per confezione («3 farmaci scadono tra 7 giorni: …»), identificativo dalla data; programmazione dentro un try nei provider, così un errore delle notifiche non tocca mai il salvataggio | 2 h e mezza |
| A5 | **Avvisi di farmaci che non esistono più.** Cancellare un armadietto elimina i farmaci a cascata ma non le loro notifiche; dopo un ripristino da backup le notifiche non vengono riprogrammate. Si sistema solo alla successiva riapertura a freddo dell'app | `cabinet_provider.dart` 54-58; `home_screen.dart` 483-484 | `rescheduleAll` dopo cancellazione di un armadietto e dopo ogni ripristino (con A4 costa poco) | 20 min |

## Medi

| # | Problema | Dove | Correzione | Tempo |
|---|---|---|---|---|
| M1 | Il ripristino del backup di **un solo armadietto** lo cancella e lo reinserisce: per `ON DELETE CASCADE` sparisce anche il suo registro dei controlli, che nel backup singolo non c'è | `database_helper.dart` 610-621 | aggiornare l'armadietto esistente e sostituire solo i farmaci, tenendo l'id; posizione nuova solo se l'armadietto non c'era | 30 min |
| M2 | Date impossibili accettate e spostate: «31/04/2027» diventa 1 maggio, «30/02» diventa 2 marzo (Dart normalizza in silenzio) | `date_parser.dart` 333-335, 390-394, 407-412 | scartare la data se il mese ricostruito non è quello letto | 10 min |
| M3 | Il parser delle date, la parte che decide la scadenza, **non ha test**, e la sua logica è copiata in due funzioni che hanno già cominciato a divergere (la correzione OCR delle date senza separatore c'è solo in `parseExpiryDateFromLines`). Senza test anche `medicine_matcher.dart` | `date_parser.dart` 18-152 | una funzione sola; test con testi di scatole vere (produzione più scadenza, solo mese, giorno primo, nomi dei mesi, scatola già scaduta) | 2 h |
| M4 | Se l'utente nega il permesso delle notifiche l'app non lo dice mai: `notificationsAllowed` è calcolato e mai usato | `notification_service.dart` 18, 52 | avviso in home e nelle Impostazioni con il pulsante per le impostazioni di Android | 45 min |
| M5 | Nel foglio «Testo riconosciuto» toccare una riga non cambia il nome se il campo è già pieno: chiama `updateName`, che scrive solo nel campo vuoto | `scan_screen.dart` 929 | `forceUpdateName` | 5 min |
| M6 | Backup: l'HMAC copre i dati cifrati ma non intestazione, sale e IV; PBKDF2 a 210.000 iterazioni calcolato due volte | `backup_service.dart` 144-163, 195-201, 223-233 | formato 2: una sola derivazione da 64 byte a 600.000 iterazioni divisa in chiave di cifratura e chiave HMAC, HMAC su tutto ciò che precede il tag; i backup in formato 1 restano leggibili | 2 h |
| M7 | Un farmaco salvato non si può correggere: la modifica cambia solo quantità e scadenza, non nome, dosaggio e soprattutto **lotto**, che serve proprio nei ritiri | `cabinet_screen.dart` 28-112 | campi nome, dosaggio e lotto nella modifica | 45 min |

## Piccoli

| # | Problema | Dove | Correzione |
|---|---|---|---|
| B1 | Calendari fino al 2040, parser fino al 2045: con una data letta oltre il 2040 il calendario parte fuori dai limiti | `confirm_sheet.dart` 195; `cabinet_screen.dart` 83 | stesso limite ovunque (2045) |
| B2 | Colori diversi per lo stesso farmaco: home e armadietti usano 30 e 90 giorni fissi, il reintegro le soglie scelte (1 o 2 e da 3 a 6 mesi) | `expiry_utils.dart` 5-15 | una classificazione sola con le soglie dell'utente |
| B3 | Ora legale: `difference().inDays` su mezzanotti locali tronca le 23 ore; una scadenza del 28 o 29 marzo risulta «in scadenza» per un giorno invece di «scaduto» | `expiry_utils.dart` 9 | date in UTC |
| B4 | Le espressioni regolari del parser si ricompilano a ogni fotogramma (CPU e calore in scansione) | `date_parser.dart` 307, 341, 356 | compilarle una volta |
| B5 | Ogni backup lascia un file nella cartella dell'app, mai cancellato | `backup_service.dart` 73-86 | tenere gli ultimi 10 |
| B6 | Il catalogo AIFA si reinstalla solo se cambia la **lunghezza** del file compresso | `aifa_catalog_service.dart` 89-110 | numero di versione o impronta |
| B7 | La notifica dice «SCADUTO oggi!» nel giorno che è ancora l'ultimo di validità (le scadenze «mese/anno» valgono fino all'ultimo giorno del mese) | `notification_service.dart` 77 | «scade oggi, ultimo giorno di validità» |
| B8 | `qtyController.dispose` in `whenComplete` mentre il dialogo sta ancora chiudendo | `cabinet_screen.dart` 112 | eliminarlo dopo l'animazione |
| B9 | Migrazione dal vecchio database in chiaro: un file `.encrypted` lasciato da un'interruzione blocca la migrazione per sempre | `database_helper.dart` 171-188 | cancellarlo prima dell'ATTACH |

## Cosa regge

Cifratura del database (SQLCipher 4.20 dalla 1.4.1 (prima 4.9), chiave casuale da 256 bit, `resetOnError: false`), apertura condivisa contro le corse all'avvio, ripristino completo validato prima di cancellare e dentro una transazione, confronto dell'HMAC a tempo costante, lavoro pesante del backup in un isolate, notifiche nascoste sulla schermata di blocco, nome protetto dalle sovrascritture, scheda di conferma con il doppio tocco bloccato, lettore GS1 e AIC con test. Analisi statica pulita (3 note di stile), 119 test verdi, OSV: nessuna vulnerabilità nota sui 112 pacchetti.

## Ordine proposto

A1, A3, M5, M2 (un'ora in tutto, i più rapidi sui dati), poi A4 con A5, A2, M1, M6 con il punto 2.5 del piano, M3, M4, M7, infine B1, B3, B7. Ogni correzione con il suo test prima.

## Stato delle correzioni (3/11/2026, notte)

Fatte tutte tranne B5, ognuna col suo test scritto prima e visto fallire (M5 senza test: la schermata di scansione non si avvia senza fotocamera; A5 provato dalla parte che calcola gli avvisi, la chiamata dopo cancellazioni e ripristini no).

| Commit | Punti |
|---|---|
| `4b20eb3` | A1 data scelta a mano protetta, A3 conteggi del controllo, M5 «Testo riconosciuto», M2 date impossibili |
| `54f917b` | A4 un avviso per giorno (tetto 400), A5 riprogrammazione dopo cancellazioni e ripristini, B7 «ultimo giorno di validità» |
| `876b8cf` | A2 database messo da parte e avviso in home, B9 `.encrypted` rimasto |
| `ffcef01` | M1 ripristino di un armadietto senza perdere i controlli (test su database vero con `sqflite_common_ffi`, solo sviluppo) |
| `49ffb41` | M6 backup formato 2 (una PBKDF2 a 600.000, HMAC su tutto il file; il formato 1 si legge ancora, campione in `test/fixtures`) |
| `c5477d9` | M3 parser con una sola logica e test su scatole tipiche, B4 espressioni compilate una volta |
| `055e16c` | M4 avviso «Notifiche spente» in home e Impostazioni |
| `c30bc8c` | M7 modifica completa (nome, dosaggio, lotto), B1 calendari fino al 2045, B8 |
| `51a0b34` | B2 stessi colori ovunque con le soglie dell'utente, B3 ora legale |
| commit successivi | B6 contrassegno del catalogo AIFA, punto 2.1 del piano (niente trasferimento tra telefoni) |

**Non fatto, B5** (backup che si accumulano nella cartella dell'app): cancellarli da soli vorrebbe dire eliminare file dell'utente senza chiedere. Meglio un pulsante «Elimina» nell'elenco del ripristino: da decidere.

**Da provare sul telefono** in aggiunta al giro del piano: una riga scelta da «Testo riconosciuto» sostituisce il nome; l'avviso del giorno con più farmaci; tempo di backup e ripristino col formato 2 (PBKDF2 a 600.000 iterazioni, sul PC circa 3 secondi); `sqflite_common` salito da 2.5.4 a 2.5.14.
