import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../database/database_helper.dart';
import '../models/medicine.dart';
import '../providers/medicine_provider.dart';
import '../services/aifa_catalog_service.dart';
import '../services/settings_service.dart';
import '../utils/aic_utils.dart';
import '../utils/date_parser.dart';
import '../utils/gs1_utils.dart';
import '../utils/lot_parser.dart';
import '../utils/medicine_matcher.dart';
import '../utils/nv21_crop.dart';
import '../utils/preview_geometry.dart';
import '../widgets/confirm_sheet.dart';
import '../widgets/scan_overlay.dart';
import '../theme/app_theme.dart';

class ScanScreen extends StatefulWidget {
  final int cabinetId;

  const ScanScreen({super.key, required this.cabinetId});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _cameraController;
  final _textRecognizer = TextRecognizer();
  // Bollino farmaceutico (Code 32, letto come Code 39) + Data Matrix/EAN
  final _barcodeScanner = BarcodeScanner(formats: [
    BarcodeFormat.code39,
    BarcodeFormat.dataMatrix,
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.code128,
  ]);
  final _catalog = AifaCatalogService();
  bool _isProcessing = false;
  bool _cameraReady = false;
  String? _cameraError;
  bool _frozen = false; // frame congelato
  DateTime? _cameraStartTime;
  DateTime _lastProcessTime = DateTime(2000);

  // Fotocamere disponibili (posteriori/esterne) e zoom
  List<CameraDescription> _cameras = [];
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _zoomAtScaleStart = 1.0;

  // Tap-to-focus: posizione del mirino su schermo e geometria del riquadro
  Offset? _focusPoint;
  Timer? _focusTimer;
  Size? _previewBox;
  Size? _previewDisplaySize;

  String? _detectedName;
  String? _detectedDosage;
  String? _detectedForm;
  DateTime? _detectedDate;
  List<String> _ocrBlocks = [];
  List<MatchResult> _nameSuggestions = [];
  List<DateCandidate> _dateSuggestions = [];
  MatchResult? _bestMatch;

  // Auto-correzione nome
  String? _correctionCandidate;
  int _correctionCount = 0;
  bool _nameManuallyEdited = false;

  // Auto-correzione data
  DateTime? _dateCorrectionCandidate;
  int _dateCorrectionCount = 0;

  // Accumula righe OCR da frame diversi
  final Set<String> _allOcrLines = {};

  // Ricerca per AIC: codice già applicato al foglio + codici cercati senza hit
  String? _appliedAic;
  final Set<String> _aicMisses = {};

  // Dati letti dal Data Matrix GS1 (scadenza e lotto stampati sulla confezione).
  String? _detectedLot;
  bool _dateFromBarcode = false;
  bool _lotManuallyEdited = false;

  // Farmaci custom dall'utente
  List<Map<String, dynamic>> _customMedicines = [];

  final _sheetKey = GlobalKey<ConfirmSheetState>();

  @override
  void initState() {
    super.initState();
    _loadCustomMedicines();
    _initCamera();
  }

