'use strict';
// R175e · NO MÁXIMO UMA TENTATIVA DE CARTÃO ATIVA POR CONTA (migração 0028) no Postgres 16 REAL (migrations 0001–0025 + 0028):
// guarda por conta (card_charge_guard + fraiha_card_attempt_begin, transacional) + índice único parcial como invariante.
// Requisições que chegaram enquanto outra tentativa da conta estava em processamento são RECUSADAS (nunca cobram depois).
// SupabaseStore de verdade sobre um PostgREST mínimo; cada "instância" tem store/conexões próprios.
// Opcional: FRAIHA_PG_TEST=1 e o Postgres de teste em /tmp:55432 (pgtest171.sh com MIGDIR=<repo>/supabase/migrations).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const http = require('http');
const { execFileSync } = require('child_process');
const path = require('path');
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


const M0028 = path.join(__dirname, '../../supabase/migrations/0028_fraiha_pagamento_uma_tentativa_cartao.sql');
const psql = (sql, role) => execFileSync('psql', ['-h', '/tmp', '-p', '55432', '-U', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1', '-c', (role ? `set role ${role}; ` : '') + sql], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim().split('\n').pop();
const psqlFile = f => execFileSync('psql', ['-h', '/tmp', '-p', '55432', '-U', 'postgres', '-q', '-v', 'ON_ERROR_STOP=1', '-f', f], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const fails = fn => { try { fn(); return null; } catch (e) { return String(e.stderr || e.message); } };

async function openOrders(t, inst, ana, products) {
  const refs = [];
  for (const p of products) {
    const n = t.sent.length;
    await inst.handle(ws(ana), { type: 'payment_create', product_id: p, method: 'card' });
    const c = t.sent.slice(n).find(o => o.type === 'payment_charge');
    assert.ok(c, 'pedido ' + p + ' criado'); refs.push(c.charge.id);
  }
  return refs;
}
const cardPay = (inst, uid, ref, tok) => inst.handle(ws(uid), { type: 'payment_card_pay', charge_id: ref, token: tok, payment_method_id: 'visa' });
const results = (t, from) => t.sent.slice(from).filter(o => o.type === 'payment_card_result');
const approvalsOf = (t, refs) => refs.reduce((n, r) => n + t.mp.approvals(r), 0);

test('0028 · aplica e REAPLICA sem erro; compatível com 0023/0025 (funções existentes intactas)', { skip: !ON || !pool }, () => {
  psqlFile(M0028); psqlFile(M0028);
  assert.equal(psql(`select count(*) from pg_indexes where indexname = 'payments_one_card_attempt_per_user'`), '1');
  assert.equal(psql(`select count(*) from pg_proc where proname in ('fraiha_card_attempt_begin','fraiha_card_guard_generation')`), '2');
  assert.equal(psql(`select count(*) from pg_proc where proname in ('fraiha_pay_and_grant','fraiha_founder_reserve','fraiha_founder_taken','fraiha_grant_paid_missing')`), '4');
  assert.equal(psql(`select count(*) from information_schema.columns where table_name = 'matches' and column_name = 'counts_stats'`), '1', '0025 intacta');
});

test('0028 · permissões: anon/authenticated NÃO executam a RPC nem leem a guarda; service_role sim', { skip: !ON || !pool }, () => {
  for (const role of ['anon', 'authenticated']) {
    assert.match(fails(() => psql(`select public.fraiha_card_attempt_begin(gen_random_uuid(), 'mercadopago', 'x', gen_random_uuid()::text, 0::bigint, now())`, role)) || '', /permission denied/);
    assert.match(fails(() => psql(`select public.fraiha_card_guard_generation(gen_random_uuid())`, role)) || '', /permission denied/);
    assert.match(fails(() => psql(`select * from public.card_charge_guard`, role)) || '', /permission denied/);
  }
  assert.equal(psql(`select public.fraiha_card_guard_generation(gen_random_uuid())`, 'service_role'), '0');
  assert.match(psql(`select prosecdef::text || ' ' || array_to_string(proconfig, ',') from pg_proc where proname = 'fraiha_card_attempt_begin'`), /^true search_path=public, pg_temp$/);
});

test('0028 · aborta com mensagem clara se já houver dados violando a regra', { skip: !ON || !pool }, async () => {
  await reset(); const ana = await user();
  psql(`drop index if exists public.payments_one_card_attempt_per_user`);
  for (let i = 0; i < 2; i++) psql(`insert into public.payments(user_id, product_id, method, provider, provider_ref, amount_cents, status, raw) values ('${ana}', 'club_monthly', 'card', 'mercadopago', gen_random_uuid()::text, 1990, 'pending', '{"card_attempt": {"id": "x"}}')`);
  assert.match(fails(() => psqlFile(M0028)) || '', /tentativas de cartão ativas/);
  await reset(); psqlFile(M0028);
  assert.equal(psql(`select count(*) from pg_indexes where indexname = 'payments_one_card_attempt_per_user'`), '1');
});

test('0028 · RPC valida dono, método, estado, id da tentativa e geração (nada vem do cliente)', { skip: !ON || !pool }, async () => {
  await reset(); const ana = await user(), bia = await user();
  const st = newStore();
  const mk = async (uid, method, status = 'pending') => { const ref = crypto.randomUUID(); await q(`insert into public.payments(user_id, product_id, method, provider, provider_ref, amount_cents, status) values ($1,'club_monthly',$2,'mercadopago',$3,1990,$4)`, [uid, method, ref, status]); return ref; };
  const card = await mk(ana, 'card'), pix = await mk(ana, 'pix'), paid = await mk(ana, 'card', 'paid');
  const begin = (uid, ref, seen = 0, att = crypto.randomUUID(), rcv = new Date().toISOString()) => st.cardAttemptBegin({ userId: uid, provider: 'mercadopago', ref, attemptId: att, seenGeneration: seen, receivedAt: rcv });
  assert.equal((await begin(bia, card)).reason, 'order_not_found', 'pedido de outra conta');
  assert.equal((await begin(ana, pix)).reason, 'order_not_card');
  assert.equal((await begin(ana, paid)).reason, 'order_closed');
  assert.equal((await begin(ana, card, 0, 'nao-e-uuid')).reason, 'bad_attempt');
  assert.equal((await begin(ana, card, 7)).reason, 'payment_in_progress', 'geração diferente da atual');
  assert.equal((await begin(ana, card, 0, crypto.randomUUID(), new Date(Date.now() + 60e3).toISOString())).reason, 'payment_in_progress', 'relógio do servidor adiantado: fail closed');
  assert.equal((await begin(ana, card, 0, crypto.randomUUID(), null)).reason, 'payment_in_progress', 'sem horário de recebimento: fail closed');
  const ok = await begin(ana, card, 0);
  assert.equal(ok.ok, true); assert.equal(ok.generation, 1);
  assert.equal(await st.cardGuardGeneration(ana), 1);
  const r = (await q(`select raw from public.payments where provider_ref = $1`, [card]))[0].raw;
  assert.equal(r.card_attempt.state, 'inflight'); assert.equal(r.history.at(-1).event, 'card_attempt_started');
  const card2 = await mk(ana, 'card');
  assert.equal((await begin(ana, card2, 1)).reason, 'previous_attempt_unconfirmed', 'já existe tentativa ativa na conta');
  // a tentativa de "card" termina (recusa confirmada): uma requisição RECEBIDA antes do início dela continua recusada
  // mesmo com a geração certa (leitura de geração atrasada), e uma ação NOVA (recebida > 2 s depois) passa
  await q(`update public.payments set raw = raw || '{"card_attempt": null}'::jsonb where provider_ref = $1`, [card]);
  const antes = new Date(Date.now() - 500).toISOString();
  assert.equal((await begin(ana, card2, 1, crypto.randomUUID(), antes)).reason, 'payment_in_progress', 'recebida antes do início da outra');
  await tick(2100);
  assert.equal((await begin(ana, card2, 1)).ok, true, 'ação nova depois do fim');
});

test('0028 · ÍNDICE impede duas tentativas ativas mesmo contornando a aplicação (UPDATE direto / CAS do store)', { skip: !ON || !pool }, async () => {
  await reset(); const ana = await user();
  const refs = [];
  for (let i = 0; i < 3; i++) { const ref = crypto.randomUUID(); refs.push(ref); await q(`insert into public.payments(user_id, product_id, method, provider, provider_ref, amount_cents, status) values ($1,'club_monthly','card','mercadopago',$2,1990,'pending')`, [ana, ref]); }
  await q(`update public.payments set raw = '{"card_attempt": {"id": "a"}}' where provider_ref = $1`, [refs[0]]);
  await assert.rejects(q(`update public.payments set raw = '{"card_attempt": {"id": "b"}}' where provider_ref = $1`, [refs[1]]), /payments_one_card_attempt_per_user/);
  await assert.rejects(newStore().casPaymentRaw('mercadopago', refs[2], 'pending', 0, { rev: 1, card_attempt: { id: 'c', state: 'inflight' } }), /payments_one_card_attempt_per_user|duplicate/);
  // tentativa em pedido cancelado/vencido continua contando; pedido pago sai do índice
  await q(`update public.payments set status = 'cancelled' where provider_ref = $1`, [refs[0]]);
  await assert.rejects(q(`update public.payments set raw = '{"card_attempt": {"id": "b"}}' where provider_ref = $1`, [refs[1]]), /payments_one_card_attempt_per_user/);
  await q(`update public.payments set status = 'paid' where provider_ref = $1`, [refs[0]]);
  await q(`update public.payments set raw = '{"card_attempt": {"id": "b"}}' where provider_ref = $1`, [refs[1]]);
});

test('ORCA · mesma conta, 2 pedidos Club abertos, 2 instâncias, cartão nos dois AO MESMO TEMPO → 1 POST / ≤1 aprovação (20 rodadas)', { skip: !ON || !pool }, () => world(async t => {
  for (let round = 0; round < 20; round++) {
    await reset(); const ana = await user();
    const i1 = t.boot(), i2 = t.boot();
    const [a, b] = await openOrders(t, i1, ana, ['club_monthly', 'club_yearly']);
    const p0 = t.mp.posts.length, s0 = t.sent.length;
    if (round % 2) t.mp.slowMs = 300;   // metade das rodadas com a cobrança "em voo" (incerta), metade aprovando na hora
    await Promise.all([cardPay(i1, ana, a, 'tokA_' + round + '_xyz'), cardPay(i2, ana, b, 'tokB_' + round + '_xyz')]);
    await tick(round % 2 ? 350 : 0); t.mp.slowMs = 0;
    assert.equal(t.mp.posts.length - p0, 1, 'rodada ' + round);
    assert.ok(approvalsOf(t, [a, b]) <= 1);
    const res = results(t, s0);
    assert.equal(res.length, 2);
    assert.equal(res.filter(r => ['payment_in_progress', 'previous_attempt_unconfirmed', 'previous_payment_confirmed'].includes(r.code)).length, 1, 'o outro recusado pela guarda da conta, sem cobrança');
  }
}));

for (const n of [2, 4]) {
  test(`10 pedidos da mesma conta (Club + Fundador misturados) × ${n} instâncias, simultâneos → 1 POST (aprovação rápida e lenta)`, { skip: !ON || !pool }, () => world(async t => {
    for (const slow of [0, 300]) {
      await reset(); const ana = await user();
      const insts = Array.from({ length: n }, () => t.boot());
      // Fundador: só 1 pedido aberto por vez (regra antiga), o resto Club
      const refs = await openOrders(t, insts[0], ana, ['founder', 'club_monthly', 'club_yearly', 'club_monthly', 'club_yearly', 'club_monthly', 'club_yearly', 'club_monthly', 'club_yearly', 'club_monthly']);
      const p0 = t.mp.posts.length, s0 = t.sent.length;
      t.mp.slowMs = slow;
      await Promise.all(refs.map((r, i) => cardPay(insts[i % n], ana, r, 'tok_' + slow + '_' + i + '_abcdef')));
      await tick(slow ? 350 : 0); t.mp.slowMs = 0;
      assert.equal(t.mp.posts.length - p0, 1, `${n} instâncias, lento=${slow}: ` + results(t, s0).map(r => r.status + ':' + (r.code || '')).join(' '));
      assert.ok(approvalsOf(t, refs) <= 1);
      assert.equal(results(t, s0).length, 10, 'todas responderam');
    }
  }));
}

test('DUAS ABAS (mesma instância, 2 conexões) e DOIS APARELHOS (2 instâncias) → 1 POST', { skip: !ON || !pool }, () => world(async t => {
  await reset(); const ana = await user();
  const pc = t.boot(), cel = t.boot();
  const [a, b, c] = await openOrders(t, pc, ana, ['club_monthly', 'club_yearly', 'club_monthly']);
  const p0 = t.mp.posts.length;
  await Promise.all([cardPay(pc, ana, a, 'tokAba1_123456'), cardPay(pc, ana, b, 'tokAba2_123456'), cardPay(cel, ana, c, 'tokCel_1234567')]);
  assert.equal(t.mp.posts.length - p0, 1);
}));

test('requisições que ESPERAVAM na fila: a 1ª aprova em milissegundos e as antigas continuam RECUSADAS', { skip: !ON || !pool }, () => world(async t => {
  await reset(); const ana = await user();
  const inst = t.boot();
  const refs = await openOrders(t, inst, ana, ['club_monthly', 'club_yearly', 'club_monthly', 'club_yearly']);
  const p0 = t.mp.posts.length, s0 = t.sent.length;
  await Promise.all(refs.map((r, i) => cardPay(inst, ana, r, 'tokFila_' + i + '_abc')));   // A, B, C, D quase juntos
  const res = results(t, s0);
  assert.equal(t.mp.posts.length - p0, 1, 'só A cobrou');
  assert.equal(res.filter(r => r.status === 'approved').length, 1);
  assert.equal(res.filter(r => r.code === 'payment_in_progress').length, 3, 'B, C e D recusados mesmo com A já aprovada');
  // uma NOVA ação depois do fim de A pode cobrar outro pedido
  await tick(2100);
  const s1 = t.sent.length;
  const recusado = res.find(r => r.code === 'payment_in_progress').charge_id;   // um dos pedidos recusados (o vencedor varia)
  await cardPay(inst, ana, recusado, 'tokNova_1234567');
  assert.equal(results(t, s1)[0].status, 'approved', JSON.stringify(results(t, s1)[0]));
  assert.equal(t.mp.posts.length - p0, 2);
}));

test('leitura da geração ATRASADA (requisição antiga lê a geração depois que outra já começou e aprovou) → recusada pelo horário de recebimento', { skip: !ON || !pool }, () => world(async t => {
  for (let round = 0; round < 5; round++) {
    await reset(); const ana = await user();
    const i1 = t.boot(), i2 = t.boot();
    const [a, b] = await openOrders(t, i1, ana, ['club_monthly', 'club_yearly']);
    // i2 recebe B AGORA, mas a leitura da geração atrasa até A (em i1) começar e aprovar
    const origGen = i2.store.cardGuardGeneration.bind(i2.store);
    let release; const gate = new Promise(r => { release = r; });
    i2.store.cardGuardGeneration = async uid => { await gate; return origGen(uid); };
    const p0 = t.mp.posts.length, s0 = t.sent.length;
    const pB = cardPay(i2, ana, b, 'tokB_' + round + '_atrasada');
    await tick(5);
    await cardPay(i1, ana, a, 'tokA_' + round + '_primeira');
    release(); await pB;
    const res = results(t, s0);
    assert.equal(t.mp.posts.length - p0, 1, 'rodada ' + round + ': ' + res.map(r => r.status + ':' + (r.code || '')).join(' '));
    assert.equal(res.find(r => r.charge_id === b).code, 'payment_in_progress');
  }
}));

test('1ª tentativa REJEITADA: as antigas NÃO cobram; uma NOVA solicitação posterior cobra', { skip: !ON || !pool }, () => world(async t => {
  await reset(); const ana = await user();
  const i1 = t.boot(), i2 = t.boot();
  const refs = await openOrders(t, i1, ana, ['club_monthly', 'club_yearly', 'club_monthly']);
  t.mp.cardStatus = 'rejected';
  const p0 = t.mp.posts.length, s0 = t.sent.length;
  await Promise.all(refs.map((r, i) => cardPay(i % 2 ? i2 : i1, ana, r, 'tokRej_' + i + '_abc')));
  assert.equal(t.mp.posts.length - p0, 1);
  const res = results(t, s0);
  assert.equal(res.filter(r => r.status === 'rejected').length, 1);
  assert.equal(res.filter(r => ['payment_in_progress', 'previous_attempt_unconfirmed'].includes(r.code)).length, 2);
  t.mp.cardStatus = 'approved';
  await tick(2100);
  const s1 = t.sent.length;
  const recusado = res.find(r => ['payment_in_progress', 'previous_attempt_unconfirmed'].includes(r.code)).charge_id;
  await cardPay(i2, ana, recusado, 'tokDepois_123456');   // ação NOVA
  assert.equal(results(t, s1)[0].status, 'approved');
  assert.equal(t.mp.posts.length - p0, 2); assert.equal(approvalsOf(t, refs), 1);
}));

test('tentativa INCERTA: bloqueia a conta; REINÍCIO continua seguro; nada cobra até a confirmação', { skip: !ON || !pool }, () => world(async t => {
  await reset(); const ana = await user();
  let inst = t.boot();
  const refs = await openOrders(t, inst, ana, ['club_monthly', 'club_yearly', 'founder']);
  t.mp.slowMs = 450;
  await cardPay(inst, ana, refs[0], 'tokIncerto_12345');
  await tick(500); t.mp.slowMs = 0; t.mp.searchMode = 'empty';
  for (let k = 0; k < 3; k++) {
    inst = t.boot();   // reinício
    const s0 = t.sent.length;
    await Promise.all([cardPay(inst, ana, refs[1], 'tokX_' + k + '_abcde'), cardPay(t.boot(), ana, refs[2], 'tokY_' + k + '_abcde')]);
    assert.ok(results(t, s0).every(r => r.code === 'previous_attempt_unconfirmed' || r.code === 'payment_unconfirmed'), results(t, s0).map(r => r.code).join(','));
  }
  assert.equal(t.mp.posts.length, 1); assert.equal(approvalsOf(t, refs), 1);
  t.mp.searchMode = 'ok';
  const s1 = t.sent.length;
  await cardPay(t.boot(), ana, refs[0], 'tokFim_1234567');
  assert.equal(results(t, s1)[0].status, 'approved', 'a aprovação antiga é entregue sem cobrar');
  assert.equal(t.mp.posts.length, 1);
}));

test('10 contas DIFERENTES pagando ao mesmo tempo em 4 instâncias → 10 POSTs (uma por conta)', { skip: !ON || !pool }, () => world(async t => {
  await reset();
  const insts = [t.boot(), t.boot(), t.boot(), t.boot()];
  const jobs = [];
  for (let i = 0; i < 10; i++) {
    const u = await user();
    const [r] = await openOrders(t, insts[0], u, ['club_monthly']);
    jobs.push(() => cardPay(insts[i % 4], u, r, 'tokConta_' + i + '_abc'));
  }
  const p0 = t.mp.posts.length, s0 = t.sent.length;
  await Promise.all(jobs.map(j => j()));
  assert.equal(t.mp.posts.length - p0, 10);
  assert.equal(results(t, s0).filter(r => r.status === 'approved').length, 10);
}));

test.after(async () => { if (pool) await pool.end(); });
