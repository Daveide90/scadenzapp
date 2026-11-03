# Ricerca farmaci per codice AIC — Design

Data: 2026-07-09 · Approvato dall'utente in chat (approccio A + tutte e 3 le modalità di input)

## Obiettivo

Identificare un farmaco tramite il suo codice AIC (9 cifre, identifica la singola
confezione: nome + dosaggio + formato), in tre modi:

1. **Campo nome del ConfirmSheet** — se l'utente digita 9 cifre, lookup e compilazione
   automatica di nome, dosaggio e forma.
2. **OCR durante la scansione** — sequenze di 9 cifre nelle righe OCR (priorità a quelle
   vicine alla parola "AIC") vengono cercate nel catalogo; un hit è un match al 100% e
   batte il matching per nome.
3. **Barcode** — lettura del bollino farmaceutico (Code 32, letto da ML Kit come Code 39,
   da decodificare in base 32 → 9 cifre) e del Data Matrix/EAN dei pacchi recenti
   (si estraggono le finestre di 9 cifre e si validano col lookup).

## Fonte dati

Open data AIFA `https://drive.aifa.gov.it/farmaci/confezioni_fornitura.csv`
(aggiornato quotidianamente): 159.679 confezioni **Autorizzate** con
CODICE_AIC, COD_FARMACO, DENOMINAZIONE, DESCRIZIONE, PA_ASSOCIATI, FORMA.

## Architettura

- **Catalogo SQLite read-only** `assets/aifa_catalog.db.gz` (~3,5 MB nell'APK,
  ~20 MB decompresso), separato dal DB cifrato dell'utente (è un catalogo pubblico).
  Schema normalizzato:
  - `farmaci(cod_farmaco PK, denominazione, pa, forma)` (~12.600 righe)
  - `confezioni(aic PK, cod_farmaco, descrizione)` (~159.700 righe)
  - `meta(chiave, valore)` — versione/data generazione.
- **`tools/genera_catalogo_aifa.py`** — scarica il CSV, genera il .db.gz. Rilanciarlo
  per aggiornare il catalogo.
- **`lib/services/aifa_catalog_service.dart`** — singleton; alla prima richiesta
  decomprime l'asset nella dir documenti (in `Isolate.run`, ri-estrae se la lunghezza
  dell'asset cambia) e apre il DB read-only. `lookupAic(String) → AicMedicine?`
  (denominazione, descrizione, pa, forma + dosaggio estratto dalla descrizione).
- **`lib/utils/aic_utils.dart`** — funzioni pure testabili: estrazione candidati
  9 cifre da testo OCR, decodifica Code 32, estrazione finestre 9 cifre dai barcode.
- **ConfirmSheet** — `onChanged` del campo nome: se `^\d{9}$` → lookup → compila.
- **ScanScreen** — nel loop frame: candidati AIC dalle righe OCR + barcode scanner
  ML Kit (`google_mlkit_barcode_scanning`, formati Code 39 + Data Matrix + EAN13)
  sugli stessi frame; hit AIC → match al 100%.

## Gestione errori

- AIC non trovato nel catalogo → si ignora (il lookup È la validazione; niente
  falsi positivi da numeri di lotto).
- Decompressione fallita → il resto dell'app funziona come oggi (solo matching nome).

## Test

- Unit test su `aic_utils` (roundtrip Code 32, estrazione da righe OCR, finestre GTIN).
- Test manuale on-device con scatole reali (APK in Telegram).
