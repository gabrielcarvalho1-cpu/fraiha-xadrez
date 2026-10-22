'use strict';
// R175E-teste · back_urls/auto_return só com URL pública HTTPS (o Mercado Pago recusa localhost: "auto_return invalid.
// back_url.success must be defined"). Produção (jogar.fraihaxadrez.com) continua igual; PIX não muda.
const { publicBackUrl, MercadoPago } = require('../../online_v021/payments/providers/mercadopago.js');
let ok = 0, bad = 0;
const check = (c, m) => { if (c) { ok++; console.log('  ok  ' + m); } else { bad++; console.log('  FALHA  ' + m); } };
for (const u of ['https://jogar.fraihaxadrez.com', 'https://teste.exemplo.com/jogo']) check(publicBackUrl(u) !== '', 'pública: ' + u);
for (const u of ['http://127.0.0.1:8129', 'https://127.0.0.1:8129', 'https://localhost:8129', 'http://localhost', 'https://jogo.localhost',
  'https://[::1]:8129', 'https://0.0.0.0', 'http://jogar.fraihaxadrez.com', '', 'não é url']) check(publicBackUrl(u) === '', 'não pública: ' + JSON.stringify(u));
async function body(gameUrl, method) {
  const env = { FRAIHA_MP_ACCESS_TOKEN: 'TEST-x', FRAIHA_PUBLIC_URL: 'https://srv.test', FRAIHA_MP_PUBLIC_KEY: 'TEST-pk' };
  if (gameUrl !== undefined) env.FRAIHA_GAME_URL = gameUrl;
  const mp = new MercadoPago(env); const sent = [];
  mp.call = async (m, path, b, idem) => { sent.push({ path, b, idem }); return path === '/checkout/preferences'
    ? { id: 'pref1', init_point: 'https://mp.test/redirect?pref_id=pref1' }
    : { id: 77, point_of_interaction: { transaction_data: { qr_code: 'QR', qr_code_base64: 'B64' } } }; };
  const out = await mp.createCharge({ ref: 'ref-1', userId: 'u1', productId: 'club_monthly', method, amountCents: 1990, title: 'Club', email: 'a@example.com' });
  return { sent, out };
}
(async () => {
  let r = await body(undefined, 'card');
  const p = r.sent[0].b;
  check(r.sent[0].path === '/checkout/preferences' && p.auto_return === 'approved' && p.back_urls.success === 'https://jogar.fraihaxadrez.com'
    && p.back_urls.pending === p.back_urls.success && p.back_urls.failure === p.back_urls.success, 'produção (padrão): back_urls + auto_return como antes');
  check(r.sent[0].idem === 'ref-1' && r.out.public_key === 'TEST-pk' && r.out.checkout_url.includes('pref_id='), 'produção: mesma chave de idempotência, checkout e formulário no jogo');
  r = await body('http://127.0.0.1:8129', 'card');
  const q = r.sent[0].b;
  check(!('auto_return' in q) && !('back_urls' in q), 'cliente local 127.0.0.1: sem auto_return e sem back_urls inválidas');
  check(q.external_reference === 'ref-1' && q.notification_url === 'https://srv.test/webhooks/payments' && r.sent[0].idem === 'ref-1' && r.out.public_key === 'TEST-pk',
    'cliente local: referência, webhook, idempotência e formulário de cartão iguais');
  r = await body('https://localhost:8129', 'card');
  check(!('auto_return' in r.sent[0].b) && !('back_urls' in r.sent[0].b), 'localhost HTTPS também fica sem back_urls');
  r = await body('http://127.0.0.1:8129', 'pix');
  check(r.sent[0].path === '/v1/payments' && r.sent[0].b.payment_method_id === 'pix' && !('back_urls' in r.sent[0].b) && r.out.copy_paste === 'QR', 'PIX não muda');
  console.log(`MERCADOPAGO BACK_URLS: ${ok} ok, ${bad} falha(s)`);
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
