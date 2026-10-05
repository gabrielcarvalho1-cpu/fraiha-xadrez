'use strict';
// R42 · Integração do hardening de sessão: uma resposta produzida durante a revalidação de
// rotina (a cada 60 s) espera a revalidação. Sessão válida → entrega; sessão revogada → descarta.
// Caso real: pagamento com cartão esperando o Mercado Pago enquanto a revalidação acontece.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');

const U = '11111111-1111-4111-a111-111111111111';
const def = () => { let r; const p = new Promise(x => { r = x; }); return { p, r }; };
const tick = () => new Promise(r => setTimeout(r, 20));

async function setup() {
  let t = 1_000_000;
  const out = [];
  const b = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, now: () => t, send: (ws, m) => out.push(m) });
  const ctl = { slow: null };
  b.auth = { verify: async (tok, o) => (o && o.force && ctl.slow) ? ctl.slow.p : { id: U, email: 'a@x', provider: 'dev' } };
  await b.store.createProfile(U, 'Probe', 'warrior');
  const ws = { readyState: 1 };
  await b.handle(ws, { type: 'acct_auth', access_token: 'x'.repeat(30) });
  out.length = 0;
  const gate = def();
  b.payments.handle = async w => { await gate.p; b.send(w, { type: 'payment_card_result', status: 'approved' }); };
  const stop = () => { clearInterval(b.sweeper); if (b.presence.stop) b.presence.stop(); };
  return { b, ws, out, gate, ctl, stop, advance: ms => { t += ms; } };
}

test('resposta durante revalidação de rotina: entregue depois que a sessão é confirmada', async () => {
  const { b, ws, out, gate, ctl, stop, advance } = await setup();
  const p = b.handle(ws, { type: 'payment_card_pay' });
  advance(61_000); ctl.slow = def();
  const ens = b.ensureSession(ws);
  gate.r(); await p;
  assert.deepEqual(out.map(m => m.type), [], 'ainda não entrega enquanto a validade é desconhecida');
  ctl.slow.r({ id: U, email: 'a@x', provider: 'dev' }); await ens; await tick();
  assert.deepEqual(out.map(m => m.type), ['payment_card_result'], 'entregue (não descartada) após revalidar');
  stop();
});

test('resposta durante revalidação: sessão revogada → não entrega, só o aviso de sessão inválida', async () => {
  const { b, ws, out, gate, ctl, stop, advance } = await setup();
  const p = b.handle(ws, { type: 'payment_card_pay' });
  advance(61_000); ctl.slow = def();
  const ens = b.ensureSession(ws);
  gate.r(); await p;
  ctl.slow.r(null); await ens; await tick();
  assert.ok(!out.some(m => m.type === 'payment_card_result'), 'resultado não vai para sessão revogada');
  assert.ok(out.some(m => m.code === 'invalid_token'), 'cliente recebe invalid_token para renovar');
  assert.equal(ws.user, null);
  stop();
});

test('resposta sem revalidação pendente: entrega imediata (sem mudança de comportamento)', async () => {
  const { b, ws, out, gate, stop } = await setup();
  const p = b.handle(ws, { type: 'payment_card_pay' });
  gate.r(); await p;
  assert.deepEqual(out.map(m => m.type), ['payment_card_result']);
  stop();
});
