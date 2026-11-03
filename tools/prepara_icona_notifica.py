#!/usr/bin/env python3
"""Crea l'icona per le notifiche a partire dal foreground dell'icona app.

Nella barra di stato Android usa soltanto la trasparenza dell'immagine: una
icona a colori diventa una macchia bianca senza forma. Serve quindi una
sagoma tutta bianca su fondo trasparente, in tutte le densità.

    python3 tools/prepara_icona_notifica.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

SRC = Path('assets/icon_foreground.png')
RES = Path('android/app/src/main/res')

# 24dp nelle varie densità, come vuole la barra di stato.
DENSITIES = {
    'drawable-mdpi': 24,
    'drawable-hdpi': 36,
    'drawable-xhdpi': 48,
    'drawable-xxhdpi': 72,
    'drawable-xxxhdpi': 96,
}

# Sotto questa opacità il pixel è considerato fuori dalla sagoma.
ALPHA_THRESHOLD = 40


def main() -> None:
    src = Image.open(SRC).convert('RGBA')

    # Tutto ciò che è visibile diventa bianco pieno: conta solo la forma.
    pixels = src.load()
    for y in range(src.height):
        for x in range(src.width):
            _, _, _, a = pixels[x, y]
            pixels[x, y] = (255, 255, 255, 0 if a < ALPHA_THRESHOLD else 255)

    box = src.getbbox()
    sagoma = src.crop(box) if box else src

    for folder, size in DENSITIES.items():
        # Un margine interno evita che il sistema tagli i bordi.
        inner = int(size * 0.9)
        ratio = min(inner / sagoma.width, inner / sagoma.height)
        piccola = sagoma.resize(
            (max(1, int(sagoma.width * ratio)), max(1, int(sagoma.height * ratio))),
            Image.LANCZOS,
        )
        canvas = Image.new('RGBA', (size, size), (255, 255, 255, 0))
        canvas.paste(
            piccola,
            ((size - piccola.width) // 2, (size - piccola.height) // 2),
            piccola,
        )
        out = RES / folder / 'ic_notification.png'
        out.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(out)
        print(f'{out}  {size}x{size}')


if __name__ == '__main__':
    main()
