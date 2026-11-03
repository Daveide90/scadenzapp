#!/usr/bin/env python3
"""Prepara i due asset dell'icona a partire da un PNG piatto generato.

- `assets/icon.png`: l'icona intera (sfondo compreso), per l'icona classica.
- `assets/icon_foreground.png`: solo il soggetto su trasparente, rimpicciolito
  dentro la zona sicura dell'adaptive icon di Android (il sistema può ritagliare
  fino a un cerchio, quindi il disegno deve stare nel 66% centrale).

Stampa anche il colore di sfondo rilevato, da mettere in
`flutter_launcher_icons.adaptive_icon_background`.

    python3 tools/prepara_icona.py design/icona_A1_rifinita.png
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

# Quanta parte del quadrato può occupare il disegno nell'adaptive icon.
SAFE_FRACTION = 0.66
# Distanza massima dal colore di sfondo perché un pixel sia considerato sfondo.
TOLERANCE = 42


def background_color(im: Image.Image) -> tuple[int, int, int]:
    """Colore dei quattro angoli: è lo sfondo pieno dell'icona."""
    w, h = im.size
    corners = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]
    pixels = [im.getpixel(c)[:3] for c in corners]
    return tuple(sum(c[i] for c in pixels) // len(pixels) for i in range(3))


def cut_background(im: Image.Image, bg: tuple[int, int, int]) -> Image.Image:
    """Rende trasparente tutto ciò che è vicino al colore di sfondo."""
    out = im.convert("RGBA").copy()
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            dist = ((r - bg[0]) ** 2 + (g - bg[1]) ** 2 + (b - bg[2]) ** 2) ** 0.5
            if dist <= TOLERANCE:
                px[x, y] = (r, g, b, 0)
    return out


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("Uso: prepara_icona.py <png sorgente>")
    src = Path(sys.argv[1])
    im = Image.open(src).convert("RGBA")
    size = im.size[0]

    bg = background_color(im)
    print(f"sfondo rilevato: #{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}")

    # 1. Icona classica: l'immagine così com'è.
    Path("assets").mkdir(exist_ok=True)
    im.save("assets/icon.png")

    # 2. Foreground: soggetto isolato, ritagliato al suo ingombro e ricentrato
    #    dentro la zona sicura.
    cut = cut_background(im, bg)
    box = cut.getbbox()
    if box is None:
        sys.exit("Nessun soggetto trovato: lo sfondo copre tutta l'immagine")
    subject = cut.crop(box)

    target = int(size * SAFE_FRACTION)
    ratio = min(target / subject.width, target / subject.height)
    subject = subject.resize(
        (max(1, int(subject.width * ratio)), max(1, int(subject.height * ratio))),
        Image.LANCZOS,
    )

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(
        subject,
        ((size - subject.width) // 2, (size - subject.height) // 2),
        subject,
    )
    canvas.save("assets/icon_foreground.png")
    print("scritti assets/icon.png e assets/icon_foreground.png")


if __name__ == "__main__":
    main()
