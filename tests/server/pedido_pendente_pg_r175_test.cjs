'use strict';
// R175 · PEDIDO PENDENTE no Postgres 16 REAL (migrations 0001–0025, sem migration nova): o SupabaseStore de verdade
// fala com um PostgREST mínimo (mesmas URLs/filtros/PATCH condicional) ligado ao banco. Confere o compare-and-set
// do cancelamento e da reabertura, o raw preservado, a liberação da reserva do Fundador e que o pagamento tardio
// passa pela fraiha_pay_and_grant da 0023 (com vaga: entrega 1 vez; sem vaga: sold_out). Várias conexões ao mesmo tempo.
// Opcional: roda só com FRAIHA_PG_TEST=1 e o Postgres de teste em /tmp:55432 (pgtest171.sh com MIGDIR=<repo>/supabase/migrations).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const ON = process.env.FRAIHA_PG_TEST === '1';
const { SupabaseStore } = require('../../online_v021/accounts/store');
const { Payments } = require('../../online_v021/payments/service');

let Pool; try { ({ Pool } = require('pg')); } catch { Pool = null; }
const pool = ON && Pool ? new Pool({ host: '/tmp', port: 55432, user: 'postgres', database: 'postgres', max: 12 }) : null;
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
      if (!IDENT.test(k)) throw new Error('filtro');
      const i = v.indexOf('.'); const op = v.slice(0, i), val = v.slice(i + 1);
      if (op === 'eq') { args.push(val); where.push(`${k}::text = $${args.length}`); }
      else if (op === 'gt') { args.push(val); where.push(`${k} > $${args.length}`); }
      else if (op === 'in') { args.push(val.replace(/^\(|\)$/g, '').split(',')); where.push(`${k}::text = any($${args.length}::text[])`); }
      else if (op === 'is' && val === 'null') where.push(`${k} is null`);
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

// ---- Mercado Pago falso (mesmo contrato do provedor) ----
function fakeMP() {
  const mp = { pays: new Map(), calls: [], nextId: 7000 };
  const MAP = { approved: 'paid', pending: 'pending', rejected: 'failed', cancelled: 'cancelled', refunded: 'refunded' };
  const ev = p => ({ providerRef: p.ref, status: MAP[p.status], amountCents: p.amount, currency: 'BRL', providerPaymentId: String(p.id), detail: p.detail || '' });
  const latest = ref => { const l = [...mp.pays.values()].filter(p => p.ref === ref).reverse(); return l.find(p => p.status === 'approved') || l[0] || null; };
  mp.provider = { name: 'mercadopago', ready: () => true,
    async createCharge({ ref, method, amountCents }) { mp.calls.push('create'); if (method === 'pix') { const id = mp.nextId++; mp.pays.set(id, { id, ref, status: 'pending', amount: amountCents }); return { id: ref, method: 'pix', copy_paste: 'QR' + id, expires_at: new Date(Date.now() + 18e5).toISOString() }; } return { id: ref, method: 'card', public_key: 'PK' }; },
    async findByRef(ref) { await tick(1); const p = latest(ref); return p ? ev(p) : null; },
    async resumePix(ref) { const p = latest(ref); return p && p.status === 'pending' ? { event: ev(p), charge: { id: ref, method: 'pix', copy_paste: 'QR' + p.id } } : (p ? { event: ev(p) } : null); },
    async cancel(id) { await tick(1); const p = mp.pays.get(Number(id)); if (p.status === 'approved') { const e = new Error('400'); e.status = 400; throw e; } p.status = 'cancelled'; return ev(p); },
    async payCard({ ref, amountCents }) { const id = mp.nextId++; const p = { id, ref, status: 'approved', amount: amountCents }; mp.pays.set(id, p); return ev(p); },
    async refund(id) { mp.calls.push('refund'); } };
  mp.approve = ref => { const p = [...mp.pays.values()].reverse().find(x => x.ref === ref); if (p) { p.status = 'approved'; return ev(p); } const id = mp.nextId++; const n = { id, ref, status: 'approved', amount: 4990 }; mp.pays.set(id, n); return ev(n); };
  return mp;
}

