'use strict';
// R175 · provedor Mercado Pago (classe real) contra um Mercado Pago FALSO local: CONTINUAR PIX devolve o MESMO pagamento
// (mesmo QR/Copia e Cola, sem POST novo), PIX vencido/pago é reconhecido, CANCELAR usa PUT status=cancelled no pagamento
// certo, e CONTINUAR cartão cria a preferência com outra chave de idempotência (mesmo external_reference).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { MercadoPago } = require('../../online_v021/payments/providers/mercadopago');

function fakeServer() {
  const mp = { payments: new Map(), calls: [], nextId: 9100 };
  const json = (res, code, body) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };
  const srv = http.createServer((req, res) => {
    let raw = ''; req.on('data', d => raw += d);
    req.on('end', () => {
      const body = raw ? JSON.parse(raw) : {};
      mp.calls.push({ method: req.method, url: req.url, idem: req.headers['x-idempotency-key'], body });
      if (req.method === 'POST' && req.url === '/v1/payments') {
        const id = mp.nextId++;
        const p = { id, status: 'pending', transaction_amount: body.transaction_amount, currency_id: 'BRL', external_reference: body.external_reference, date_of_expiration: body.date_of_expiration,
          point_of_interaction: { transaction_data: { qr_code: 'PIXCOPIA' + id, qr_code_base64: 'QRB64' + id, ticket_url: 'https://mp.test/t/' + id } } };
        mp.payments.set(String(id), p); return json(res, 201, p);
      }
      if (req.method === 'POST' && req.url === '/checkout/preferences') return json(res, 201, { id: 'pref', init_point: 'https://mp.test/checkout?k=' + encodeURIComponent(req.headers['x-idempotency-key']) });
      if (req.method === 'GET' && req.url.startsWith('/v1/payments/search')) {
        const ref = new URL(req.url, 'http://x').searchParams.get('external_reference');
        // a busca devolve o resumo SEM o point_of_interaction (o provedor busca o pagamento completo depois)
        return json(res, 200, { results: [...mp.payments.values()].filter(p => p.external_reference === ref).reverse().map(({ point_of_interaction, ...rest }) => rest) });
      }
      const m = req.url.match(/^\/v1\/payments\/(\d+)$/);
      if (m && req.method === 'GET') { const p = mp.payments.get(m[1]); return p ? json(res, 200, p) : json(res, 404, {}); }
      if (m && req.method === 'PUT') {
        const p = mp.payments.get(m[1]); if (!p) return json(res, 404, {});
        if (p.status === 'approved') return json(res, 400, { message: 'Payment cannot be cancelled' });
        p.status = body.status; return json(res, 200, p);
      }
      json(res, 404, { message: 'no route' });
    });
  });
  return { mp, srv };
}

async function withMP(fn) {
  const { mp, srv } = fakeServer();
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  const prov = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'TEST', FRAIHA_PUBLIC_URL: 'https://srv.test', FRAIHA_MP_API: 'http://127.0.0.1:' + srv.address().port, FRAIHA_MP_PUBLIC_KEY: 'PK' });
  try { await fn(prov, mp); } finally { srv.close(); }
}

test('CONTINUAR PIX: mesmo pagamento do Mercado Pago (mesmo QR / Copia e Cola), nenhuma cobrança nova', () => withMP(async (prov, mp) => {
  const c = await prov.createCharge({ ref: 'ref-1', userId: 'u', productId: 'founder', method: 'pix', amountCents: 4490, title: 'F', email: 'a@b.c' });
  const posts = mp.calls.filter(x => x.method === 'POST').length;
  const r = await prov.resumePix('ref-1');
  assert.ok(r.charge, 'ainda aberto');
  assert.equal(r.charge.copy_paste, c.copy_paste); assert.equal(r.charge.qr_code_base64, c.qr_code_base64);
  assert.equal(r.charge.provider_payment_id, c.provider_payment_id);
  assert.ok(Date.parse(r.charge.expires_at) > Date.now());
  assert.equal(mp.calls.filter(x => x.method === 'POST').length, posts, 'sem POST novo');
  assert.equal(await prov.resumePix('outro-ref'), null);
}));

test('CONTINUAR PIX vencido ou pago: devolve o evento (sem QR)', () => withMP(async (prov, mp) => {
  await prov.createCharge({ ref: 'ref-2', userId: 'u', productId: 'founder', method: 'pix', amountCents: 4490, title: 'F', email: 'a@b.c' });
  const p = [...mp.payments.values()][0];
  p.date_of_expiration = new Date(Date.now() - 1000).toISOString();
  let r = await prov.resumePix('ref-2');
  assert.equal(r.charge, undefined); assert.equal(r.event.expired, true);
  p.date_of_expiration = new Date(Date.now() + 60e3).toISOString(); p.status = 'approved';
  r = await prov.resumePix('ref-2');
  assert.equal(r.event.status, 'paid'); assert.equal(r.event.providerRef, 'ref-2'); assert.equal(r.event.amountCents, 4490);
}));

test('CANCELAR: PUT status=cancelled no pagamento do pedido; aprovado não cancela (erro → o serviço reconfere)', () => withMP(async (prov, mp) => {
  const c = await prov.createCharge({ ref: 'ref-3', userId: 'u', productId: 'founder', method: 'pix', amountCents: 4490, title: 'F', email: 'a@b.c' });
  const ev = await prov.cancel(c.provider_payment_id);
  assert.equal(ev.status, 'cancelled'); assert.equal(ev.providerRef, 'ref-3');
  const put = mp.calls.find(x => x.method === 'PUT');
  assert.equal(put.url, '/v1/payments/' + c.provider_payment_id); assert.deepEqual(put.body, { status: 'cancelled' });
  const c2 = await prov.createCharge({ ref: 'ref-4', userId: 'u', productId: 'founder', method: 'pix', amountCents: 4490, title: 'F', email: 'a@b.c' });
  mp.payments.get(c2.provider_payment_id).status = 'approved';
  await assert.rejects(prov.cancel(c2.provider_payment_id));
  await assert.rejects(prov.cancel('abc'), /inválido/);
}));

test('CONTINUAR cartão: nova preferência do MESMO pedido com outra chave de idempotência', () => withMP(async (prov, mp) => {
  const a = await prov.createCharge({ ref: 'ref-5', userId: 'u', productId: 'founder', method: 'card', amountCents: 4990, title: 'F', email: 'a@b.c' });
  const b = await prov.createCharge({ ref: 'ref-5', userId: 'u', productId: 'founder', method: 'card', amountCents: 4990, title: 'F', email: 'a@b.c', idemSuffix: ':continuar:1' });
  const prefs = mp.calls.filter(x => x.url === '/checkout/preferences');
  assert.equal(prefs.length, 2);
  assert.equal(prefs[0].idem, 'ref-5'); assert.equal(prefs[1].idem, 'ref-5:continuar:1');
  assert.equal(prefs[1].body.external_reference, 'ref-5', 'mesmo pedido');
  assert.equal(b.public_key, 'PK'); assert.notEqual(a.checkout_url, b.checkout_url);
}));
