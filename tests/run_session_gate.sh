#!/bin/bash
# R42 · GATE de sessão com cliente Godot REAL (conta logada em partida Casual atravessando a
# revalidação de 60 s e uma renovação de token). Demora ~2 min. Uso: tests/run_session_gate.sh
cd "$(dirname "$0")/.."
export NODE_PATH=${NODE_PATH:-/home/claude/nodedeps/node_modules}
PORT=$((21000 + RANDOM % 9000))
PORT=$PORT FRAIHA_DEV_AUTH=1 FRAIHA_RANKED_START_DELAY_MS=300 node online_v021/server.js > /tmp/srv_session_gate.log 2>&1 &
SRV=$!; sleep 1
node tests/server/session_gate_peer.cjs $PORT > /tmp/peer_session_gate.log 2>&1 &
PEER=$!
GODOT=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT timeout 280 $GODOT --headless --path . -s tests/session_gate_client_test.gd 2>&1 | grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error|DBG"
kill $SRV $PEER 2>/dev/null