async function q(sql, args) { return (await pool.query(sql, args)).rows; }
async function reset(limit) {
  await q(`truncate public.payments, public.entitlements cascade`);
  await q(`delete from public.profiles where nickname like 'fx_%'`);
  await q(`update public.founder_capacity set seat_limit = $1, configured = true`, [limit]);
}
async function user() {
  const id = crypto.randomUUID();
  await q(`insert into auth.users(id) values ($1)`, [id]);
  await q(`insert into public.profiles(user_id, nickname) values ($1, $2)`, [id, 'fx_' + id.slice(0, 8)]);
  return id;
}
function service(limit, env = {}) {
  const store = newStore(); const sent = [];
  const keep = { e: console.error, l: console.log, w: console.warn }; console.error = () => {}; console.log = () => {}; console.warn = () => {};
  const pay = new Payments({ send: (ws, o) => sent.push({ to: ws.uid, ...o }), backend: { store, socketsOf: uid => [{ uid }], state: async () => {} },
    env: { FRAIHA_PAYMENT_PROVIDER: '', FRAIHA_FOUNDER_LIMIT: String(limit), FRAIHA_FOUNDER_CAPACITY_WAIT_MS: '10000', ...env } });
  const mp = fakeMP(); pay.provider = mp.provider;
  const ws = id => ({ uid: id, user: { id, email: 'x@x.dev' }, profile: { nickname: 'x' } });
  const last = (to, type) => [...sent].reverse().find(o => o.to === to && o.type === type);
  return { store, pay, mp, ws, last, sent, restore: () => { console.error = keep.e; console.log = keep.l; console.warn = keep.w; } };
}
const row = async ref => (await q(`select status, seat_hold_until, raw, granted_at from public.payments where provider_ref = $1`, [ref]))[0];
const founders = async () => Number((await q(`select count(*)::int as n from public.entitlements where is_founder`))[0].n);
const taken = async () => Number((await q(`select public.fraiha_founder_taken(null) as n`))[0].n);

test('PG: cancelar (CAS) libera a vaga e grava o motivo; pago depois COM vaga → mesmo pedido reaberto e entregue 1 vez', { skip: !ON || !pool }, async () => {
  await reset(2);
  const t = service(2);
  try {
    const ana = await user();
    await t.pay.handle(t.ws(ana), { type: 'payment_create', product_id: 'founder', method: 'pix' });
    const ref = t.last(ana, 'payment_charge').charge.id;
    assert.equal(await taken(), 1, 'reserva viva');
    await t.pay.handle(t.ws(ana), { type: 'payment_cancel', charge_id: ref });
    assert.equal(t.last(ana, 'payment_cancel_result').status, 'cancelled');
    let r = await row(ref);
    assert.equal(r.status, 'cancelled'); assert.equal(r.seat_hold_until, null); assert.equal(r.raw.cancel.reason, 'user');
    assert.equal(await taken(), 0, 'vaga liberada no banco');
    // aprovado depois (cartão pago na página do MP), avisos repetidos e simultâneos
    const ev = t.mp.approve(ref);
    await Promise.all(Array.from({ length: 6 }, () => t.pay.apply(ev)));
    r = await row(ref);
    assert.equal(r.status, 'paid'); assert.ok(r.granted_at);
    assert.equal(r.raw.cancel.reason, 'user', 'cancelamento preservado');
    assert.equal(r.raw.reopened.length, 1);
    assert.deepEqual(r.raw.history.map(h => h.event), ['cancelled', 'provider_approved_after_cancelled']);
    assert.equal(await founders(), 1);
    assert.equal(Number((await q(`select count(*)::int n from public.payments`))[0].n), 1, 'nenhum pedido novo');
    await t.pay.handle(t.ws(ana), { type: 'payment_history' });
    const it = t.last(ana, 'payment_history').items[0];
    assert.equal(it.state, 'paid'); assert.equal(it.paid_after_cancel, true);
  } finally { t.restore(); }
});

