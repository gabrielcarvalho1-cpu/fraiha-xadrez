#!/bin/bash
# R42 · GATE MANUAL Web real: Stockfish (Worker/WASM) fora de PvP + fair play com job EM VOO
# (análise e bot) + modo LOCAL. Exporta uma CÓPIA de QA com engine_gate.tscn como cena principal
# (nunca a build do produto) e roda no Chromium. Uso: tests/web/qa_gate/run_engine_gate.sh
set -e
SRC="$(cd "$(dirname "$0")/../../.." && pwd)"
G=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
Q=$(mktemp -d); OUT=$(mktemp -d)
(cd "$SRC" && tar --exclude=.git --exclude=node_modules -cf - .) | (cd "$Q" && tar xf -)
mkdir -p "$Q/qa_gate"; cp "$SRC/tests/web/qa_gate/engine_gate.gd" "$SRC/tests/web/qa_gate/engine_gate.tscn" "$Q/qa_gate/"
rm -rf "$Q/tests/web/qa_gate"   # a cena de QA vive só em res://qa_gate na cópia
sed -i 's#res://tests/web/qa_gate/engine_gate.gd#res://qa_gate/engine_gate.gd#' "$Q/qa_gate/engine_gate.tscn"
sed -i 's#run/main_scene="[^"]*"#run/main_scene="res://qa_gate/engine_gate.tscn"#' "$Q/project.godot"
(cd "$Q" && timeout 300 $G --headless --path . --import >/dev/null 2>&1 || true)
(cd "$Q" && timeout 900 xvfb-run -a $G --headless --path . --export-release "Web Alpha" "$OUT/index.html" >/dev/null 2>&1)
cp -r "$SRC/web/engines" "$OUT/"
PORT=$((28000 + RANDOM % 1000))
(cd "$OUT" && python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1) & HTTP=$!
sleep 1
python3 "$SRC/tests/web/qa_gate/gate_run.py" "http://127.0.0.1:$PORT/index.html" | grep -v "^FAIR PLAY"
kill $HTTP; rm -rf "$Q" "$OUT"
