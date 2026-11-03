#!/usr/bin/env python3
"""Copia le schermate generate da schermate_test.dart in docs/schermate/,
senza canale trasparente (Google Play vuole PNG a 24 bit), e prepara
l'icona 512×512 per la scheda.

    flutter test tools/schermate/schermate_test.dart --update-goldens
    python3 tools/schermate/esporta.py
"""
import os
from PIL import Image

QUI = os.path.dirname(os.path.abspath(__file__))
RADICE = os.path.normpath(os.path.join(QUI, '..', '..'))
SORGENTE = os.path.join(QUI, 'png')
SCHERMATE = os.path.join(RADICE, 'docs', 'schermate')
GRAFICA = os.path.join(RADICE, 'docs', 'play-store', 'grafica')

os.makedirs(SCHERMATE, exist_ok=True)
os.makedirs(GRAFICA, exist_ok=True)
for nome in sorted(os.listdir(SORGENTE)):
    if nome.endswith('.png'):
        im = Image.open(os.path.join(SORGENTE, nome)).convert('RGB')
        im.save(os.path.join(SCHERMATE, nome), optimize=True)
        print('schermata', nome, im.size)

icona = Image.open(os.path.join(RADICE, 'assets', 'icon.png')).convert('RGBA')
icona.resize((512, 512), Image.LANCZOS).save(
    os.path.join(GRAFICA, 'icona_512.png'), optimize=True)
print('icona_512.png')
