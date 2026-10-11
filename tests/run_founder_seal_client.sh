#!/bin/bash
# R62 · selo Fundador na faixa da partida. Uso: tests/run_founder_seal_client.sh [casual|ranked] [--mobile|--land]
cd "$(dirname "$0")/.."
export NODE_PATH=${NODE_PATH:-/home/claude/nodedeps/node_modules}
KIND=${1:-casual}; shift
PORT=$((21000 + RANDOM % 9000))
PORT=$PORT FRAIHA_DEV_AUTH=1 FRAIHA_RANKED_START_DELAY_MS=300 node online_v021/server.js > /tmp/srv_seal.log 2>&1 &
SRV=$!
sleep 1
node tests/server/founder_peer.cjs $PORT ${KIND}_3min 20000 > /tmp/peer_seal.log 2>&1 &
PEER=$!
GODOT=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
SIZE=""; EXTRA=""
[[ " $* " == *" --mobile "* ]] && SIZE=390x844 && EXTRA="-- --mobile-test"
[[ " $* " == *" --land "* ]] && SIZE=844x390 && EXTRA="-- --mobile-test"
FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT SEAL_KIND=$KIND LOOK_SIZE=$SIZE timeout 300 xvfb-run -a -s "-screen 0 2000x1200x24" $GODOT --path . --rendering-driver opengl3 -s tests/founder_seal_client_test.gd $EXTRA 2>&1 | grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error"
kill $SRV $PEER 2>/dev/null
