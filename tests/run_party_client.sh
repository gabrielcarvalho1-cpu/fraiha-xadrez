#!/bin/bash
# R35 · teste do cliente Godot online (MARCHA REAL / XEQUE) contra servidor local + PeerParty.
cd "$(dirname "$0")/.."
PORT=$((21000 + RANDOM % 9000))
PORT=$PORT FRAIHA_DEV_AUTH=1 FRAIHA_PARTY_MARCHA_BOT_MS=200 node online_v021/server.js > /tmp/srv_party.log 2>&1 &
SRV=$!
sleep 1
node tests/server/party_peer.cjs $PORT GodotParty > /tmp/peer_party.log 2>&1 &
PEER=$!
GODOT=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
if [[ " $* " == *" --shots "* ]]; then
  FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT timeout 400 xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . -s tests/party_client_test.gd -- "$@" 2>&1 | grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error|DBG"
else
  FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT timeout 400 $GODOT --headless --path . -s tests/party_client_test.gd -- "$@" 2>&1 | grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error|DBG"
fi
kill $SRV $PEER 2>/dev/null
