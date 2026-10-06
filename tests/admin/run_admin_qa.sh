#!/bin/bash
# FRAIHA Admin V1 · QA local completo: servidor DEV (memória, FRAIHA_DEV_AUTH=1) + atividade real + Admin + Chromium.
# Nada externo: só 127.0.0.1. Uso: tests/admin/run_admin_qa.sh [pasta_screenshots]
cd "$(dirname "$0")/../.."
[ -d node_modules/ws ] || export NODE_PATH="${ADMIN_QA_NODE_PATH:-/home/claude/nodedeps/node_modules}:$NODE_PATH"   # ws (dependência do servidor)
BOSS=1ea3aa2e-1217-4d41-a665-c1a26b626cde   # UUID determinístico da conta DEV "dev:boss" (DevAuth)
PORT=8140 FRAIHA_DEV_AUTH=1 FRAIHA_ENV=local FRAIHA_ADMIN_USERS=$BOSS=owner node online_v021/server.js > /tmp/admin_qa_srv.log 2>&1 & SRV=$!
sleep 1.5
node tests/admin/seed_dev.cjs 8140 > /tmp/admin_qa_seed.log 2>&1 & SEED=$!
(cd admin && python3 -m http.server 8150 --bind 127.0.0.1 >/dev/null 2>&1) & WEB=$!
sleep 5
python3 tests/admin/admin_ui_test.py "${1:-/tmp/admin_shots}"; RC=$?
kill $SRV $SEED $WEB 2>/dev/null
exit $RC
