#!/usr/bin/env bash
# R185 · ATUALIZAÇÃO DO APP SEM APK: gera o pacote só com o que mudou desde o APK publicado.
# Uso: tools/android/gerar_patch.sh <base_N.pck do APK> <saida.pck> <id>
#   base_N.pck = godot --export-pack "Android" feito NA MESMA cópia leve (tools/android/copia_leve.py) do APK N.
#   Sobe <saida.pck> em app/patch-android-<id>.pck e o manifesto app/patch-android.json:
#     {"base": N, "id": "<id>", "url": "https://jogar.fraihaxadrez.com/app/patch-android-<id>.pck", "size": bytes, "sha256": "..."}
#   O app (app_boot/boot.gd) baixa na abertura, confere o SHA-256 e carrega por cima. APK novo → manifesto com "id": "".
# Não vai por pacote (precisa de APK): voz/plugins, permissões, ícone, versão do Godot, classes novas com class_name.
set -euo pipefail
BASE="$1"; OUT="$2"; ID="$3"
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
LEVE=/home/claude/fx-android-leve
G=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
python3 "$SRC/tools/android/copia_leve.py" "$SRC" "$LEVE"
cd "$LEVE"
"$G" --headless --path . --import >/dev/null 2>&1 || true
"$G" --headless --path . --export-patch "Android" "$OUT" --patches "$BASE"
SIZE=$(stat -c %s "$OUT"); SHA=$(sha256sum "$OUT" | cut -d' ' -f1)
echo "{\"base\": ${BASE_CODE:-0}, \"id\": \"$ID\", \"url\": \"https://jogar.fraihaxadrez.com/app/patch-android-$ID.pck\", \"size\": $SIZE, \"sha256\": \"$SHA\"}"
