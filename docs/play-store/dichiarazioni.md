# Dichiarazioni di Play Console · ScadenzApp 1.4.0

Risposte per Play Console › Policy › Contenuti dell'app. Ogni risposta ha il motivo, verificato sul codice e sull'APK di rilascio il 3/11/2026. Se una funzione cambia (per esempio arriva un permesso Internet), queste risposte vanno riviste prima del caricamento.

## Norme sulla privacy

URL dell'informativa: quello della pagina pubblicata col modello che scegli. La pagina deve essere pubblica, raggiungibile senza login, in HTML e non in PDF. Lo stesso indirizzo va scritto in `lib/app_info.dart` (`privacyPolicyUrl`): l'app lo mostra nelle Impostazioni, come chiede Google («link o testo dentro l'app»). I fatti che il testo deve dire sono in `privacy-fatti-per-il-modello.md`.

## Accesso all'app

**Tutte le funzionalità sono disponibili senza accesso speciale.** Non ci sono account né login. Nota per i revisori, da incollare nel campo delle istruzioni: «Al primo avvio compare la schermata "Prima di iniziare": toccare "Ho capito". Il blocco con impronta o PIN usa lo sblocco del telefono; se il telefono non ha un blocco, l'app si apre direttamente. Si spegne in Impostazioni › Blocco con impronta o PIN.»

## Annunci

**No, l'app non contiene annunci.**

## Classificazione dei contenuti (questionario IARC)

Categoria: «Tutti gli altri tipi di app» (strumento, non gioco, non social). Risposte: **No** a violenza, contenuti sessuali, linguaggio volgare, gioco d'azzardo, sostanze controllate (i farmaci sono citati come inventario, non promossi né venduti), interazione fra utenti, condivisione della posizione, acquisti digitali. Risultato atteso: adatta a tutti (PEGI 3).

## Destinatari

**18 anni e oltre.** L'app è pensata per operatori sanitari e adulti che gestiscono farmaci; scegliere solo la fascia 18+ evita le regole per le famiglie. Non attira bambini: nessun gioco, personaggio o linguaggio per bambini.

## App di notizie, app governative, funzioni finanziarie, COVID-19

**No** a tutte.

## Dichiarazione delle app sanitarie

**Categoria: «Servizi e gestione sanitaria» (Healthcare Services and Management).** Google la descrive anche come «managing healthcare logistics»: l'app gestisce le scorte e le scadenze dei farmaci negli armadietti. Se il modulo chiede domande aggiuntive, rispondere secondo l'uso previsto scritto nella scheda.

**Mai «App dispositivo medico» (Medical Device Apps).** ScadenzApp non è un dispositivo medico: non agisce su un singolo paziente e non dà indicazioni cliniche (regolamento UE 2017/745, guida MDCG 2019-11). Quella voce chiederebbe numero di registrazione del fabbricante, UDI-DI e istruzioni elettroniche.

Alternativa, se Google la chiedesse: «Gestione di farmaci e terapie» (Medication and Treatment Management), che però riguarda soprattutto promemoria per assumere farmaci e aderenza alle terapie.

## Sicurezza dei dati (Data safety)

| Domanda | Risposta | Perché |
|---|---|---|
| La tua app raccoglie o condivide dati utente dei tipi richiesti? | **No** | Il manifest finale non ha il permesso INTERNET (verificato con `aapt2 dump permissions` sull'APK): nessun dato può lasciare il telefono per opera dell'app. |
| Riconoscimento del testo (Google ML Kit) | non è raccolta | È la variante inclusa nell'APK (`text-recognition` 16.0.1, `barcode-scanning` 17.3.0): lavora sul telefono e non scarica modelli. La sua componente di diagnostica non può trasmettere senza il permesso INTERNET. |
| PDF e backup inviati dall'utente | non è condivisione | Avviene solo per azione esplicita dell'utente, verso l'app che sceglie (email, salvataggio): Google non la considera raccolta né condivisione. |

Con «No» alla prima domanda il modulo finisce lì; la scheda mostrerà «Nessun dato raccolto» e «Nessun dato condiviso con terze parti».

## Stato di trader (Digital Services Act)

Account personale dichiarato **non trader**: app gratuita, senza pubblicità, senza acquisti, senza ricavi. Se un giorno l'app diventa fonte di guadagno, lo stato va cambiato prima.

## Test chiuso (beta)

Traccia «Test chiuso», elenco di almeno 12 indirizzi Gmail (consigliati 15), per 14 giorni di fila. Durante il test si possono caricare versioni nuove senza azzerare i 14 giorni. Indirizzo per il feedback: l'alias dedicato.

## Firma

Play App Signing attivo (obbligatorio per le app nuove): la chiave di distribuzione la genera Google, la chiave del PC serve solo per caricare. Per questo chi aveva l'app installata a mano deve disinstallarla prima di installare la versione di Google Play: fare prima il backup e salvarlo fuori dall'app.
