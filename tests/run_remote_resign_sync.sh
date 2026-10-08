#!/bin/bash
# R53 · fim de partida online chega ao outro jogador (conectado e com o link morto na hora do fim).
# Servidor de teste (gravação lenta como o Supabase) + adversário automático que desiste 2 s após começar.
# Uso: tests/run_remote_resign_sync.sh [-- --mobile-test --size 390x844 [--actions-open]]
cd "$(dirname "$0")/.."
[ -d node_modules/ws ] || export NODE_PATH="${SKIN_NODE_PATH:-/home/claude/nodedeps/node_modules}:${NODE_PATH:-}"
PORT=$((21000 + RANDOM % 9000))
LOG=$(mktemp)
PORT=$PORT FRAIHA_DEV_AUTH=1 FRAIHA_RANKED_START_DELAY_MS=300 PERSIST_DELAY_MS=${PERSIST_DELAY_MS:-400} node tests/server/slow_persist_server.cjs > $LOG 2>&1 &
SRV=$!; for i in $(seq 1 50); do grep -q listening $LOG && break; sleep 0.1; done
node tests/server/ranked_result_peer.cjs $PORT ranked:resign:2,ranked:resign:2 > /dev/null 2>&1 &
PEER=$!
GODOT=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT timeout ${TMO:-240} xvfb-run -a $GODOT --rendering-driver opengl3 --path . -s tests/remote_resign_sync_client_test.gd "$@" 2>&1 | grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error"
RC=${PIPESTATUS[0]}
kill $SRV $PEER 2>/dev/null; rm -f $LOG
exit $RC