test('PG: pago depois de cancelado SEM vaga → sold_out pela 0023 (nada entregue, limite respeitado)', { skip: !ON || !pool }, async () => {
  await reset(1);
  const t = service(1);
  try {
    const ana = await user(), bia = await user();
    await t.pay.handle(t.ws(ana), { type: 'payment_create', product_id: 'founder', method: 'pix' });
    const refA = t.last(ana, 'payment_charge').charge.id;
    await t.pay.handle(t.ws(ana), { type: 'payment_cancel', charge_id: refA });
    await t.pay.handle(t.ws(bia), { type: 'payment_create', product_id: 'founder', method: 'pix' });
    const refB = t.last(bia, 'payment_charge').charge.id;
    await t.pay.apply(t.mp.approve(refB));
    const evA = t.mp.approve(refA);
    await Promise.all([t.pay.apply(evA), t.pay.apply(evA)]);
    const r = await row(refA);
    assert.equal(r.status, 'sold_out'); assert.equal(r.raw.cancel.reason, 'user');
    assert.equal(await founders(), 1);
    assert.equal(Number((await q(`select count(*)::int n from public.payments where status = 'pending'`))[0].n), 0);
  } finally { t.restore(); }
});

test('PG: compare-and-set com várias conexões (sem a fila do processo): 8 cancelamentos → 1; 8 reaberturas → 1; 8 entregas → 1', { skip: !ON || !pool }, async () => {
  await reset(3);
  const ana = await user();
  const ref = crypto.randomUUID();
  await q(`insert into public.payments(user_id, product_id, method, provider, provider_ref, amount_cents, status, seat_hold_until)
           values ($1, 'founder', 'pix', 'mercadopago', $2, 4490, 'pending', now() + interval '20 minutes')`, [ana, ref]);
  const stores = Array.from({ length: 8 }, newStore);
  const c = await Promise.all(stores.map(s => s.cancelPayment('mercadopago', ref, { reason: 'user', by: ana })));
  assert.equal(c.filter(Boolean).length, 1, 'um cancelamento');
  const re = await Promise.all(stores.map(s => s.reopenPayment('mercadopago', ref, { event: 'provider_approved_after_cancelled', provider_payment_id: '1' })));
  assert.equal(re.filter(Boolean).length, 1, 'uma reabertura');
  const pg = await Promise.all(stores.map(s => s.payAndGrant('mercadopago', ref, 'mercadopago')));
  assert.equal(pg.filter(x => x && x.status === 'paid').length, 1, 'uma entrega');
  const r = await row(ref);
  assert.equal(r.status, 'paid'); assert.equal(await founders(), 1);
  assert.equal(r.raw.history.filter(h => h.event === 'cancelled').length, 1);
});

test('PG: pagamento chegando durante o cancelamento (várias rodadas) → pago e entregue 1 vez, nunca perdido', { skip: !ON || !pool }, async () => {
  for (let i = 0; i < 8; i++) {
    await reset(5);
    const t = service(5);
    try {
      const ana = await user();
      await t.pay.handle(t.ws(ana), { type: 'payment_create', product_id: 'founder', method: 'pix' });
      const ref = t.last(ana, 'payment_charge').charge.id;
      const ev = t.mp.approve(ref);
      const jobs = [() => t.pay.handle(t.ws(ana), { type: 'payment_cancel', charge_id: ref }), () => t.pay.apply(ev), () => t.pay.apply(ev)];
      if (i % 2) jobs.reverse();
      await Promise.all(jobs.map(j => j()));
      const r = await row(ref);
      assert.equal(r.status, 'paid', 'rodada ' + i);
      assert.equal(await founders(), 1);
    } finally { t.restore(); }
  }
});

test('PG: CONTINUAR não cria pedido nem reserva nova; reserva original preservada', { skip: !ON || !pool }, async () => {
  await reset(1);
  const t = service(1);
  try {
    const ana = await user();
    await t.pay.handle(t.ws(ana), { type: 'payment_create', product_id: 'founder', method: 'pix' });
    const ref = t.last(ana, 'payment_charge').charge.id;
    const before = (await row(ref)).seat_hold_until;
    await t.pay.handle(t.ws(ana), { type: 'payment_resume', charge_id: ref });
    assert.equal(t.last(ana, 'payment_charge').charge.id, ref);
    assert.equal(Number((await q(`select count(*)::int n from public.payments`))[0].n), 1);
    assert.equal(String((await row(ref)).seat_hold_until), String(before));
    assert.equal(await taken(), 1);
  } finally { t.restore(); }
});

test.after(async () => { if (pool) await pool.end(); });
