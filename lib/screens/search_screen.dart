import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import '../models/cabinet.dart';
import '../models/medicine_search_hit.dart';
import '../utils/expiry_utils.dart';
import 'cabinet_screen.dart';

export '../models/medicine_search_hit.dart';

/// Ricerca per nome o lotto in tutti gli armadietti. Il caso tipico è il
/// ritiro di un lotto: si scrive il lotto e si vede subito dove sta.
class SearchScreen extends StatefulWidget {
  /// Iniettabile per i test; di serie cerca nel database.
  final Future<List<MedicineSearchHit>> Function(String query)? search;

  const SearchScreen({super.key, this.search});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<MedicineSearchHit> _hits = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(text));
  }

  Future<void> _run(String text) async {
    final q = text.trim();
    setState(() {
      _query = q;
      _searching = q.length >= 2;
    });
    if (q.length < 2) {
      setState(() => _hits = const []);
      return;
    }
    List<MedicineSearchHit> hits;
    try {
      hits = await (widget.search ?? DatabaseHelper().searchMedicines)(q);
    } catch (_) {
      hits = const [];
    }
    // Una risposta arrivata tardi non deve coprire quella più recente.
    if (!mounted || q != _controller.text.trim()) return;
    setState(() {
      _hits = hits;
      _searching = false;
    });
  }

  Future<void> _open(MedicineSearchHit hit) async {
    final cabinets = await DatabaseHelper().getCabinets();
    final Cabinet? cabinet = cabinets
        .where((c) => c.id == hit.medicine.cabinetId)
        .firstOrNull;
    if (cabinet == null || !mounted) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => CabinetScreen(cabinet: cabinet)));
    if (mounted) _run(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          cursorColor: Colors.white,
          decoration: const InputDecoration(
            hintText: 'Nome del farmaco o lotto',
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Cancella',
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                _run('');
              },
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_query.length < 2) {
      return const _Hint(
        'Scrivi almeno 2 lettere del nome o del lotto: la ricerca guarda in '
        'tutti gli armadietti.',
      );
    }
    if (_searching) return const Center(child: CircularProgressIndicator());
    if (_hits.isEmpty) {
      return _Hint('Nessun farmaco trovato per «$_query».');
    }
    final df = DateFormat('dd/MM/yyyy');
    return ListView.separated(
      itemCount: _hits.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              _hits.length == 1 ? '1 confezione' : '${_hits.length} confezioni',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          );
        }
        final hit = _hits[i - 1];
        final m = hit.medicine;
        final lot = (m.lot != null && m.lot!.isNotEmpty) ? ' · Lotto ${m.lot}' : '';
        return ListTile(
          leading: Icon(Icons.medication_outlined,
              color: getExpiryColor(m.expirationDate)),
          title: Text(m.name),
          subtitle: Text('${hit.cabinetName}$lot'),
          trailing: Text(
            '${df.format(m.expirationDate)}\n${getExpiryLabel(m.expirationDate)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: getExpiryTextColor(m.expirationDate),
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () => _open(hit),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;

  const _Hint(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 15)),
      );
}
