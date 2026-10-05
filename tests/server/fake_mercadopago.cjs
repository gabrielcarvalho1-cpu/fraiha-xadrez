'use strict';
// R39 · Mercado Pago FALSO para testes locais (mesmos caminhos/formatos da API usados pelo FRAIHA).
// Controle de teste: POST /__approve?ref=<external_reference>  → marca o último pagamento daquela referência
// como aprovado (cria um pagamento aprovado, no caso do cartão). Uso: node fake_mercadopago.cjs <porta>
const http = require('http');
const zlib = require('zlib');
const port = Number(process.argv[2] || 0);
const payments = new Map(); let nextId = 7001; const prefs = new Map();
// PNG 8x8 de verdade (para o jogo conseguir decodificar o "QR")
function png() {
  const w = 8, h = 8, raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const v = (x + y) % 2 ? 0 : 255; const o = y * (w * 3 + 1) + 1 + x * 3; raw[o] = raw[o + 1] = raw[o + 2] = v; }
  const crc = (b) => { let c, t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } let r = 0xffffffff; for (const x of b) r = t[(r ^ x) & 0xff] ^ (r >>> 8); return (r ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]).toString('base64');
}
const PNG = png();
const json = (res, code, body) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };
const srv = http.createServer((req, res) => {
  let raw = ''; req.on('data', d => raw += d);
  req.on('end', () => {
    const body = raw ? JSON.parse(raw) : {};
    const url = new URL(req.url, 'http://x');
    if (req.method === 'POST' && url.pathname === '/__approve') {
      const ref = url.searchParams.get('ref');
      let p = [...payments.values()].reverse().find(x => x.external_reference === ref);
      if (!p && prefs.has(ref)) { const pr = prefs.get(ref); p = { id: nextId++, status: 'pending', transaction_amount: pr.items[0].unit_price, currency_id: 'BRL', external_reference: ref }; payments.set(String(p.id), p); }
      if (!p) return json(res, 404, { message: 'ref desconhecida' });
      p.status = 'approved'; return json(res, 200, { ok: true, id: p.id });
    }
    if (req.method === 'GET' && url.pathname === '/__cards') return json(res, 200, [...payments.values()].filter(p => p.payment_method_id && p.payment_method_id !== 'pix'));
    if (req.method === 'GET' && url.pathname === '/__last') return json(res, 200, { ref: [...payments.values(), ...[...prefs.values()].map(x => ({ external_reference: x.external_reference }))].map(x => x.external_reference).pop() || '' });
    if (req.headers.authorization !== 'Bearer TEST-TOKEN') return json(res, 401, { message: 'unauthorized' });
    if (req.method === 'POST' && url.pathname === '/v1/payments') {
      if (body.token) {   // R40: cartão no jogo (token do Card Payment Brick). TOKEN "...reject..." = recusado por saldo.
        const rej = /reject/.test(body.token), bad = /cvv/.test(body.token);
        const p = { id: nextId++, status: rej || bad ? 'rejected' : 'approved', status_detail: rej ? 'cc_rejected_insufficient_amount' : (bad ? 'cc_rejected_bad_filled_security_code' : 'accredited'),
          transaction_amount: body.transaction_amount, currency_id: 'BRL', external_reference: body.external_reference, payment_method_id: body.payment_method_id,
          installments: body.installments, binary_mode: body.binary_mode, payer: body.payer, issuer_id: body.issuer_id,
          _session: req.headers['x-meli-session-id'] || '', _idem: req.headers['x-idempotency-key'] || '' };
        payments.set(String(p.id), p); return json(res, 201, p);
      }
      const p = { id: nextId++, status: 'pending', transaction_amount: body.transaction_amount, currency_id: 'BRL', external_reference: body.external_reference,
        point_of_interaction: { transaction_data: { qr_code: '00020126580014br.gov.bcb.pix0136TESTE' + body.external_reference.slice(0, 8), qr_code_base64: PNG, ticket_url: 'https://www.mercadopago.com.br/payments/' + nextId + '/ticket' } } };
      payments.set(String(p.id), p); return json(res, 201, p);
    }
    if (req.method === 'POST' && url.pathname === '/checkout/preferences') {
      prefs.set(body.external_reference, body);
      return json(res, 201, { id: 'pref-' + body.external_reference.slice(0, 8), init_point: 'https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=pref-' + body.external_reference.slice(0, 8) });
    }
    const m = url.pathname.match(/^\/v1\/payments\/(\d+)$/);
    if (req.method === 'GET' && m) { const p = payments.get(m[1]); return p ? json(res, 200, p) : json(res, 404, {}); }
    if (req.method === 'GET' && url.pathname === '/v1/payments/search') {
      const ref = url.searchParams.get('external_reference');
      return json(res, 200, { results: [...payments.values()].filter(p => p.external_reference === ref) });
    }
    json(res, 404, { message: 'no route' });
  });
});
srv.listen(port, '127.0.0.1', () => console.log('fake-mp listening ' + srv.address().port));
