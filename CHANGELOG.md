# Novità di ScadenzApp

## 1.4.2 · 3 novembre 2026 (beta)

**Sicurezza**

- **Password dei backup nuovi di almeno 12 caratteri** invece di 8. I
  backup già fatti con una password più corta si aprono ancora: il
  ripristino non cambia.

**Pulizia del repository**

- Tolte le cartelle iOS, web e desktop (Linux, macOS, Windows) generate da
  Flutter e mai usate: ScadenzApp esce solo per Android.
- I file `.env` con le chiavi locali sono esclusi da git.

## 1.4.1 · 3 novembre 2026 (beta)

**Sicurezza**

- **SQLCipher 4.20.0**, con SQLite del 16/10/2026, al posto della 4.9.0
  (SQLite 3.49.2) arrivata col plugin del database: chiude CVE-2025-6965,
  CVE-2025-7709, CVE-2026-11822 e CVE-2026-11824. Servono SQL scritto
  dall'attaccante o un database costruito apposta, cose che l'app non accetta:
  è un aggiornamento preventivo. Il formato dei database non cambia.
- **Guava 33.7.2** al posto della 33.5.0 arrivata con la fotocamera:
  CVE-2026-102554 (deserializzazione Java, che l'app non usa).
- Controllo di tutte le librerie (121 pacchetti Dart, 106 Android) sul
  database pubblico OSV il 3/11/2026: nessun'altra vulnerabilità nota.

## 1.4.0 · novembre 2026 (beta)

**Nuovo**

- **Ricerca per nome o lotto** in tutti gli armadietti (la lente nella
  home): quando viene ritirato un lotto si vede subito dove sta.
- **Backup salvato fuori dall'app**: dopo il backup il pulsante principale è
  «Salva sul dispositivo». La home ricorda il backup se non ce n'è uno
  salvato fuori o se ha più di 30 giorni («Più tardi» lo rinvia di 7).
  Nel ripristino si eliminano i backup vecchi della cartella dell'app.
- Al primo avvio, **«Prima di iniziare»**: cosa fa l'app e cosa non fa. Il
  testo completo è in Impostazioni › Uso previsto e avvertenze.
- Nelle Impostazioni: fonte dei dati dei farmaci (AIFA, CC BY 4.0) e
  **licenze** di tutti i componenti, comprese le librerie Android.
- **Catalogo AIFA aggiornato al 3 novembre 2026**: 12.680 farmaci, 160.241
  confezioni.

**Corretto**

- I PDF perdevano le lettere fuori dall'alfabeto di base: «Ștefan» usciva
  «tefan», «Łukasz» usciva «ukasz»; sparivano anche €, trattini e
  apostrofi curvi. Ora i PDF usano il carattere Roboto incorporato.
- Date e scritte delle scadenze più leggibili, anche con luce forte: le
  tinte chiare su bianco erano sotto il contrasto minimo per il testo.
- Con i caratteri grandi di Android, data ed etichetta della riga del
  farmaco uscivano dallo schermo.
- I pulsanti a icona hanno tutti una descrizione per il lettore dello
  schermo.
- Gli errori di backup, ripristino e PDF sono spiegati a parole, senza il
  messaggio tecnico.
- Tolta l'email dello sviluppatore dalle Informazioni.

**Sicurezza**

- Backup nel formato 2: l'autenticazione copre anche l'intestazione del
  file (prima un file con l'IV alterato si apriva come integro) e la chiave
  nasce da PBKDF2 a 600.000 iterazioni (prima 210.000). I backup vecchi si
  leggono ancora.
- Spento il trasferimento automatico da telefono a telefono, che copiava il
  database cifrato senza la sua chiave.

**Dalla revisione del 3 novembre**

- Tolto il pulsante per offrire un caffè: ScadenzApp esce gratis su Google
  Play, che non ammette donazioni fuori dal suo sistema di pagamento.
- Nuova schermata **Impostazioni** (icona dell'ingranaggio, al posto di Info):
  il **blocco con impronta o PIN** si può spegnere e riaccendere, sempre dopo
  aver sbloccato il telefono. Di serie resta acceso.
- Se il telefono non ha un PIN, una sequenza o un'impronta, l'app si apre lo
  stesso invece di restare ferma sulla schermata di blocco.
- Il blocco dopo 2 minuti fuori dall'app ora scatta davvero (prima non
  partiva mai) e copre anche le schermate aperte sopra la home; allo sblocco
  si torna dove si era.
- L'email della lista di reintegro trova le app di posta senza passare dal
  menu Condividi.
- **Notifiche**: un solo avviso al giorno con l'elenco dei farmaci («3 farmaci
  da controllare»), invece di uno per confezione. Prima, oltre circa 170
  confezioni, gli avvisi smettevano di essere programmati. Il giorno della
  scadenza l'avviso dice «ultimo giorno di validità». Dopo aver cancellato un
  armadietto o ripristinato un backup non arrivano più avvisi di farmaci che
  non ci sono.
- Se le notifiche sono spente, la home e le Impostazioni lo dicono, con il
  pulsante per riattivarle.
- Una **data corretta a mano** non viene più rimessa dalla lettura automatica.
- Il **report dei controlli** conta tra gli scaduti trovati anche le confezioni
  tolte durante il controllo.
- Un farmaco salvato si corregge per intero: nome, dosaggio e **lotto**.
- Il ripristino di un solo armadietto non cancella più il suo registro dei
  controlli.
- Se i dati salvati non si possono aprire, non vengono più cancellati: sono
  messi da parte e l'app propone di ripristinare un backup.
- Date impossibili lette dall'OCR (31/04, 30/02) non vengono più spostate al
  mese dopo; colori delle scadenze uguali in tutte le schermate, con le soglie
  scelte nel reintegro.

## 1.3.0 — 13 agosto 2026

**Lettura della confezione**

- Dal Data Matrix delle confezioni che ce l'hanno, l'app prende da sola
  **scadenza e lotto**: inquadri e la scheda è già compilata.
- Nuovo campo **lotto**, letto dal codice o dal testo stampato sulla scatola,
  e comunque scrivibile a mano. Serve quando viene ritirato un lotto e devi
  sapere in fretta se ce l'hai.
- Il bollino a barre italiano contiene solo l'AIC: ora, quando la scadenza non
  c'è, l'app te lo dice invece di restare in attesa.
- Il numero della fustella non viene più scambiato per un codice AIC.

**Controlli degli armadietti**

- Nuova sezione **Controlli**: registri chi ha verificato un armadietto e
  quando, spunti le confezioni, togli gli scaduti e lasci una nota.
- **Report mensile in PDF** con il riepilogo, il dettaglio per armadietto,
  gli armadietti rimasti senza controllo e lo spazio per la firma. Si salva,
  si invia per email o si condivide.

**Aspetto**

- Icona nuova, colori dell'app coordinati e illustrazioni nelle schermate
  vuote.

**Privacy**

- L'app **non dichiara più il permesso di accesso a Internet**: non può
  trasmettere nulla verso l'esterno. Tolti anche microfono e memoria esterna,
  che arrivavano dalle librerie senza essere usati.
- I PDF generati non restano nella memoria temporanea del telefono.

**Altro**

- Un pulsante per offrire un caffè allo sviluppatore, se ti va: è una
  donazione libera e non sblocca nessuna funzione.
