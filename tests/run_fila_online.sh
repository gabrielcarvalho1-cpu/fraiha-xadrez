#!/bin/bash
# R144 · fila online de XEQUE: cliente Godot + servidor local + 3 jogadores automáticos.
cd "$(dirname "$0")/.."
PORT=$((21000 + RANDOM % 9000))
PORT=$PORT FRAIHA_DEV_AUTH=1 FRAIHA_PARTY_QUEUE_TICK_MS=200 node online_v021/server.js > /tmp/srv_fila.log 2>&1 &
SRV=$!
sleep 1
node tests/server/queue_peers.cjs $PORT xeque 3 > /tmp/peer_fila.log 2>&1 &
PEER=$!
GODOT=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT timeout 200 $GODOT --headless --path . -s tests/r144_fila_online_client.gd 2>&1 | grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error"
kill $SRV $PEER 2>/dev/null
