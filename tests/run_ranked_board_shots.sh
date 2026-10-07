#!/bin/bash
# Capturas do tabuleiro Ranked + subida de liga (servidor LOCAL + adversário automático), numa CÓPIA do projeto.
# Uso: tests/run_ranked_board_shots.sh <pasta> [mob]
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:?pasta}" && cd "$1" && pwd)"
GODOT="${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}"
[ -d "$SRC/node_modules/ws" ] || export NODE_PATH="${BOARD_NODE_PATH:-/home/claude/nodedeps/node_modules}:${NODE_PATH:-}"
WORK="${BOARD_WORK:-$(mktemp -d)}"
mkdir -p "$WORK/proj" && (cd "$SRC" && tar --exclude=./.git --exclude=./node_modules --exclude=./.godot -cf - .) | (cd "$WORK/proj" && tar -xf -)
export XDG_DATA_HOME="$WORK/userdata"
(cd "$WORK/proj" && timeout 300 "$GODOT" --headless --import >/dev/null 2>&1)
PORT=$((24000 + RANDOM % 5000))
(cd "$SRC" && PORT=$PORT FRAIHA_DEV_AUTH=1 FRAIHA_RANKED_START_DELAY_MS=300 node online_v021/server.js > "$WORK/srv.log" 2>&1) & SRV=$!
sleep 1.2
(cd "$SRC" && node tests/server/ranked_result_peer.cjs $PORT ranked:wait > "$WORK/peer.log" 2>&1) & PEER=$!
if [ "${2:-}" = "mob" ]; then PX=${BOARD_MOB_PX:-854x1842}; CSS=${BOARD_MOB_CSS:-427x921}; EX="-- --mobile-test"; NAME=mob; else PX=1672x941; CSS=""; EX=""; NAME=pc; fi
mkdir -p "$OUT/$NAME"
BOARD_SHOTS="$OUT/$NAME" BOARD_PX=$PX BOARD_CSS=$CSS FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT timeout 200 xvfb-run -a -s "-screen 0 2000x2000x24" "$GODOT" --rendering-driver opengl3 --resolution $PX --path "$WORK/proj" -s tests/ranked_board_shots.gd $EX 2>&1 | grep -E "SHOT|PARTIDA|SCRIPT ERROR"
kill $SRV $PEER 2>/dev/null
