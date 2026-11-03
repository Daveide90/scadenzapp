# Qualità fotocamera schermata scansione — design

Data: 2026-07-09 · Stato: approvato dall'utente

## Problemi segnalati (betatest v1.1.1)

1. La preview si **stira** quando il ConfirmSheet si espande (Stack con
   `StackFit.expand` deforma la CameraPreview).
2. **Messa a fuoco** scarsa: nessun tap-to-focus, autofocus lasciato al default.
3. Telefoni diversi = fotocamere diverse: l'utente vuole **scegliere la lente**
   (alcuni telefoni hanno la macro).
4. Riconoscimento più veloce ma telefono caldo: servono **max precisione e
   velocità a bassi consumi** (ricerca online richiesta).

## Decisioni (con fonti)

### 1. Preview mai deformata (scelta utente: adattivo, non riquadro fisso)
La preview è renderizzata in un `ClipRect` + `FittedBox(BoxFit.cover)` con
`SizedBox` alle dimensioni native del sensore (swap w/h in portrait): quando lo
spazio si riduce l'inquadratura si ritaglia al centro ma **non cambia mai
proporzioni**.

### 2. Fuoco
- Autofocus continuo esplicito dopo l'init (`setFocusMode(FocusMode.auto)`).
- **Tap-to-focus**: tocco sul riquadro → `setFocusPoint`+`setExposurePoint`
  con mirino animato. La geometria tap→punto normalizzato (tenendo conto del
  ritaglio cover) è in una funzione pura testata (`preview_geometry.dart`).
- La **pausa** (prima sul tap) passa a un pulsante dedicato sovrapposto alla
  preview.

### 3. Scelta fotocamera + zoom
- Selettore lenti (bottom sheet) con le fotocamere posteriori esposte dal
  telefono; scelta persistita in `SettingsService`. NB: molti OEM espongono
  una sola camera "logica" (limite piattaforma: flutter#91247, #173406) —
  in quel caso il selettore non compare.
- **Zoom pinch + slider** (min→max dal controller): su telefoni senza macro
  esposta lo zoom è il modo pratico di ingrandire testi piccoli (ML Kit:
  "il testo deve riempire il riquadro").

### 4. Consumi (ricerca online)
- Upgrade `camera` 0.10 → **0.11 (CameraX default)**:
  - ~~`MediaSettings.fps: 15`~~ **RIMOSSO dopo betatest**: CameraX applica
    l'fps come gamma fissa (15-15) e AF/AE convergono alla velocità dei
    frame → fuoco lento e immagine scura in poca luce (stesso motivo per cui
    camera_android non lo applica fuori dalla registrazione). Il risparmio
    resta affidato al throttling OCR con pausa garantita + barcode alternato
    + stop stream in pausa.
  - Backpressure `KEEP_ONLY_LATEST` di CameraX = i frame in eccesso vengono
    scartati, non accodati (raccomandazione ML Kit).
  - NV21: da camerax 0.6.23 i bytes dello stream sono NV21 anche se il
    formato riportato è yuv420 → in `_buildInputImage` su Android il formato
    ML Kit è forzato a `nv21`.
- Risoluzione **`ResolutionPreset.high` = 720p su CameraX** (ML Kit consiglia
  ~720p per il testo; il vecchio `medium` su Camera2 era 720×480).
- Restano: throttling OCR 1,5 s/3 s, barcode un ciclo su due, pausa che ferma
  lo stream, warmup catalogo post-avvio camera (fix v1.1.1).

## Fuori scope
- Lenti fisiche non esposte dall'OEM (impossibile da plugin).
- Torcia/flash (eventuale richiesta futura).

## Test
- Unit: geometria tap→punto fuoco con crop cover (casi: box più largo/stretto
  del preview, tap ai bordi).
- On-device (utente): niente stretch, fuoco al tocco, selettore/zoom, calore.
