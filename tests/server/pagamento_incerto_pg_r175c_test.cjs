'use strict';
// R175c · tentativa de cartão INCERTA persistente no Postgres 16 REAL (migrations 0001–0025, sem migration nova):
// SupabaseStore de verdade sobre um PostgREST mínimo (mesmos filtros, inclusive raw->>rev / raw->rev) ligado ao banco.
// Cada "instância do servidor" tem o seu próprio store/conexões: reinício e duas instâncias são reais do ponto de vista do banco.
// Opcional: roda só com FRAIHA_PG_TEST=1 e o Postgres de teste em /tmp:55432 (pgtest171.sh com MIGDIR=<repo>/supabase/migrations).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const http = require('http');
const ON = process.env.FRAIHA_PG_TEST === '1';
const { SupabaseStore } = require('../../online_v021/accounts/store');
const { Payments } = require('../../online_v021/payments/service');
const { MercadoPago } = require('../../online_v021/payments/providers/mercadopago');
let Pool; try { ({ Pool } = require('pg')); } catch { Pool = null; }
const pool = ON && Pool ? new Pool({ host: '/tmp', port: 55432, user: 'postgres', database: 'postgres', max: 16 }) : null;
const tick = (ms = 0) => new Promise(r => setTimeout(r, ms));

// ---- PostgREST mínimo: /tabela?col=eq.v&col=in.(a,b)&col=gt.v&select=...&order=col.desc&limit=n ; /rpc/fn ----
const IDENT = /^[a-z_][a-z0-9_]*$/;
function parse(path) {
  const u = new URL('http://x' + path);
  const parts = u.pathname.split('/').filter(Boolean);
  return { parts, params: [...u.searchParams.entries()] };
}
async function postgrest(path, opts = {}) {
  const method = (opts.method || 'GET').toUpperCase();
  const { parts, params } = parse(path);
  const body = opts.body ? JSON.parse(opts.body) : null;
  try {
    if (parts[0] === 'rpc') {
      const fn = parts[1]; if (!IDENT.test(fn)) throw new Error('fn');
      const keys = Object.keys(body || {});
      const vals = keys.map(k => (body[k] !== null && typeof body[k] === 'object') ? JSON.stringify(body[k]) : body[k]);
      const sql = `select public.${fn}(${keys.map((k, i) => `${k} => $${i + 1}`).join(', ')}) as v`;
      const r = await pool.query(sql, vals);
      return ok(r.rows[0] ? r.rows[0].v : null);
    }
    const table = parts[0]; if (!IDENT.test(table)) throw new Error('table');
    let select = '*', order = '', limit = '';
    const where = [], args = [];
    for (const [k, v] of params) {
      if (k === 'select') { select = v.split(',').map(c => { if (c !== '*' && !IDENT.test(c)) throw new Error('col'); return c; }).join(', '); continue; }
      if (k === 'order') { const [c, d] = v.split('.'); if (!IDENT.test(c)) throw new Error('order'); order = ` order by ${c} ${d === 'desc' ? 'desc' : 'asc'}`; continue; }
      if (k === 'limit') { limit = ' limit ' + (Number(v) | 0); continue; }
      if (k === 'on_conflict') continue;
      // coluna ou caminho JSON (col->chave / col->>chave), como o PostgREST (R175c: versão do raw)
      const jm = k.match(/^([a-z_][a-z0-9_]*)(->>?)([a-z_][a-z0-9_]*)$/);
      if (!IDENT.test(k) && !jm) throw new Error('filtro');
      const col = jm ? `${jm[1]}${jm[2]}'${jm[3]}'` : k;
      const i = v.indexOf('.'); const op = v.slice(0, i), val = v.slice(i + 1);
      if (op === 'eq') { args.push(val); where.push(`(${col})::text = $${args.length}`); }
      else if (op === 'gt') { args.push(val); where.push(`${col} > $${args.length}`); }
      else if (op === 'in') { args.push(val.replace(/^\(|\)$/g, '').split(',')); where.push(`(${col})::text = any($${args.length}::text[])`); }
      else if (op === 'is' && val === 'null') where.push(`${col} is null`);
      else if (op === 'not' && val === 'is.null') where.push(`${col} is not null`);
      else throw new Error('op ' + op);
    }
    const w = where.length ? ' where ' + where.join(' and ') : '';
    if (method === 'GET') return ok((await pool.query(`select ${select} from public.${table}${w}${order}${limit}`, args)).rows);
    if (method === 'PATCH') {
      const sets = Object.keys(body).map(c => { if (!IDENT.test(c)) throw new Error('col'); args.push(body[c] !== null && typeof body[c] === 'object' ? JSON.stringify(body[c]) : body[c]); return `${c} = $${args.length}`; });
      const ret = /return=representation/.test(JSON.stringify(opts.headers || {})) ? ` returning ${select}` : '';
      return ok((await pool.query(`update public.${table} set ${sets.join(', ')}${w}${ret}`, args)).rows);
    }
    if (method === 'POST') {
      const cols = Object.keys(body); cols.forEach(c => { if (!IDENT.test(c)) throw new Error('col'); });
      const vals = cols.map(c => body[c] !== null && typeof body[c] === 'object' ? JSON.stringify(body[c]) : body[c]);
      return ok((await pool.query(`insert into public.${table} (${cols.join(', ')}) values (${cols.map((_, i) => '$' + (i + 1)).join(', ')}) returning *`, vals)).rows);
    }
    throw new Error('método');
  } catch (e) {
    return { ok: false, status: 400, text: async () => JSON.stringify({ code: e.code || 'XX', message: e.message }) };
  }
}
const ok = v => ({ ok: true, status: 200, text: async () => JSON.stringify(v) });
const newStore = () => new SupabaseStore({ url: 'http://pg.local', serviceKey: 'sb_secret_test', fetchImpl: (url, opts) => postgrest(url.replace('http://pg.local/rest/v1', ''), opts) });


