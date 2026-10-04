#!/bin/bash
# R39 · cliente Godot com pagamento REAL (FRAIHA_PAYMENT_MODE=real) contra servidor local + Mercado Pago falso.
cd "$(dirname "$0")/.."
export NODE_PATH=${NODE_PATH:-/home/claude/nodedeps/node_modules}
PORT=$((21000 + RANDOM % 9000)); MPP=$((PORT + 1))
node tests/server/fake_mercadopago.cjs $MPP > /tmp/fake_mp.log 2>&1 &
MP=$!
PORT=$PORT FRAIHA_DEV_AUTH=1 FRAIHA_PAYMENT_PROVIDER=mercadopago FRAIHA_MP_ACCESS_TOKEN=TEST-TOKEN FRAIHA_MP_WEBHOOK_SECRET=s \
  FRAIHA_MP_API=http://127.0.0.1:$MPP FRAIHA_PUBLIC_URL=https://servidor.fraiha.test FRAIHA_FOUNDER_LIMIT=2 \
  FRAIHA_FOUNDER_WHATSAPP_URL=https://chat.whatsapp.com/GRUPO-TESTE node online_v021/server.js > /tmp/srv_payment.log 2>&1 &
SRV=$!
sleep 1
GODOT=${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}
SHOTS=""; [[ " $* " == *" --shots "* ]] && SHOTS=1
if [ -n "$SHOTS" ]; then RUN="xvfb-run -a -s \"-screen 0 1920x1080x24\" $GODOT --path ."; else RUN="$GODOT --headless --path ."; fi
FRAIHA_PAYMENT_MODE=real FAKE_MP=http://127.0.0.1:$MPP FRAIHA_SERVER_URL=ws://127.0.0.1:$PORT PAY_SHOTS=$SHOTS timeout 300 bash -c "$RUN -s tests/payment_real_client_test.gd" 2>&1 | grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error|DBG"
kill $SRV $MP 2>/dev/null
