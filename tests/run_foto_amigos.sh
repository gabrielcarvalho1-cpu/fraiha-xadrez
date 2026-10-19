#!/bin/bash
# R150 · foto dos amigos no cliente: serve fotos de teste por HTTP local e roda o teste Godot.
cd "$(dirname "$0")/.."
DIR=$(mktemp -d)
python3 - "$DIR" <<'PY'
import sys
from PIL import Image, ImageDraw
for n, c in [("a", (40, 90, 160)), ("b", (170, 60, 110)), ("b2", (60, 150, 90))]:
    im = Image.new("RGB", (512, 512), c); d = ImageDraw.Draw(im)
    d.ellipse((140, 90, 372, 322), fill=(240, 210, 180)); d.rectangle((110, 330, 402, 512), fill=(30, 30, 30))
    im.save(sys.argv[1] + "/" + n + ".png")
PY
PORT=$((30000 + RANDOM % 9000))
python3 -m http.server $PORT --bind 127.0.0.1 --directory "$DIR" > /dev/null 2>&1 &
HTTP=$!
sleep 0.5
GODOT=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
PHOTO_BASE=http://127.0.0.1:$PORT timeout 200 $GODOT --headless --path . -s tests/r150_foto_amigos_test.gd 2>&1 | grep -E "PASS|FAIL|SCRIPT ERROR|Parse Error"
kill $HTTP 2>/dev/null; rm -rf "$DIR"
