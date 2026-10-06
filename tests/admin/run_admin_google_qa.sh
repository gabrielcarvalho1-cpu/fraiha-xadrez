#!/bin/bash
# FRAIHA Admin V1 · QA do ENTRAR COM GOOGLE (Google/Supabase MOCKADOS no navegador; ver admin_google_test.py).
# Admin servido pelo PRÓPRIO servidor em /admin/. Nada externo: só 127.0.0.1.
# Uso: tests/admin/run_admin_google_qa.sh [pasta_screenshots]
cd "$(dirname "$0")/../.."
[ -d node_modules/ws ] || export NODE_PATH="${ADMIN_QA_NODE_PATH:-/home/claude/nodedeps/node_modules}:$NODE_PATH"
BOSS=1ea3aa2e-1217-4d41-a665-c1a26b626cde   # UUID determinístico da conta DEV "dev:boss" (DevAuth)
PORT=8140 FRAIHA_DEV_AUTH=1 FRAIHA_ENV=local FRAIHA_ADMIN_USERS=$BOSS=owner node online_v021/server.js > /tmp/admin_google_srv.log 2>&1 & SRV=$!
sleep 1.5
node tests/admin/seed_dev.cjs 8140 > /tmp/admin_google_seed.log 2>&1 & SEED=$!
sleep 4
python3 tests/admin/admin_google_test.py "${1:-/tmp/admin_google_shots}"; RC=$?
kill $SRV $SEED 2>/dev/null
exit $RC
