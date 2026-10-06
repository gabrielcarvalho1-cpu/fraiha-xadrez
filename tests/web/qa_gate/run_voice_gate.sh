#!/bin/bash
# R45 · GATE Web real da FRAIHA Voice (ponte JS + SDK Agora no Chromium, microfone falso).
# Exporta uma CÓPIA de QA com voice_gate.tscn como cena principal e serve SEM COEP (como o Worker).
set -e
SRC="$(cd "$(dirname "$0")/../../.." && pwd)"
G=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
Q=$(mktemp -d); OUT=$(mktemp -d)
(cd "$SRC" && tar --exclude=.git --exclude=node_modules -cf - .) | (cd "$Q" && tar xf -)
mkdir -p "$Q/qa_gate"; cp "$SRC/tests/web/qa_gate/voice_gate.gd" "$SRC/tests/web/qa_gate/voice_gate.tscn" "$Q/qa_gate/"
rm -rf "$Q/tests/web/qa_gate"
sed -i 's#res://tests/web/qa_gate/voice_gate.gd#res://qa_gate/voice_gate.gd#' "$Q/qa_gate/voice_gate.tscn"
sed -i 's#run/main_scene="[^"]*"#run/main_scene="res://qa_gate/voice_gate.tscn"#' "$Q/project.godot"
(cd "$Q" && timeout 300 $G --headless --path . --import >/dev/null 2>&1 || true)
(cd "$Q" && timeout 900 xvfb-run -a $G --headless --path . --export-release "Web Alpha" "$OUT/index.html" >/dev/null 2>&1)
cp -r "$SRC/web/voice" "$OUT/"
PORT=$((28000 + RANDOM % 1000))
(cd "$OUT" && python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1) & HTTP=$!
sleep 1
python3 "$SRC/tests/web/qa_gate/voice_gate_run.py" "http://127.0.0.1:$PORT/index.html"
kill $HTTP; rm -rf "$Q" "$OUT"
