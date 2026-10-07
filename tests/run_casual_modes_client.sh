#!/bin/bash
# Casual controlado pelo Admin na tela do jogo: servidor LOCAL (FRAIHA_DEV_AUTH=1, Admin ligado para dev:boss) + cliente Godot
# numa CÓPIA do projeto (não suja o repo). Com xvfb grava capturas em $SHOTS. Nada externo.
# Uso: tests/run_casual_modes_client.sh [pasta_screenshots]
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}"
[ -d "$SRC/node_modules/ws" ] || export NODE_PATH="${CASUAL_QA_NODE_PATH:-/home/claude/nodedeps/node_modules}:${NODE_PATH:-}"
WORK="$(mktemp -d)"; trap 'kill $SRV 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/proj" && (cd "$SRC" && tar --exclude=./.git --exclude=./node_modules -cf - .) | (cd "$WORK/proj" && tar -xf -)
PORT=$((24000 + RANDOM % 5000))
BOSS=1ea3aa2e-1217-4d41-a665-c1a26b626cde
(cd "$SRC" && PORT=$PORT FRAIHA_DEV_AUTH=1 FRAIHA_ENV=local FRAIHA_ADMIN_USERS=$BOSS=owner node online_v021/server.js > "$WORK/srv.log" 2>&1) & SRV=$!
sleep 1.2
export XDG_DATA_HOME="$WORK/userdata"
(cd "$WORK/proj" && timeout 300 "$GODOT" --headless --import >/dev/null 2>&1)
SHOTS_DIR="${1:-}"
[ -n "$SHOTS_DIR" ] && mkdir -p "$SHOTS_DIR"
if [ -n "$SHOTS_DIR" ] && command -v xvfb-run >/dev/null; then
  CASUAL_MODES_PORT=$PORT FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT SHOTS="$SHOTS_DIR" timeout 240 xvfb-run -a -s "-screen 0 1440x900x24" "$GODOT" --rendering-driver opengl3 --resolution 1440x900 --path "$WORK/proj" -s tests/casual_modes_client_test.gd > "$WORK/out.log" 2>&1
else
  CASUAL_MODES_PORT=$PORT FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT timeout 240 "$GODOT" --headless --path "$WORK/proj" -s tests/casual_modes_client_test.gd > "$WORK/out.log" 2>&1
fi
RC=$?
grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error" -A2 "$WORK/out.log" | head -80
exit $RC