function fakeMP() {
  const mp = { payments: new Map(), nextId: 80000, posts: [], searchMode: 'ok', cardStatus: 'approved', slowMs: 0 };
  const json = (res, code, body) => { if (!res.writableEnded) { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); } };
  mp.srv = http.createServer((req, res) => {
    let raw = ''; req.on('data', d => raw += d);
    req.on('end', async () => {
      const body = raw ? JSON.parse(raw) : {};
      if (req.method === 'POST' && req.url === '/v1/payments') {
        mp.posts.push({ token: body.token, attempt: body.metadata && body.metadata.fraiha_attempt });
        const id = mp.nextId++;
        const p = { id, status: mp.cardStatus, transaction_amount: body.transaction_amount, currency_id: 'BRL', external_reference: body.external_reference, metadata: body.metadata || {} };
        mp.payments.set(String(id), p);
        if (mp.slowMs) await tick(mp.slowMs);
        return json(res, 201, p);
      }
      if (req.method === 'POST' && req.url === '/checkout/preferences') return json(res, 201, { id: 'pref', init_point: 'https://mp.test/c' });
      if (req.method === 'GET' && req.url.startsWith('/v1/payments/search')) {
        if (mp.searchMode === 'empty') return json(res, 200, { results: [] });
        const ref = new URL(req.url, 'http://x').searchParams.get('external_reference');
        return json(res, 200, { results: [...mp.payments.values()].filter(p => p.external_reference === ref).reverse() });
      }
      json(res, 404, {});
    });
  });
  mp.approvals = ref => [...mp.payments.values()].filter(p => p.external_reference === ref && p.status === 'approved').length;
  return mp;
}
async function q(sql, args) { return (await pool.query(sql, args)).rows; }
async function reset() {
  await q(`truncate public.payments, public.entitlements cascade`);
  await q(`delete from public.profiles where nickname like 'fx_%'`);
  await q(`update public.founder_capacity set seat_limit = 5, configured = true`);
}
async function user() {
  const id = crypto.randomUUID();
  await q(`insert into auth.users(id) values ($1)`, [id]);
  await q(`insert into public.profiles(user_id, nickname) values ($1, $2)`, [id, 'fx_' + id.slice(0, 8)]);
  return id;
}
async function world(fn) {
  const mp = fakeMP();
  await new Promise(r => mp.srv.listen(0, '127.0.0.1', r));
  const keep = { e: console.error, l: console.log, w: console.warn }; console.error = () => {}; console.log = () => {}; console.warn = () => {};
  const sent = [];
  const boot = () => {   // instância NOVA: store próprio (conexões próprias), memória zerada
    const store = newStore();
    const pay = new Payments({ send: (ws, o) => sent.push({ to: ws.uid, ...o }), backend: { store, socketsOf: uid => [{ uid }], state: async () => {} },
      env: { FRAIHA_PAYMENT_PROVIDER: '', FRAIHA_FOUNDER_LIMIT: '5', FRAIHA_FOUNDER_CAPACITY_WAIT_MS: '10000' } });
    pay.provider = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'T', FRAIHA_PUBLIC_URL: 'https://srv.test', FRAIHA_MP_API: 'http://127.0.0.1:' + mp.srv.address().port, FRAIHA_MP_PUBLIC_KEY: 'PK', FRAIHA_MP_TIMEOUT_MS: '150' });
    return pay;
  };
  const last = type => [...sent].reverse().find(o => o.type === type);
  try { await fn({ mp, boot, last, sent }); }
  finally { console.error = keep.e; console.log = keep.l; console.warn = keep.w; mp.srv.closeAllConnections && mp.srv.closeAllConnections(); mp.srv.close(); }
}
const ws = id => ({ uid: id, user: { id, email: 'x@x.dev' }, profile: { nickname: 'x' } });
const row = async ref => (await q(`select status, raw from public.payments where provider_ref = $1`, [ref]))[0];

