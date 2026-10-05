#!/bin/bash
# R42.1 · Ranked seguidas com gravação lenta do resultado (como o Supabase real). ~1 min.
cd "$(dirname "$0")/.."
export NODE_PATH=${NODE_PATH:-/home/claude/nodedeps/node_modules}
PORT=$((21000 + RANDOM % 9000))
PORT=$PORT FRAIHA_DEV_AUTH=1 FRAIHA_RANKED_START_DELAY_MS=300 PERSIST_DELAY_MS=${PERSIST_DELAY_MS:-400} node tests/server/slow_persist_server.cjs > /tmp/srv_ranked_lifecycle.log 2>&1 &
SRV=$!; for i in $(seq 1 50); do grep -q listening /tmp/srv_ranked_lifecycle.log && break; sleep 0.1; done
node tests/server/ranked_result_peer.cjs $PORT ${PEER_ACTIONS:-ranked:resign,ranked:wait,ranked:resign} > /tmp/peer_ranked_lifecycle.log 2>&1 &
PEER=$!
GODOT=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT timeout ${TMO:-240} $GODOT --headless --path . -s ${TEST:-tests/ranked_result_lifecycle_client_test.gd} 2>&1 | grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error|DBG"
kill $SRV $PEER 2>/dev/null