  Future<void> _loadCustomMedicines() async {
    _customMedicines = await DatabaseHelper().getCustomMedicines();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permesso fotocamera negato')),
        );
        Navigator.pop(context);
      }
      return;
    }

    try {
      final all = await availableCameras();
      if (all.isEmpty) {
        if (mounted) {
          setState(() => _cameraError = 'Nessuna fotocamera disponibile');
        }
        return;
      }

      // Per la scansione servono le lenti posteriori/esterne. Se il telefono
      // ne espone più di una (dipende dall'OEM) l'utente può scegliere.
      _cameras = all
          .where((c) => c.lensDirection != CameraLensDirection.front)
          .toList();
      if (_cameras.isEmpty) _cameras = all;

      final saved = await SettingsService().getScanCameraName();
      final desc = _cameras.firstWhere(
        (c) => c.name == saved,
        orElse: () => _cameras.first,
      );
      await _startCamera(desc);
    } catch (_) {
      // Camera occupata da altra app, errore hardware, ecc.: niente spinner infinito.
      if (mounted) {
        setState(() => _cameraError = 'Impossibile avviare la fotocamera');
      }
    }
  }

  Future<void> _startCamera(CameraDescription desc) async {
    try {
      final controller = CameraController(
        desc,
        // Su CameraX high = 720p: la risoluzione consigliata da ML Kit per il
        // testo (il vecchio medium su Camera2 era 720x480).
        ResolutionPreset.high,
        enableAudio: false,
        // NIENTE limite fps: CameraX lo applica come gamma fissa (es. 15-15)
        // e autofocus/esposizione convergono alla velocità dei frame → fuoco
        // lento e immagine scura in poca luce. Il calore è già contenuto da
        // throttling OCR con pausa garantita, barcode alternato e stop dello
        // stream in pausa.
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      _cameraController = controller;

      await controller.initialize();
      // Autofocus continuo esplicito; non tutte le camere lo supportano.
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
      _minZoom = 1.0;
      _maxZoom = 1.0;
      try {
        _minZoom = await controller.getMinZoomLevel();
        _maxZoom = await controller.getMaxZoomLevel();
      } catch (_) {}
      _zoom = _zoom.clamp(_minZoom, _maxZoom);
      if (_zoom != 1.0) {
        try {
          await controller.setZoomLevel(_zoom);
        } catch (_) {}
      }
      if (!mounted) return;

      _cameraStartTime = DateTime.now();
      setState(() {
        _cameraReady = true;
        _cameraError = null;
      });
      await controller.startImageStream(_processImage);
      // Il warmup del catalogo (estrazione ~20 MB al primo avvio) parte solo
      // a fotocamera avviata: farlo prima contende la CPU all'inizializzazione
      // della camera e causa blocchi all'apertura della schermata.
      _catalog.warmUp();
    } catch (_) {
      if (mounted) {
        setState(() => _cameraError = 'Impossibile avviare la fotocamera');
      }
    }
  }

  /// Passa a un'altra fotocamera (scelta ricordata per le prossime scansioni).
  Future<void> _switchCamera(CameraDescription desc) async {
    if (desc.name == _cameraController?.description.name) return;
    setState(() {
      _cameraReady = false;
      _frozen = false;
    });
    final old = _cameraController;
    _cameraController = null;
    if (old != null) {
      if (old.value.isStreamingImages) {
        try {
          await old.stopImageStream();
        } catch (_) {}
      }
      await old.dispose();
    }
    await SettingsService().setScanCameraName(desc.name);
    await _startCamera(desc);
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing || _frozen || _cameraController == null) return;

    final now = DateTime.now();

    // Warmup breve: giusto il tempo che l'autofocus si assesti.
    if (_cameraStartTime != null &&
        now.difference(_cameraStartTime!).inMilliseconds < 800) return;

    // Rate limit: 1.1s in ricerca, 3s quando entrambi già impostati
    // (auto-correzione). Il ciclo costa meno grazie al ritaglio dell'area
    // visibile, quindi la cadenza più fitta non aumenta la CPU totale.
    final rateLimit = (_detectedName != null && _detectedDate != null) ? 3000 : 1100;
    if (now.difference(_lastProcessTime).inMilliseconds < rateLimit) return;

    _isProcessing = true;

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final recognizedText = await _textRecognizer.processImage(inputImage);
      if (!mounted) return;

      // Barcode (bollino/Data Matrix) → AIC dal catalogo AIFA, e dal Data
      // Matrix anche scadenza e lotto. Gira su ogni ciclo: sul frame
      // ritagliato costa poco rispetto all'OCR e smette da solo quando non
      // c'è più niente da leggere.
      final scan = await _scanBarcodes(inputImage);
      if (!mounted) return;
      if (scan.gs1 != null) _applyGs1(scan.gs1!);
      if (scan.med != null) _applyAicHit(scan.med!);

      await _processRecognizedText(recognizedText);
    } catch (_) {
      // Ignore processing errors
    } finally {
      _isProcessing = false;
      // Misurato a FINE elaborazione: garantisce una pausa vera tra un ciclo
      // e l'altro anche quando OCR+barcode impiegano più del rate limit
      // (altrimenti su device lenti si elabora in continuo e il telefono scalda).
      _lastProcessTime = DateTime.now();
    }
  }

  Future<void> _processRecognizedText(RecognizedText recognizedText) async {
    final fullText = recognizedText.text;
    if (fullText.isEmpty) return;

    // Estrai righe da ogni blocco ML Kit (più strutturato del semplice split)
    final lines = <String>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isNotEmpty) lines.add(text);
      }
    }
    if (lines.isEmpty) return;

    bool changed = false;

    // Accumula righe OCR per analisi multi-frame (cap a 200, FIFO)
    _allOcrLines.addAll(lines);
    while (_allOcrLines.length > 200) {
      _allOcrLines.remove(_allOcrLines.first);
    }

    // 1. Cerca date candidate (saltata se la scadenza arriva dal Data Matrix:
    // quella stampata nel bollino è certa, l'OCR non deve correggerla)
    if (!_dateFromBarcode) {
      // Prova con le righe di questo frame
      var dateCandidates = findExpiryDateCandidates(lines);

      // Se pochi risultati, prova con il testo accumulato
      if (dateCandidates.length < 2 && _allOcrLines.length > lines.length) {
        final accumulated = findExpiryDateCandidates(_allOcrLines.toList());
        // Unisci e deduplica
        final seen = <String>{};
        final merged = <DateCandidate>[];
        for (final c in [...accumulated, ...dateCandidates]) {
          final key = '${c.date.year}-${c.date.month}';
          if (seen.add(key)) merged.add(c);
        }
        merged.sort((a, b) => b.score.compareTo(a.score));
        dateCandidates = merged;
      }

      if (dateCandidates.isNotEmpty) {
        final best = dateCandidates.first;
        final secondScore = dateCandidates.length > 1 ? dateCandidates[1].score : 0;
        final clearWinner = dateCandidates.length == 1 || best.score >= secondScore + 20;

        if (_detectedDate == null) {
          // Prima rilevazione
          if (clearWinner) {
            _detectedDate = best.date;
            _dateSuggestions.clear();
            HapticFeedback.mediumImpact();
            _sheetKey.currentState?.updateDate(_detectedDate!);
            changed = true;
          } else {
            _dateSuggestions = dateCandidates.take(4).toList();
            changed = true;
          }
        } else if (best.score >= 60) {
          // Auto-correzione: data già impostata, verifica se frame successivi suggeriscono diversa
          final sameMonth = best.date.year == _detectedDate!.year &&
              best.date.month == _detectedDate!.month;
          if (!sameMonth) {
            final sameCorrCandidate = _dateCorrectionCandidate != null &&
                best.date.year == _dateCorrectionCandidate!.year &&
                best.date.month == _dateCorrectionCandidate!.month;
            if (sameCorrCandidate) {
              _dateCorrectionCount++;
              if (_dateCorrectionCount >= 3) {
                _detectedDate = best.date;
                _sheetKey.currentState?.updateDate(best.date);
                _dateCorrectionCandidate = null;
                _dateCorrectionCount = 0;
                HapticFeedback.mediumImpact();
                changed = true;
              }
            } else {
              _dateCorrectionCandidate = best.date;
              _dateCorrectionCount = 1;
            }
          } else {
            // Stesso risultato corrente → resetta correzione
            _dateCorrectionCandidate = null;
            _dateCorrectionCount = 0;
          }
        }
      }
    }

    // 1b. Cerca codici AIC nelle righe OCR (il lookup nel catalogo è la
    // validazione: un numero di lotto non darà mai un hit)
    if (_appliedAic == null && !_nameManuallyEdited) {
      for (final cand in extractAicCandidates(lines)) {
        if (_aicMisses.contains(cand)) continue;
        final med = await _catalog.lookupAic(cand);
        if (!mounted) return;
        if (med == null) {
          _aicMisses.add(cand);
          continue;
        }
        _applyAicHit(med);
        break;
      }
    }

    // 1c. Lotto stampato sulla scatola: serve alle confezioni senza Data
    // Matrix. Quello letto dal bollino, se c'è, resta buono e non si tocca.
    if (_detectedLot == null && !_lotManuallyEdited) {
      final lot = findLot(_allOcrLines.toList());
      if (lot != null) {
        _detectedLot = lot;
        _sheetKey.currentState?.updateLot(lot);
        changed = true;
      }
    }

    // 2. Cerca farmaco nel database (in Isolate per non bloccare UI)
    // L'AIC identifica la confezione esatta: se applicato, niente matching nome.
    if (_appliedAic == null &&
        (_detectedName == null || (_detectedName != null && !_nameManuallyEdited))) {
      final matches = await findMedicineMatchesAsync(lines,
          maxResults: 5, minScore: 0.55, customMedicines: _customMedicines);
      if (!mounted) return;

      if (matches.isNotEmpty) {
        final best = matches.first;
        _detectedDosage ??= extractDosage(fullText);

        if ((best.score * 100).round() >= 100) {
          if (_detectedName == null) {
            // Prima rilevazione
            _detectedForm = extractForm(fullText);
            _detectedName = best.nameForField();
            _bestMatch = best;
            _nameSuggestions.clear();
            HapticFeedback.mediumImpact();
            _sheetKey.currentState?.updateName(_detectedName!);
            _sheetKey.currentState?.updateDetails(
              form: _detectedForm,
              dosage: _detectedDosage,
            );
            changed = true;
          } else if (best.dbName != _bestMatch?.dbName) {
            // Auto-correzione: 100% match diverso dal corrente
            if (_correctionCandidate == best.dbName) {
              _correctionCount++;
              if (_correctionCount >= 3) {
                _detectedForm = extractForm(fullText);
                _detectedName = best.nameForField();
                _bestMatch = best;
                _sheetKey.currentState?.forceUpdateName(_detectedName!);
                _sheetKey.currentState?.updateDetails(
                  form: _detectedForm,
                  dosage: _detectedDosage,
                );
                _correctionCandidate = null;
                _correctionCount = 0;
                HapticFeedback.mediumImpact();
                changed = true;
              }
            } else {
              _correctionCandidate = best.dbName;
              _correctionCount = 1;
            }
          } else {
            // Stesso match corrente → resetta correzione
            _correctionCandidate = null;
            _correctionCount = 0;
          }
        } else if (_detectedName == null) {
          final betterScore = _nameSuggestions.isEmpty ||
              best.score > _nameSuggestions.first.score;
          if (betterScore) {
            _nameSuggestions = matches;
            changed = true;
          }
        }
      }

      // Aggiorna blocchi testo OCR
      if (lines.isNotEmpty && _ocrBlocks.length < lines.length) {
        _ocrBlocks = lines;
        changed = true;
      }
    }

    if (changed && mounted) setState(() {});
  }

  /// Legge i barcode del frame e ne ricava due cose:
  /// - la confezione, via AIC (bollino Code 32, oppure finestre di 9 cifre
  ///   in Data Matrix/EAN, oppure il GTIN italiano del Data Matrix);
  /// - i dati stampati nel Data Matrix GS1: scadenza (AI 17) e lotto (AI 10).
  Future<({AicMedicine? med, Gs1Data? gs1})> _scanBarcodes(
      InputImage image) async {
    final wantsAic = _appliedAic == null && !_nameManuallyEdited;
    final wantsGs1 = !_dateFromBarcode || _detectedLot == null;
    if (!wantsAic && !wantsGs1) return (med: null, gs1: null);

    AicMedicine? med;
    Gs1Data? gs1;
    try {
      final barcodes = await _barcodeScanner.processImage(image);
      for (final b in barcodes) {
        final raw = b.rawValue ?? b.displayValue;
        if (raw == null || raw.isEmpty) continue;

        // Data Matrix serializzato: scadenza e lotto senza digitare nulla.
        gs1 ??= parseGs1(raw);

        if (!wantsAic || med != null) continue;

        // Il bollino italiano contiene il numero della singola scatola, non
        // l'AIC: cercarci dentro un codice di 9 cifre porterebbe a
        // identificare un farmaco sbagliato.
        if (isItalianBollino(raw)) continue;

        final candidates = <String>[];
        if (b.format == BarcodeFormat.code39) {
          final aic = decodeCode32(raw);
          if (aic != null) candidates.add(aic);
        }
        // Il GTIN del Data Matrix contiene l'AIC: candidato più affidabile
        // delle finestre di 9 cifre, quindi va provato per primo.
        final gtin = gs1?.gtin;
        if (gtin != null) {
          final fromGtin = aicFromGtin(gtin);
          if (fromGtin != null) candidates.add(fromGtin);
        }
        candidates.addAll(extractAicWindows(raw));

        for (final c in candidates) {
          if (_aicMisses.contains(c)) continue;
          final found = await _catalog.lookupAic(c);
          if (found != null) {
            med = found;
            break;
          }
          _aicMisses.add(c);
        }
      }
    } catch (_) {
      // Errori del barcode scanner: si riprova al frame successivo
    }
    return (med: med, gs1: gs1);
  }

  /// Applica scadenza e lotto letti dal Data Matrix.
  ///
  /// Il bollino è più attendibile dell'OCR, quindi la sua data vince e da quel
  /// momento l'OCR non tocca più il campo. Restano comunque modificabili a
  /// mano: molte confezioni il Data Matrix non ce l'hanno affatto.
  void _applyGs1(Gs1Data gs1) {
    final parts = <String>[];

    if (gs1.expiry != null && !_dateFromBarcode) {
      _detectedDate = gs1.expiry;
      _dateFromBarcode = true;
      _dateSuggestions = [];
      _dateCorrectionCandidate = null;
      _dateCorrectionCount = 0;
      _sheetKey.currentState?.updateDate(gs1.expiry!);
      parts.add('scadenza ${DateFormat('MM/yyyy').format(gs1.expiry!)}');
    }

    if (gs1.lot != null && _detectedLot == null && !_lotManuallyEdited) {
      _detectedLot = gs1.lot;
      _sheetKey.currentState?.updateLot(gs1.lot!);
      parts.add('lotto ${gs1.lot}');
    }

    if (parts.isEmpty || !mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Dal bollino: ${parts.join(' · ')}'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() {});
  }

  /// Applica al foglio una confezione identificata per AIC (match certo:
  /// l'AIC identifica nome, dosaggio e formato esatti).
  void _applyAicHit(AicMedicine med) {
    if (!mounted || _appliedAic == med.aic || _nameManuallyEdited) return;
    _appliedAic = med.aic;
    _detectedDosage = med.dosage ?? _detectedDosage;
    _detectedForm = med.appForm ?? _detectedForm;
    _detectedName = med.displayName;
    _bestMatch = MatchResult(
      dbName: med.denominazione.toUpperCase(),
      activeIngredient: med.pa,
      score: 1.0,
      candidate: med.aic,
    );
    _nameSuggestions.clear();
    HapticFeedback.mediumImpact();
    _sheetKey.currentState?.forceUpdateName(_detectedName!);
    // L'unità di misura non viene mai auto-compilata: la mette l'utente.
    _sheetKey.currentState?.updateDetails(
      form: _detectedForm,
      dosage: _detectedDosage,
    );
    // Il bollino a barre (Code 32) contiene SOLO l'AIC: scadenza e lotto
    // stanno nel quadratino Data Matrix, che non tutte le confezioni hanno.
    // Senza questa riga sembra che l'app "non legga" la scadenza.
    final mancaScadenza = !_dateFromBarcode && _detectedDate == null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mancaScadenza
              ? 'AIC ${med.aic}: ${med.displayName}\n'
                  'Per la scadenza inquadra il quadratino (Data Matrix) '
                  'o scrivila a mano.'
              : 'AIC ${med.aic}: ${med.displayName}',
        ),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: mancaScadenza ? 4 : 2),
      ),
    );
    setState(() {});
  }

  // Mappa DeviceOrientation → gradi, per il calcolo rotazione ML Kit.
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _buildInputImage(CameraImage image) {
    final controller = _cameraController;
    if (controller == null) return null;
    final camera = controller.description;

    // Rotazione compensata con l'orientamento del device (formula documentata
    // da google_mlkit_commons: necessaria con CameraX).
    InputImageRotation? rotation;
    if (Platform.isAndroid) {
      var compensation = _orientations[controller.value.deviceOrientation];
      if (compensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        compensation = (camera.sensorOrientation + compensation) % 360;
      } else {
        compensation = (camera.sensorOrientation - compensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(compensation);
    } else {
      rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    }
    if (rotation == null) return null;

    // CameraX consegna bytes NV21 ma riporta il raw format yuv420:
    // per ML Kit su Android il formato va forzato a nv21.
    final format = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    var bytes = image.planes.first.bytes;
    var width = image.width;
    var height = image.height;
    var bytesPerRow = image.planes.first.bytesPerRow;

    // Ritaglio all'area VISIBILE: i pixel nascosti dal cover-crop non si
    // vedono nemmeno — meno pixel = OCR/barcode più veloci a parità di CPU.
    // Solo su buffer NV21 compatti (stride == width), altrimenti frame pieno.
    final box = _previewBox;
    final disp = _previewDisplaySize;
    if (Platform.isAndroid &&
        box != null &&
        disp != null &&
        bytesPerRow == width &&
        bytes.length >= width * height * 3 ~/ 2) {
      final f = visibleFractions(box: box, preview: disp);
      final crop = computeVisibleCrop(
        sensorWidth: width,
        sensorHeight: height,
        fx: f.fx,
        fy: f.fy,
        portrait: disp.width < disp.height,
      );
      if (crop != null) {
        bytes = cropNv21(
            bytes, width, height, crop.left, crop.top, crop.width, crop.height);
        width = crop.width;
        height = crop.height;
        bytesPerRow = crop.width;
      }
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  // ─── Azioni utente ──────────────────────────────────────────

  /// Tap sul riquadro = punto di fuoco/esposizione (con mirino animato).
  Future<void> _focusAt(Offset pos) async {
    final cam = _cameraController;
    final box = _previewBox;
    final preview = _previewDisplaySize;
    if (cam == null || !cam.value.isInitialized || box == null || preview == null) {
      return;
    }
    final point = mapTapToPreviewPoint(tap: pos, box: box, preview: preview);
    if (point == null) return;

    setState(() => _focusPoint = pos);
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _focusPoint = null);
    });

    try {
      await cam.setFocusPoint(point);
      await cam.setExposurePoint(point);
    } catch (_) {
      // Non tutte le fotocamere supportano il punto di fuoco/esposizione.
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _zoomAtScaleStart = _zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount < 2) return; // solo pinch a due dita
    _setZoom(_zoomAtScaleStart * d.scale);
  }

  void _setZoom(double z) {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return;
    final clamped = z.clamp(_minZoom, _maxZoom);
    if ((clamped - _zoom).abs() < 0.01) return;
    _zoom = clamped;
    cam.setZoomLevel(clamped).catchError((_) {});
    if (mounted) setState(() {});
  }

  /// Selettore fotocamera (visibile solo se il telefono espone più lenti).
  void _showCameraPicker() {
    final currentName = _cameraController?.description.name;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Fotocamera',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            for (var i = 0; i < _cameras.length; i++)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(
                  'Fotocamera ${i + 1}'
                  '${_cameras[i].lensDirection == CameraLensDirection.external ? ' (esterna)' : ''}',
                ),
                subtitle: Text('ID ${_cameras[i].name}'),
                trailing: _cameras[i].name == currentName
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _switchCamera(_cameras[i]);
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Se la macro non compare, il telefono non la espone alle app: '
                'usa lo zoom per i testi piccoli.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleFreeze() {
    setState(() {
      _frozen = !_frozen;
      if (!_frozen) {
        _lastProcessTime = DateTime(2000); // riprendi subito
      }
    });
    // In pausa lo stream viene fermato del tutto: la preview resta attiva ma
    // i frame non vengono più copiati/elaborati (meno CPU, meno calore).
    _setStreamRunning(!_frozen);
    HapticFeedback.lightImpact();
  }

  void _setStreamRunning(bool running) {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return;
    if (running && !cam.value.isStreamingImages) {
      cam.startImageStream(_processImage).catchError((_) {});
    } else if (!running && cam.value.isStreamingImages) {
      cam.stopImageStream().catchError((_) {});
    }
  }

  void _resetScan() {
    setState(() {
      _detectedName = null;
      _detectedDosage = null;
      _detectedForm = null;
      _detectedDate = null;
      _ocrBlocks.clear();
      _nameSuggestions.clear();
      _dateSuggestions.clear();
      _bestMatch = null;
      _allOcrLines.clear();
      _correctionCandidate = null;
      _correctionCount = 0;
      _nameManuallyEdited = false;
      _dateCorrectionCandidate = null;
      _dateCorrectionCount = 0;
      _appliedAic = null;
      _detectedLot = null;
      _dateFromBarcode = false;
      _lotManuallyEdited = false;
      _frozen = false;
      _lastProcessTime = DateTime(2000);
      _cameraStartTime = DateTime.now();
    });
    _aicMisses.clear();
    _setStreamRunning(true); // se si era in pausa lo stream era fermo
    _sheetKey.currentState?.reset();
    HapticFeedback.lightImpact();
  }

  void _selectNameSuggestion(MatchResult match) {
    final ocrText = _ocrBlocks.join(' ');
    _detectedDosage ??= extractDosage(ocrText);
    _detectedForm = extractForm(ocrText);
    _detectedName = match.nameForField();
    _bestMatch = match;
    _nameSuggestions.clear();
    _nameManuallyEdited = true;
    _sheetKey.currentState?.updateName(_detectedName!);
    _sheetKey.currentState?.updateDetails(
      form: _detectedForm,
      dosage: _detectedDosage,
    );
    setState(() {});
  }

  void _selectDateSuggestion(DateCandidate candidate) {
    _detectedDate = candidate.date;
    _dateSuggestions.clear();
    HapticFeedback.mediumImpact();
    // Suggerimento toccato: è una scelta dell'utente, l'OCR non la cambia più.
    _sheetKey.currentState?.setDateByUser(candidate.date);
    setState(() {});
  }

  void _onSave(String name, DateTime date, int quantity,
      {String? form, String? dosage, String? unit, String? lot}) async {
    final provider = context.read<MedicineProvider>();
    final medicine = Medicine(
      cabinetId: widget.cabinetId,
      name: name,
      expirationDate: date,
      quantity: quantity,
      form: form,
      dosage: dosage,
      unit: unit,
      lot: lot,
    );

    await provider.addMedicine(medicine);

    // Salva come farmaco custom se non era nel database AIFA
    if (_bestMatch == null && name.isNotEmpty) {
      // Pulisci il nome: togli dosaggio e forma che vanno nei campi separati
      var cleanName = name;
      if (dosage != null) cleanName = cleanName.replaceAll(dosage, '').trim();
      if (form != null) cleanName = cleanName.replaceAll(form, '').trim();
      // Togli anche eventuali parentesi vuote rimaste
      cleanName = cleanName.replaceAll(RegExp(r'\(\s*\)'), '').trim();
      // Togli spazi multipli
      cleanName = cleanName.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (cleanName.isNotEmpty) {
        final db = DatabaseHelper();
        await db.insertCustomMedicine({
          'name': cleanName.toUpperCase(),
          'active_ingredient': null,
          'form': form,
          'dosage': dosage,
          'unit': unit,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name salvato'),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    }
  }

  void _showTextPicker() {
    if (_ocrBlocks.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.8,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Testo riconosciuto',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _ocrBlocks.length,
                itemBuilder: (ctx, i) => ListTile(
                  title: Text(_ocrBlocks[i]),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Scelta esplicita: sostituisce anche un nome già letto
                    // (updateName scriverebbe solo nel campo vuoto).
                    _sheetKey.currentState?.forceUpdateName(_ocrBlocks[i]);
                    setState(() {
                      _detectedName = _ocrBlocks[i];
                      _nameSuggestions.clear();
                      _nameManuallyEdited = true;
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _frozen = true; // blocca l'elaborazione di nuovi frame durante il teardown
    _focusTimer?.cancel();
    final cam = _cameraController;
    if (cam != null && cam.value.isStreamingImages) {
      // Ferma lo stream prima del dispose: evita che un frame in volo colpisca
      // il recognizer appena chiuso.
      cam.stopImageStream().catchError((_) {});
    }
    cam?.dispose();
    _textRecognizer.close();
    _barcodeScanner.close();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────

  /// Preview in cover-crop: riempie lo spazio disponibile ritagliando al
  /// centro, così quando il foglio sotto si espande l'inquadratura si
  /// accorcia ma NON si deforma mai.
  Widget _buildCoverPreview() {
    final cam = _cameraController!;
    final ps = cam.value.previewSize;
    if (ps == null) return CameraPreview(cam);
    // Il sensore è landscape: in portrait le dimensioni vanno scambiate.
    final portrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final w = portrait ? ps.height : ps.width;
    final h = portrait ? ps.width : ps.height;
    _previewDisplaySize = Size(w, h);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: w, height: h, child: CameraPreview(cam)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _detectedName != null || _detectedDate != null;
    final hasSuggestions = _nameSuggestions.isNotEmpty || _dateSuggestions.isNotEmpty;
    final df = DateFormat('MM/yyyy');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scansiona farmaco'),
        backgroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Chiudi la scansione',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(_frozen ? Icons.play_arrow : Icons.pause),
            tooltip: _frozen ? 'Riprendi scansione' : 'Pausa scansione',
            onPressed: _cameraReady ? _toggleFreeze : null,
          ),
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch_outlined),
              tooltip: 'Cambia fotocamera',
              onPressed: _cameraReady ? _showCameraPicker : null,
            ),
          if (_bestMatch != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                label: Text(
                  '${(_bestMatch!.score * 100).round()}%',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                backgroundColor: _bestMatch!.score >= 0.8
                    ? Colors.green
                    : Colors.orange,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (_detectedName != null)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.medication, color: Colors.greenAccent, size: 20),
            ),
          if (_detectedDate != null)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.event_available, color: Colors.greenAccent, size: 20),
            ),
          if (hasData || hasSuggestions)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Ricomincia scansione',
              onPressed: _resetScan,
            ),
          if (_ocrBlocks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.list_alt),
              tooltip: 'Testo riconosciuto',
              onPressed: _showTextPicker,
            ),
        ],
      ),
      body: Column(
        children: [
          // Camera preview
          Expanded(
            child: _cameraReady && _cameraController != null
                ? LayoutBuilder(builder: (context, constraints) {
                    _previewBox =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    final hasZoom = _maxZoom - _minZoom > 0.01;
                    return GestureDetector(
                      onTapDown: (d) => _focusAt(d.localPosition),
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildCoverPreview(),
                        const ScanOverlay(),
                        // Mirino tap-to-focus
                        if (_focusPoint != null)
                          Positioned(
                            left: _focusPoint!.dx - 24,
                            top: _focusPoint!.dy - 24,
                            child: IgnorePointer(
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.yellowAccent, width: 2),
                                ),
                              ),
                            ),
                          ),
                        // Slider zoom in basso
                        if (hasZoom)
                          Positioned(
                            bottom: 4,
                            left: 12,
                            right: 12,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.zoom_in,
                                      color: Colors.white70, size: 18),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 2,
                                        thumbShape: const RoundSliderThumbShape(
                                            enabledThumbRadius: 8),
                                      ),
                                      child: Slider(
                                        value: _zoom.clamp(_minZoom, _maxZoom),
                                        min: _minZoom,
                                        max: _maxZoom,
                                        onChanged: _setZoom,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${_zoom.toStringAsFixed(1)}x',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Hint in alto
                        Positioned(
                          top: 16,
                          left: 0,
                          right: 0,
                          child: Text(
                            _frozen
                                ? 'In pausa - premi ▶ in alto per riprendere'
                                : hasData
                                    ? 'Dati rilevati - compila e salva'
                                    : 'Inquadra e attendi la scansione\nTocca per mettere a fuoco · Pizzica per lo zoom',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 14,
                              shadows: const [Shadow(blurRadius: 4)],
                            ),
                          ),
                        ),
                        // Icona pausa quando congelato
                        if (_frozen)
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.pause,
                                color: Colors.white70,
                                size: 40,
                              ),
                            ),
                          ),
                        // Suggerimenti date
                        if (_dateSuggestions.isNotEmpty && _detectedDate == null)
                          Positioned(
                            top: 50,
                            left: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Scadenza trovata:',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: _dateSuggestions.map((d) {
                                      return ActionChip(
                                        label: Text(
                                          df.format(d.date),
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        avatar: Icon(
                                          Icons.event,
                                          size: 16,
                                          color: d.score >= 60 ? Colors.green : Colors.orange,
                                        ),
                                        onPressed: () => _selectDateSuggestion(d),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Suggerimenti nome farmaco
                        if (_nameSuggestions.isNotEmpty && _detectedName == null)
                          Positioned(
                            bottom: hasZoom ? 48 : 8,
                            left: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Potrebbe essere:',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: _nameSuggestions.map((s) {
                                      return ActionChip(
                                        label: Text(
                                          s.chipLabel,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        avatar: Text(
                                          '${(s.score * 100).round()}%',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                        onPressed: () => _selectNameSuggestion(s),
                                        visualDensity: VisualDensity.compact,
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                      ),
                    );
                  })
                : Center(
                    child: _cameraError != null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.videocam_off,
                                    color: Colors.white54, size: 56),
                                const SizedBox(height: 16),
                                Text(
                                  _cameraError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Puoi comunque inserire il farmaco a mano qui sotto.',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(color: Colors.white38, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : const CircularProgressIndicator(color: Colors.white),
                  ),
          ),
          // Confirm sheet
          ConfirmSheet(
            key: _sheetKey,
            initialName: _detectedName,
            initialDate: _detectedDate,
            initialLot: _detectedLot,
            onSave: _onSave,
            onNameEdited: () => _nameManuallyEdited = true,
            onLotEdited: () => _lotManuallyEdited = true,
          ),
        ],
      ),
    );
  }
}