test('PG · SONDA ORCA: aceito + resposta perdida + REINÍCIO + busca vazia + token novo → 1 POST / 1 aprovação', { skip: !ON || !pool }, () => world(async t => {
  await reset();
  const ana = await user();
  let pay = t.boot();
  await pay.handle(ws(ana), { type: 'payment_create', product_id: 'founder', method: 'card' });
  const ref = t.last('payment_charge').charge.id;
  t.mp.slowMs = 450;
  await pay.handle(ws(ana), { type: 'payment_card_pay', charge_id: ref, token: 'tokenUM_123456', payment_method_id: 'visa' });
  await tick(500); t.mp.slowMs = 0;
  assert.equal(t.last('payment_card_result').code, 'payment_unconfirmed');
  let r = await row(ref);
  assert.equal(r.raw.card_attempt.state, 'uncertain', 'gravado NO BANCO');
  assert.ok(r.raw.rev >= 2, 'versão do raw avançou');
  t.mp.searchMode = 'empty';
  for (let i = 0; i < 3; i++) {
    pay = t.boot();   // reinício
    await pay.handle(ws(ana), { type: 'payment_card_pay', charge_id: ref, token: 'tokenNOVO_' + i + '_12345', payment_method_id: 'visa' });
    assert.equal(t.last('payment_card_result').code, 'payment_unconfirmed');
  }
  assert.equal(t.mp.posts.length, 1); assert.equal(t.mp.approvals(ref), 1);
  t.mp.searchMode = 'ok';
  pay = t.boot();
  await pay.handle(ws(ana), { type: 'payment_card_pay', charge_id: ref, token: 'tokenFINAL_123456', payment_method_id: 'visa' });
  assert.equal(t.last('payment_card_result').status, 'approved');
  assert.equal(t.mp.posts.length, 1); assert.equal(t.mp.approvals(ref), 1);
  r = await row(ref);
  assert.equal(r.status, 'paid');
  assert.equal(Number((await q(`select count(*)::int n from public.entitlements where is_founder`))[0].n), 1);
}));

test('PG · DUAS INSTÂNCIAS (conexões separadas) ao mesmo tempo → 1 tentativa gravada, 1 POST', { skip: !ON || !pool }, () => world(async t => {
  for (let round = 0; round < 5; round++) {
    await reset();
    const ana = await user();
    const a = t.boot();
    await a.handle(ws(ana), { type: 'payment_create', product_id: 'club_monthly', method: 'card' });
    const ref = t.last('payment_charge').charge.id;
    const inst = [a, t.boot(), t.boot(), t.boot()];
    const before = t.mp.posts.length;
    await Promise.all(inst.map((p, i) => p.handle(ws(ana), { type: 'payment_card_pay', charge_id: ref, token: 'tok_' + round + '_' + i + '_abcdef', payment_method_id: 'visa' })));
    assert.equal(t.mp.posts.length - before, 1, 'rodada ' + round);
    assert.equal(t.mp.approvals(ref), 1);
    assert.equal((await row(ref)).status, 'paid');
  }
}));

