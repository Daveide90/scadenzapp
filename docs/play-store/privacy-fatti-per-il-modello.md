# Informativa privacy: i fatti che il modello deve dire

Per chi compila l'informativa partendo da un modello già pronto. I modelli generici contengono di solito sezioni su cookie, statistiche d'uso, pubblicità, account, server e trasferimenti all'estero: **in ScadenzApp nessuna di queste cose esiste, e vanno tolte**. Un'informativa che dichiara trattamenti inesistenti, o ne tace di reali, è il tipo di inesattezza che Google contesta. Ogni riga qui sotto è verificata sul codice della versione 1.4.0.

| Argomento | Cosa è vero in ScadenzApp |
|---|---|
| Chi la pubblica | Il tuo nome come sviluppatore (quello della scheda di Google Play) e l'alias email dedicato. Mai l'indirizzo personale. |
| Data | Data di efficacia dell'informativa, e la promessa di pubblicare qui le modifiche con la nuova data. |
| Dati raccolti dallo sviluppatore | **Nessuno.** L'app non ha il permesso di accedere a Internet: lo sviluppatore non riceve mai dati. Niente account, registrazione, pubblicità, statistiche d'uso, segnalazioni di crash, profilazione, cookie. |
| Dati salvati sul telefono | Armadietti, farmaci (nome, forma, dosaggio, quantità, scadenza, lotto), farmaci aggiunti a mano, registro dei controlli, impostazioni. Restano solo sul telefono, in un database cifrato (SQLCipher, chiave custodita nel Keystore di Android). |
| Nomi di persone | Nel registro dei controlli l'utente scrive il nome di chi ha controllato. Restano sul telefono e compaiono nel report PDF solo se l'utente lo genera. Se l'app è usata in una struttura, di questi dati risponde la struttura; lo sviluppatore non vi ha accesso. |
| Fotocamera | Usata solo per leggere data, lotto e codici sulla confezione. Le immagini sono elaborate sul telefono (Google ML Kit, versione inclusa nell'app) e non vengono salvate né trasmesse. |
| Impronta e volto | Il blocco facoltativo usa lo sblocco di Android: impronte e volto restano nel sistema, l'app riceve solo «sbloccato» o «non sbloccato». |
| Notifiche | Generate sul telefono. Sulla schermata di blocco non mostrano i nomi dei farmaci. |
| Backup | File cifrato con una password scelta dall'utente (AES-256, chiave derivata con PBKDF2 a 600.000 iterazioni). Va dove lo salva o lo manda l'utente; lo sviluppatore non lo riceve. |
| Copie automatiche | Backup di Android su Google Drive e trasferimento automatico fra telefoni sono spenti. |
| PDF | La lista di reintegro e il report dei controlli non sono cifrati, perché devono aprirsi da chi li riceve. Contengono nomi di farmaci e, nel report, i nomi degli operatori. Escono dal telefono solo se l'utente li condivide; le copie temporanee si cancellano da sole. |
| Dati AIFA | Il catalogo dei farmaci è un file pubblico incluso nell'app; non contiene dati di persone. |
| Destinatari | Nessuno. Nessun dato è venduto, ceduto o trasferito fuori dall'UE. |
| Conservazione | Finché l'utente non cancella i dati nell'app o la disinstalla. |
| Diritti | Tutti i dati sono sul telefono dell'utente, che li vede, li corregge e li cancella dall'app; disinstallare cancella tutto. Per domande, l'alias email. Diritto di reclamo al Garante per la protezione dei dati personali. |
| Minori | L'app è rivolta agli adulti (18+). |

**Da non scrivere**: «l'unica libreria di terze parti è ML Kit» (falso, ce ne sono molte, tutte sul telefono); «PBKDF2 a 210.000 iterazioni» (era la versione 1.3); qualunque riga sul link delle donazioni (tolto).

Quando l'informativa è pubblicata, l'indirizzo va in `lib/app_info.dart` (`privacyPolicyUrl`) e in Play Console.
