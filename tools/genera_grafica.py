#!/usr/bin/env python3
"""Genera la grafica dell'app (icona, illustrazioni) via OpenRouter.

La chiave si legge da OPENROUTER_API_KEY oppure da un file .env indicato con
--env: non viene mai stampata. Ogni immagine finisce in un PNG e accanto viene
salvato il prompt usato, così una grafica si può rigenerare identica.

Esempio:
    python3 tools/genera_grafica.py \
        --prompt "..." --out design/icona_a.png \
        --env percorso/del/file.env
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

API_URL = "https://openrouter.ai/api/v1/chat/completions"
DEFAULT_MODEL = "openai/gpt-5.4-image-2"  # GPT Image 2


def read_key(env_file: str | None) -> str:
    key = os.environ.get("OPENROUTER_API_KEY")
    if key:
        return key.strip()
    if env_file:
        pattern = re.compile(
            r"\s*(?:export\s+)?OPENROUTER_API_KEY\s*=\s*[\"']?([^\"'\s]+)"
        )
        for line in Path(env_file).read_text().splitlines():
            found = pattern.match(line)
            if found:
                return found.group(1)
    sys.exit("Nessuna chiave: usa OPENROUTER_API_KEY o --env")


def generate(prompt: str, out: Path, model: str, key: str) -> None:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "modalities": ["image", "text"],
    }
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/Daveide90/scadenzapp",
            "X-Title": "ScadenzApp grafica",
        },
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        data = json.load(resp)

    message = data["choices"][0]["message"]
    images = message.get("images") or []
    if not images:
        sys.exit(f"Nessuna immagine restituita: {message.get('content')!r}")

    url = images[0]["image_url"]["url"]
    if not url.startswith("data:"):
        with urllib.request.urlopen(url, timeout=300) as resp:
            raw = resp.read()
    else:
        raw = base64.b64decode(url.split(",", 1)[1])

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(raw)
    out.with_suffix(".prompt.txt").write_text(prompt + "\n", encoding="utf-8")

    usage = data.get("usage", {})
    print(f"{out}  ({len(raw) // 1024} KB)  costo: {usage.get('cost', '?')}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--env", help="file .env da cui leggere la chiave")
    args = parser.parse_args()

    generate(args.prompt, args.out, args.model, read_key(args.env))


if __name__ == "__main__":
    main()
