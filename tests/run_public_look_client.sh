#!/bin/bash
# R41 · cliente Godot vendo um adversário Fundador (selo/título/moldura/avatar) no Casual.
cd "$(dirname "$0")/.."
export NODE_PATH=${NODE_PATH:-/home/claude/nodedeps/node_modules}
PORT=$((21000 + RANDOM % 9000))
PORT=$PORT FRAIHA_DEV_AUTH=1 node online_v021/server.js > /tmp/srv_look.log 2>&1 &
SRV=$!
sleep 1
node tests/server/founder_peer.cjs $PORT casual_3min 14000 > /tmp/peer_look.log 2>&1 &
PEER=$!
GODOT=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
if [[ " $* " == *" --shots "* ]]; then RUN="xvfb-run -a -s \"-screen 0 1920x1080x24\" $GODOT --path ."; SH=1; else RUN="$GODOT --headless --path ."; SH=""; fi
SIZE=""; EXTRA=""
[[ " $* " == *" --mobile "* ]] && SIZE=390x844 && EXTRA="-- --mobile-test"
[[ " $* " == *" --land "* ]] && SIZE=844x390 && EXTRA="-- --mobile-test"
FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT LOOK_SHOTS=$SH LOOK_SIZE=$SIZE timeout 300 bash -c "$RUN -s tests/public_look_client_test.gd $EXTRA" 2>&1 | grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error|DBG"
kill $SRV $PEER 2>/dev/null
