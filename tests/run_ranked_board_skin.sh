#!/bin/bash
# R49 · pele do tabuleiro Ranked Madeira com partida REAL (servidor local + adversário automático), numa CÓPIA
# do projeto. Uso: tests/run_ranked_board_skin.sh [mob]
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}"
[ -d "$SRC/node_modules/ws" ] || export NODE_PATH="${SKIN_NODE_PATH:-/home/claude/nodedeps/node_modules}:${NODE_PATH:-}"
WORK="${SKIN_WORK:-$(mktemp -d)}"
mkdir -p "$WORK/proj" && (cd "$SRC" && tar --exclude=./.git --exclude=./node_modules --exclude=./.godot -cf - .) | (cd "$WORK/proj" && tar -xf -)
export XDG_DATA_HOME="$WORK/userdata"
(cd "$WORK/proj" && timeout 300 "$GODOT" --headless --import >/dev/null 2>&1)
PORT=$((24000 + RANDOM % 5000))
(cd "$SRC" && PORT=$PORT FRAIHA_DEV_AUTH=1 FRAIHA_RANKED_START_DELAY_MS=300 node online_v021/server.js > "$WORK/srv.log" 2>&1) & SRV=$!
sleep 1.2
(cd "$SRC" && node tests/server/ranked_result_peer.cjs $PORT ranked:wait > "$WORK/peer.log" 2>&1) & PEER=$!
EX=""; [ "${1:-}" = "mob" ] && EX="-- --mobile-test"
FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT timeout 240 "$GODOT" --headless --path "$WORK/proj" -s tests/ranked_board_skin_test.gd $EX > "$WORK/out.log" 2>&1
RC=$?
grep -E "PASS|FAIL|SKIP|RESULT|SCRIPT ERROR|Parse Error" -A2 "$WORK/out.log" | head -80
kill $SRV $PEER 2>/dev/null
exit $RC
