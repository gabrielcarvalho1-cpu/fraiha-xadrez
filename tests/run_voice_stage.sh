#!/bin/bash
# R45 · FRAIHA Voice no jogo inteiro (cliente Godot + servidor real + PeerParty com voz), provedor MOCK
# (o RTC real da Agora precisa de navegador + credenciais: ver docs/voice/FRAIHA_VOICE_V1.md).
cd "$(dirname "$0")/.."
PORT=$((21000 + RANDOM % 9000))
# credenciais FICTÍCIAS (formato válido) só para o servidor local de teste gerar tokens
PORT=$PORT FRAIHA_DEV_AUTH=1 FRAIHA_PARTY_MARCHA_BOT_MS=200 FRAIHA_AGORA_APP_ID=0123456789abcdef0123456789abcdef FRAIHA_AGORA_APP_CERTIFICATE=fedcba9876543210fedcba9876543210 node online_v021/server.js > /tmp/srv_voice.log 2>&1 &
SRV=$!
sleep 1
PEER_VOICE=1 node tests/server/party_peer.cjs $PORT GodotVoice > /tmp/peer_voice.log 2>&1 &
PEER=$!
GODOT=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
if [[ " $* " == *" --shots "* ]]; then
  FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT timeout 400 xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . ${RES:+--resolution $RES} -s tests/voice_stage_test.gd -- "$@" 2>&1 | grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error|DBG|ERROR|at: "
else
  FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT timeout 400 $GODOT --headless --path . -s tests/voice_stage_test.gd -- "$@" 2>&1 | grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error|DBG|ERROR|at: "
fi
kill $SRV $PEER 2>/dev/null
grep -E "\[voice\]" /tmp/srv_voice.log | head -40
