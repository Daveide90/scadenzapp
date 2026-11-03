import 'package:flutter/material.dart';

/// Stato vuoto con illustrazione, titolo e spiegazione.
///
/// Le illustrazioni sono coordinate all'icona dell'app (contorni verde scuro,
/// riempimenti mint). Un solo widget per tutte le schermate, così restano
/// uguali fra loro.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.image,
    required this.title,
    this.message,
    this.action,
    this.imageSize = 180,
  });

  /// Nome del file dentro `assets/illustrazioni/`.
  final String image;
  final String title;
  final String? message;
  final Widget? action;
  final double imageSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/illustrazioni/$image',
              width: imageSize,
              height: imageSize,
              // Il disegno è decorativo: chi usa il lettore di schermo sente
              // il titolo, non una descrizione del disegno.
              excludeFromSemantics: true,
              // Se l'asset manca l'app non deve crollare su uno stato vuoto.
              errorBuilder: (_, __, ___) => Icon(
                Icons.inbox_outlined,
                size: imageSize * 0.6,
                color: Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
