#!/bin/bash
# R47 · capturas da HOME para comparar com as referências do dono (tools/home_ref/home_referencia_r47_*.png).
# Roda numa CÓPIA do projeto (não suja o repo com .godot/.import). Precisa de xvfb. Nada de rede.
# Uso: tests/run_home_ref_shots.sh <pasta_saida>
# Saída: pc.png (1672x941), celular.png (854x1842 = 427x921 CSS a 2x), lado_a_lado_pc.png, lado_a_lado_celular.png
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:?pasta de saída}" && cd "$1" && pwd)"
GODOT="${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/proj" && (cd "$SRC" && tar --exclude=./.git --exclude=./node_modules -cf - .) | (cd "$WORK/proj" && tar -xf -)
export XDG_DATA_HOME="$WORK/userdata"
(cd "$WORK/proj" && timeout 300 "$GODOT" --headless --import >/dev/null 2>&1)
shot() {   # shot <arquivo> <px> <css|""> [args]
  HOME_SHOT_OUT="$1" HOME_SHOT_SIZE="$2" HOME_SHOT_CSS="$3" HOME_SHOT_LOGGED=1 timeout 120 xvfb-run -a -s "-screen 0 2000x2000x24" \
    "$GODOT" --rendering-driver opengl3 --resolution "$2" --path "$WORK/proj" -s tests/home_ref_shots.gd ${4:-} 2>&1 | grep -E "SHOT|SCRIPT ERROR"
}
shot "$OUT/pc.png" 1672x941 ""
shot "$OUT/celular.png" 854x1842 427x921 "-- --mobile-test"
python3 - "$SRC" "$OUT" <<'EOF'
import sys
from PIL import Image, ImageDraw
src, out = sys.argv[1], sys.argv[2]
for ref, shot, name, horiz in [("pc", "pc", "lado_a_lado_pc.png", False), ("mobile", "celular", "lado_a_lado_celular.png", True)]:
    a = Image.open(f"{src}/tools/home_ref/home_referencia_r47_{ref}.png").convert("RGB")
    b = Image.open(f"{out}/{shot}.png").convert("RGB").resize(a.size)
    W, H = a.size
    c = Image.new("RGB", (W * 2 + 24, H + 48) if horiz else (W, H * 2 + 72), (20, 20, 20))
    d = ImageDraw.Draw(c)
    if horiz:
        c.paste(a, (0, 48)); c.paste(b, (W + 24, 48))
        d.text((10, 14), "REFERÊNCIA", fill=(255, 220, 120)); d.text((W + 34, 14), "JOGO (captura)", fill=(255, 220, 120))
    else:
        c.paste(a, (0, 36)); c.paste(b, (0, H + 72))
        d.text((10, 10), "REFERÊNCIA", fill=(255, 220, 120)); d.text((10, H + 46), "JOGO (captura)", fill=(255, 220, 120))
    c.save(f"{out}/{name}")
    print("ok", name)
EOF
