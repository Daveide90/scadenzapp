#!/usr/bin/env python3
"""Genera assets/aifa_catalog.db.gz dall'anagrafica open data AIFA.

Fonte: https://drive.aifa.gov.it/farmaci/confezioni_fornitura.csv
(aggiornata quotidianamente da AIFA). Tiene solo le confezioni "Autorizzata".

Uso:
    python3 tools/genera_catalogo_aifa.py            # scarica il CSV
    python3 tools/genera_catalogo_aifa.py file.csv   # usa un CSV locale

Richiede solo la libreria standard.
"""
import csv
import datetime
import gzip
import os
import shutil
import sqlite3
import ssl
import sys
import tempfile
import urllib.request

CSV_URL = "https://drive.aifa.gov.it/farmaci/confezioni_fornitura.csv"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "aifa_catalog.db.gz")


def scarica_csv(dest: str) -> None:
    print(f"Scarico {CSV_URL} ...")
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # la catena del sito AIFA non valida ovunque
    with urllib.request.urlopen(CSV_URL, context=ctx, timeout=120) as r, \
            open(dest, "wb") as f:
        shutil.copyfileobj(r, f)


def genera(csv_path: str) -> None:
    db_path = tempfile.mktemp(suffix=".db")
    con = sqlite3.connect(db_path)
    con.execute("PRAGMA page_size=4096")
    con.execute("CREATE TABLE farmaci ("
                "cod_farmaco TEXT PRIMARY KEY, denominazione TEXT NOT NULL, "
                "pa TEXT NOT NULL, forma TEXT NOT NULL)")
    con.execute("CREATE TABLE confezioni ("
                "aic TEXT PRIMARY KEY, cod_farmaco TEXT NOT NULL, "
                "descrizione TEXT NOT NULL)")
    con.execute("CREATE TABLE meta (chiave TEXT PRIMARY KEY, valore TEXT NOT NULL)")

    farmaci = {}
    confezioni = []
    with open(csv_path, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f, delimiter=";"):
            if row["STATO_AMMINISTRATIVO"] != "Autorizzata":
                continue
            cf = row["COD_FARMACO"]
            farmaci[cf] = (cf, row["DENOMINAZIONE"], row["PA_ASSOCIATI"],
                           row["FORMA"])
            confezioni.append((row["CODICE_AIC"], cf, row["DESCRIZIONE"]))

    con.executemany("INSERT OR REPLACE INTO farmaci VALUES (?,?,?,?)",
                    farmaci.values())
    con.executemany("INSERT OR REPLACE INTO confezioni VALUES (?,?,?)", confezioni)
    con.execute("INSERT INTO meta VALUES ('generato', ?)",
                (datetime.date.today().isoformat(),))
    con.commit()
    con.execute("VACUUM")
    con.close()

    out = os.path.abspath(OUT)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(db_path, "rb") as fi, gzip.open(out, "wb", compresslevel=9) as fo:
        shutil.copyfileobj(fi, fo)
    os.remove(db_path)
    print(f"{len(farmaci)} farmaci, {len(confezioni)} confezioni "
          f"-> {out} ({os.path.getsize(out) / 1024 / 1024:.1f} MB)")


def main() -> None:
    if len(sys.argv) > 1:
        genera(sys.argv[1])
    else:
        with tempfile.NamedTemporaryFile(suffix=".csv") as tmp:
            scarica_csv(tmp.name)
            genera(tmp.name)


if __name__ == "__main__":
    main()
