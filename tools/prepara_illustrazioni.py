#!/usr/bin/env python3
"""Prepara le illustrazioni degli stati vuoti per l'app.

Le immagini generate arrivano a 1024px con lo sfondo bianco pieno: pesano
troppo per stare in un APK e il rettangolo bianco si nota sopra lo sfondo
delle schermate. Qui vengono rimpicciolite e lo sfondo viene reso
trasparente partendo dai bordi, così i bianchi interni al disegno restano.

    python3 tools/prepara_illustrazioni.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 512
# Quanto un pixel di bordo può discostarsi dal bianco ed essere ancora sfondo.
TOLERANCE = 18

SOURCES = {
    "design/vuoto_nessun_armadietto.png": "armadietti.png",
    "design/vuoto_armadietto.png": "armadietto_vuoto.png",
    "design/vuoto_tutto_in_ordine.png": "tutto_in_ordine.png",
    "design/vuoto_nessun_controllo.png": "nessun_controllo.png",
}

OUT_DIR = Path("assets/illustrazioni")


def strip_background(im: Image.Image) -> Image.Image:
    """Toglie lo sfondo bianco partendo dai quattro angoli."""
    im = im.convert("RGBA")
    w, h = im.size
    for corner in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        if im.getpixel(corner)[3] == 0:
            continue
        ImageDraw.floodfill(
            im,
            corner,
            (255, 255, 255, 0),
            thresh=TOLERANCE,
        )
    return im


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for src, name in SOURCES.items():
        im = Image.open(src).convert("RGBA")
        im = strip_background(im)
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
        out = OUT_DIR / name
        im.save(out, optimize=True)
        print(f"{out}  {out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
