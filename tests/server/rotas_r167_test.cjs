'use strict';
// R167 · o servidor de verdade (server.js) entrega ao backend as mensagens de Coroas, Loja, Passe, Torneios e Criadores.
// Antes elas caíam na sala antiga ("Crie ou entre em uma sala primeiro.") e as telas ficavam em "Abrindo…" para sempre.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');
test('server.js roteia crowns_/store_/pass_/tourn_/tev_/creator_ para o backend', async t => {
  const port = 30000 + Math.floor(Math.random() * 5000);
  const srv = spawn(process.execPath, [path.join(__dirname, '../../online_v021/server.js')], { env: { ...process.env, PORT: String(port), FRAIHA_DEV_AUTH: '1' }, stdio: 'ignore' });
  t.after(() => srv.kill());
  await new Promise(r => setTimeout(r, 1200));
  const ws = new WebSocket('ws://127.0.0.1:' + port);
  const got = [];
  ws.on('message', d => got.push(JSON.parse(d)));
  await new Promise(r => ws.on('open', r));
  ws.send(JSON.stringify({ type: 'guest_auth', token: '' }));
  await new Promise(r => setTimeout(r, 300));
  for (const type of ['crowns_get', 'store_get', 'pass_get', 'tourn_get', 'tev_list', 'creator_get']) ws.send(JSON.stringify({ type }));
  await new Promise(r => setTimeout(r, 800));
  ws.close();
  assert.ok(!got.some(m => m.type === 'error' && /sala/.test(m.message || '')), 'nada cai na sala antiga: ' + JSON.stringify(got.filter(m => m.type === 'error')));
  for (const want of ['crowns_state', 'store_error', 'pass_state', 'tourn_state', 'tev_error', 'creator_state']) assert.ok(got.some(m => m.type === want), want + ' respondido');
});
