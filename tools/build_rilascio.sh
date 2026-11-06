#!/usr/bin/env bash
# APK di rilascio compilato da una cartella neutra (/var/tmp/scadenzapp-build).
#
# Flutter scrive nel binario il percorso del progetto (dart_plugin_registrant.dart):
# compilando dalla cartella di lavoro, nell'APK pubblicato finiva il percorso della home
# dell'autore (revisione del 6/11/2026, punto 10). Lo script copia il progetto, compila lì
# e si ferma se nell'APK resta un percorso della home.
#
#   tools/build_rilascio.sh        →  build/app/outputs/flutter-apk/ScadenzApp.apk (arm64)
set -euo pipefail

SORGENTE="$(cd "$(dirname "$0")/.." && pwd)"
NEUTRA=/var/tmp/scadenzapp-build
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export PATH="$HOME/.flutter-sdk/bin:$JAVA_HOME/bin:$PATH"

mkdir -p "$NEUTRA"
chmod 700 "$NEUTRA"   # dentro c'è anche la chiave di firma
rsync -a --delete \
    --exclude build/ --exclude .dart_tool/ --exclude android/.gradle/ \
    --exclude android/local.properties --exclude .git/ \
    "$SORGENTE/" "$NEUTRA/"

cd "$NEUTRA"
flutter pub get > /dev/null
flutter build apk --release --split-per-abi

APK="$NEUTRA/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
# La home e il nome utente di chi compila; non «/home/» in generale: le librerie native di
# ML Kit contengono percorsi della macchina di build di Google (/home/build/...).
TROVATI=$(unzip -p "$APK" | strings -n 6 | grep -c -e "$HOME" -e "/home/$(id -un)/" || true)
if [ "$TROVATI" != 0 ]; then
    echo "ERRORE: nell'APK ci sono $TROVATI percorsi della home"
    exit 1
fi
# Nessuna email dell'autore nel software, nemmeno quella per gli sviluppatori. Le parole sono
# spezzate in due perché non compaiano nel repository pubblico.
EMAIL=$(unzip -p "$APK" | strings -n 6 | grep -c -i -e "dev\.dav""ide@" -e "riu""ccio" || true)
if [ "$EMAIL" != 0 ]; then
    echo "ERRORE: nell'APK c'è un'email dell'autore ($EMAIL righe)"
    exit 1
fi
echo "APK: nessun percorso della home e nessuna email dell'autore."

mkdir -p "$SORGENTE/build/app/outputs/flutter-apk"
cp "$APK" "$SORGENTE/build/app/outputs/flutter-apk/ScadenzApp.apk"
sha256sum "$SORGENTE/build/app/outputs/flutter-apk/ScadenzApp.apk"