test('PG · compare-and-set do raw: 8 conexões gravando a tentativa com a mesma versão → só 1', { skip: !ON || !pool }, async () => {
  await reset();
  const ana = await user();
  const ref = crypto.randomUUID();
  await q(`insert into public.payments(user_id, product_id, method, provider, provider_ref, amount_cents, status) values ($1, 'club_monthly', 'card', 'mercadopago', $2, 1990, 'pending')`, [ana, ref]);
  const res = await Promise.all(Array.from({ length: 8 }, (_, i) => newStore().casPaymentRaw('mercadopago', ref, 'pending', 0, { rev: 1, card_attempt: { id: 'att-' + i, state: 'inflight' } })));
  assert.equal(res.filter(Boolean).length, 1);
  const r = await row(ref);
  assert.equal(r.raw.rev, 1);
  // cancelar com versão velha não apaga a tentativa: o cancelamento relê e grava por cima com rev+1
  const c = await newStore().cancelPayment('mercadopago', ref, { reason: 'user' });
  assert.ok(c);
  const r2 = await row(ref);
  assert.equal(r2.status, 'cancelled'); assert.equal(r2.raw.rev, 2); assert.ok(r2.raw.card_attempt, 'tentativa preservada no histórico do pedido');
});

test('PG · R175d: A incerto + 30 min (vencido no banco) + reinício + 3 instâncias criando pedido B → nenhum B; aprovação antiga depois → A entregue, 1 aprovação', { skip: !ON || !pool }, () => world(async t => {
  await reset();
  const ana = await user();
  let pay = t.boot();
  await pay.handle(ws(ana), { type: 'payment_create', product_id: 'club_monthly', method: 'card' });
  const a = t.last('payment_charge').charge.id;
  t.mp.slowMs = 450;
  await pay.handle(ws(ana), { type: 'payment_card_pay', charge_id: a, token: 'tokenUM_123456', payment_method_id: 'visa' });
  await tick(500); t.mp.slowMs = 0;
  t.mp.searchMode = 'empty';
  await q(`update public.payments set created_at = now() - interval '45 minutes' where provider_ref = $1`, [a]);   // venceu
  const insts = [t.boot(), t.boot(), t.boot()];
  await Promise.all(insts.map(p => p.handle(ws(ana), { type: 'payment_create', product_id: 'club_yearly', method: 'card' })));
  assert.equal(t.sent.filter(o => o.type === 'payment_error' && o.code === 'previous_attempt_unconfirmed').length, 3);
  assert.equal(Number((await q(`select count(*)::int n from public.payments where user_id = $1`, [ana]))[0].n), 1, 'nenhum pedido B');
  assert.equal((await row(a)).raw.card_attempt.state, 'uncertain');
  t.mp.searchMode = 'ok';
  pay = t.boot();
  await pay.handle(ws(ana), { type: 'payment_create', product_id: 'club_yearly', method: 'card' });
  assert.equal(t.last('payment_error').code, 'previous_payment_confirmed');
  assert.equal((await row(a)).status, 'paid', 'A entregue');
  assert.equal(t.mp.approvals(a), 1); assert.equal(t.mp.posts.length, 1);
}));

test('PG · R175d: rejeição antiga confirmada libera pedido B (compare-and-set no pedido vencido)', { skip: !ON || !pool }, () => world(async t => {
  await reset();
  const ana = await user();
  let pay = t.boot();
  await pay.handle(ws(ana), { type: 'payment_create', product_id: 'club_monthly', method: 'card' });
  const a = t.last('payment_charge').charge.id;
  t.mp.cardStatus = 'rejected'; t.mp.slowMs = 450;
  await pay.handle(ws(ana), { type: 'payment_card_pay', charge_id: a, token: 'tokenUM_123456', payment_method_id: 'visa' });
  await tick(500); t.mp.slowMs = 0; t.mp.cardStatus = 'approved';
  await q(`update public.payments set created_at = now() - interval '45 minutes' where provider_ref = $1`, [a]);
  pay = t.boot();
  const before = t.sent.length;
  await Promise.all([t.boot(), t.boot()].map(p => p.handle(ws(ana), { type: 'payment_create', product_id: 'club_yearly', method: 'card' })));
  const charges = t.sent.slice(before).filter(o => o.type === 'payment_charge');
  assert.ok(charges.length >= 1, 'liberado depois da confirmação da recusa');
  assert.equal((await row(a)).raw.card_attempt, null);
  const b = charges[0].charge.id;
  await pay.handle(ws(ana), { type: 'payment_card_pay', charge_id: b, token: 'tokenB_7654321', payment_method_id: 'visa' });
  assert.equal(t.last('payment_card_result').status, 'approved');
  assert.equal(t.mp.approvals(a), 0); assert.equal(t.mp.approvals(b), 1);
}));

test.after(async () => { if (pool) await pool.end(); });
