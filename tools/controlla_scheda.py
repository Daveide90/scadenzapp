#!/usr/bin/env python3
"""Controlla i limiti di caratteri dei testi in docs/play-store/scheda.md
(nome 30, descrizione breve 80, completa 4000, note sulla versione 500)."""
import os
import re
import sys

p = os.path.join(os.path.dirname(__file__), '..', 'docs', 'play-store', 'scheda.md')
testo = open(p, encoding='utf-8').read()
limiti = [('Nome dell', 30), ('Descrizione breve', 80),
          ('Descrizione completa', 4000), ('Note sulla versione', 500)]
ok = True
for titolo, limite in limiti:
    m = re.search(r'## ' + titolo + r'.*?```\n(.*?)\n```', testo, re.S)
    n = len(m.group(1))
    stato = 'ok' if n <= limite else 'TROPPO LUNGO'
    ok &= n <= limite
    print(f'{titolo:22s} {n:5d} / {limite}  {stato}')
sys.exit(0 if ok else 1)
