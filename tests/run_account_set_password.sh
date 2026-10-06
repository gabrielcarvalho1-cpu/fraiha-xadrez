#!/bin/bash
# DEFINIR SENHA (conta Google): Supabase Auth MOCKADO + "servidor FRAIHA" que só registra. Nada real é tocado.
# Roda o Godot numa CÓPIA do projeto (não suja o repositório com .godot/.import/.uid).
# Uso: tests/run_account_set_password.sh [godot]
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${1:-${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}}"
[ -d "$SRC/node_modules/ws" ] || export NODE_PATH="${ACCOUNT_QA_NODE_PATH:-/home/claude/nodedeps/node_modules}:${NODE_PATH:-}"
WORK="$(mktemp -d)"; trap 'kill $MOCK 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/proj" && (cd "$SRC" && tar --exclude=./.git --exclude=./node_modules -cf - .) | (cd "$WORK/proj" && tar -xf -)
AP=$((32000 + RANDOM % 3000)); WP=$((AP + 10))
node "$SRC/tests/mock/gotrue_password_mock.cjs" $AP $WP > "$WORK/mock.log" 2>&1 & MOCK=$!
sleep 1
export XDG_DATA_HOME="$WORK/userdata"   # user:// isolado
(cd "$WORK/proj" && timeout 300 "$GODOT" --headless --import >/dev/null 2>&1)
MOCK_AUTH_PORT=$AP MOCK_WS_PORT=$WP timeout 180 "$GODOT" --headless --path "$WORK/proj" -s tests/account_set_password_test.gd > "$WORK/out.log" 2>&1
RC=$?
grep -E "PASS|FAIL|RESULT|SCRIPT ERROR|Parse Error" "$WORK/out.log"
# a senha de teste não pode aparecer na saída do jogo nem em arquivos do usuário
PW='NovaSenha!2026xyz'
if grep -F -q -- "$PW" "$WORK/out.log"; then echo "FAIL senha apareceu na saída/log do Godot"; RC=1; else echo "PASS senha não aparece na saída/log do Godot"; fi
if grep -rF -q -- "$PW" "$WORK/userdata" 2>/dev/null; then echo "FAIL senha encontrada nos dados do usuário"; RC=1; else echo "PASS senha não está nos dados do usuário (disco)"; fi
exit $RC
