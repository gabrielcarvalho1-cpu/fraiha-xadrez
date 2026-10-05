'use strict';
// R40.1 · Se o Mercado Pago recusar os detalhes opcionais (additional_info / statement_descriptor),
// a cobrança sai mesmo assim (2ª tentativa sem eles, com outra chave de idempotência).
const http = require('http');
const { MercadoPago } = require('../../online_v021/payments/providers/mercadopago.js');
const { check, summary } = require('./helpers.cjs');
const calls = [];
const srv = http.createServer((req, res) => { let raw = ''; req.on('data', d => raw += d); req.on('end', () => {
  const b = raw ? JSON.parse(raw) : {}; calls.push({ url: req.url, idem: req.headers['x-idempotency-key'], b });
  const j = (c, o) => { res.writeHead(c, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
  const extras = b.additional_info || b.statement_descriptor || (b.items && b.items[0] && b.items[0].category_id);
  if (extras) return j(400, { message: 'invalid additional_info.items.category_id' });
  if (req.url === '/checkout/preferences') return j(201, { id: 'p1', init_point: 'https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=p1' });
  if (b.token) return j(201, { id: 9, status: 'approved', transaction_amount: b.transaction_amount, currency_id: 'BRL', external_reference: b.external_reference });
  j(201, { id: 8, status: 'pending', point_of_interaction: { transaction_data: { qr_code: '000201X', qr_code_base64: '', ticket_url: '' } } });
}); });
srv.listen(0, '127.0.0.1', async () => {
  const mp = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'T', FRAIHA_PUBLIC_URL: 'https://s.test', FRAIHA_MP_API: 'http://127.0.0.1:' + srv.address().port });
  const log = console.warn; console.warn = () => {};
  const pix = await mp.createCharge({ ref: 'r1', userId: 'u', productId: 'club_monthly', method: 'pix', amountCents: 1990, title: 'Club', email: 'a@b.c' });
  check(pix.copy_paste === '000201X' && calls.length === 2 && calls[1].idem === 'r1:sem-extras' && !calls[1].b.additional_info, 'PIX: recusa dos detalhes opcionais → sai sem eles, com outra chave de idempotência');
  const card = await mp.createCharge({ ref: 'r2', userId: 'u', productId: 'founder', method: 'card', amountCents: 4990, title: 'F', email: 'a@b.c' });
  check(/pref_id=p1/.test(card.checkout_url) && !calls[3].b.items[0].category_id, 'página do cartão: idem');
  const ev = await mp.payCard({ ref: 'r3', token: 'tok-abcdefgh', paymentMethodId: 'master', amountCents: 1990, title: 'C', email: 'a@b.c', userId: 'u', productId: 'club_monthly' });
  check(ev.status === 'paid' && /:sem-extras$/.test(calls[5].idem), 'cartão no jogo: idem');
  console.warn = log; srv.close(); summary('MP_OPTIONAL_FIELDS');
});
