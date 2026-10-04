'use strict';
// R39 · Mercado Pago (PIX + cartão) contra um Mercado Pago FALSO local (mesmos caminhos e formatos da API):
// cobrança PIX (QR + Copia e Cola), checkout de cartão, webhook assinado (x-signature), consulta do pagamento,
// valor errado não libera, webhook repetido não libera 2x, reembolso retira, limite de Fundadores,
// Fundador não compra 2x, link do grupo só para Fundador, cartão recusado não cancela o pedido.
const http = require('http');
const crypto = require('crypto');
const { startServer, client, check, summary } = require('./helpers.cjs');

const SECRET = 'segredo-de-teste';
const mp = { payments: new Map(), prefs: [], calls: [], nextId: 9001 };
function json(res, code, body) { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); }
const fake = http.createServer((req, res) => {
  let raw = ''; req.on('data', d => raw += d);
  req.on('end', () => {
    const body = raw ? JSON.parse(raw) : {};
    mp.calls.push({ method: req.method, url: req.url, auth: req.headers.authorization, idem: req.headers['x-idempotency-key'], body });
    if (req.headers.authorization !== 'Bearer TEST-TOKEN') return json(res, 401, { message: 'unauthorized' });
    if (req.method === 'POST' && req.url === '/v1/payments') {
      const id = String(mp.nextId++);
      const p = { id: Number(id), status: 'pending', status_detail: 'pending_waiting_transfer', transaction_amount: body.transaction_amount, currency_id: 'BRL', external_reference: body.external_reference, payment_method_id: 'pix',
        point_of_interaction: { transaction_data: { qr_code: '00020126PIXCOPIAECOLA' + id, qr_code_base64: Buffer.from('PNGFAKE').toString('base64'), ticket_url: 'https://mp.test/ticket/' + id } } };
      mp.payments.set(id, p); return json(res, 201, p);
    }
    if (req.method === 'POST' && req.url === '/checkout/preferences') {
      const id = 'pref-' + mp.prefs.length; mp.prefs.push({ id, ...body });
      return json(res, 201, { id, init_point: 'https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=' + id });
    }
    const m = req.url.match(/^\/v1\/payments\/(\d+)$/);
    if (req.method === 'GET' && m) { const p = mp.payments.get(m[1]); return p ? json(res, 200, p) : json(res, 404, { message: 'not found' }); }
    if (req.method === 'GET' && req.url.startsWith('/v1/payments/search')) {
      const ref = new URL(req.url, 'http://x').searchParams.get('external_reference');
      return json(res, 200, { results: [...mp.payments.values()].filter(p => p.external_reference === ref) });
    }
    json(res, 404, { message: 'no route' });
  });
});

function sign(dataId, requestId, ts, secret = SECRET) {
  const manifest = `id:${String(dataId).toLowerCase()};request-id:${requestId};ts:${ts};`;
  return `ts=${ts},v1=${crypto.createHmac('sha256', secret).update(manifest).digest('hex')}`;
}
function notify(port, dataId, { secret = SECRET, type = 'payment', unsigned = false } = {}) {
  return new Promise(resolve => {
    const rid = crypto.randomUUID(), ts = String(Date.now());
    const headers = { 'content-type': 'application/json', 'x-request-id': rid };
    if (!unsigned) headers['x-signature'] = sign(dataId, rid, ts, secret);
    const body = JSON.stringify({ action: 'payment.updated', type, data: { id: String(dataId) } });
    const req = http.request({ host: '127.0.0.1', port, path: `/webhooks/payments?data.id=${dataId}&type=${type}`, method: 'POST', headers }, res => { let t = ''; res.on('data', d => t += d); res.on('end', () => resolve({ code: res.statusCode, body: t })); });
    req.end(body);
  });
}
const settle = (ms = 150) => new Promise(r => setTimeout(r, ms));

(async () => {
  await new Promise(r => fake.listen(0, '127.0.0.1', r));
  const fport = fake.address().port;
  const env = { FRAIHA_DEV_AUTH: '1', FRAIHA_PAYMENT_PROVIDER: 'mercadopago', FRAIHA_MP_ACCESS_TOKEN: 'TEST-TOKEN', FRAIHA_MP_WEBHOOK_SECRET: SECRET,
    FRAIHA_MP_API: 'http://127.0.0.1:' + fport, FRAIHA_PUBLIC_URL: 'https://servidor.fraiha.test', FRAIHA_FOUNDER_LIMIT: '2', FRAIHA_FOUNDER_WHATSAPP_URL: 'https://chat.whatsapp.com/GRUPO-TESTE' };
  const proc = await startServer(env);
  const P = proc.port;

  async function login(name) {
    const c = client(P); await c.open();
    c.send({ type: 'acct_auth', access_token: 'dev:' + name }); await c.next('acct_state');
    c.send({ type: 'acct_create_profile', nickname: name }); const st = await c.next('acct_state');
    return { c, st };
  }
  // ---------- oferta ----------
  const { c: ana, st: st0 } = await login('AnaPix');
  check(st0.founder_perks == null, 'sem compra: link do grupo dos Fundadores NÃO vem para o jogo');
  ana.send({ type: 'payment_offer' });
  let off = await ana.next('payment_offer');
  check(off.ready === true && off.founder_limit === 2 && off.founder_remaining === 2 && off.prices.founder === 4990 && off.prices.club_monthly === 1990, 'oferta: provedor pronto, 2 vagas de Fundador, preços 49,90 / 19,90');
  // ---------- PIX do Fundador ----------
  ana.send({ type: 'payment_create', product_id: 'founder', method: 'pix' });
  let ch = (await ana.next('payment_charge', 5000)).charge;
  const call = mp.calls.find(x => x.method === 'POST' && x.url === '/v1/payments');
  check(ch.method === 'pix' && ch.copy_paste.startsWith('00020126') && ch.qr_code_base64 && ch.ticket_url && ch.status === 'pending' && ch.expires_at, 'PIX: QR (imagem), Copia e Cola, link e validade chegam ao jogo');
  check(call && call.body.payment_method_id === 'pix' && call.body.transaction_amount === 49.9 && call.body.payer.email === 'AnaPix@dev.local' && call.body.external_reference === ch.id && call.idem === ch.id, 'PIX criado no Mercado Pago com valor 49,90, e-mail da conta, referência interna e chave de idempotência');
  check(/\/webhooks\/payments$/.test(call.body.notification_url) && /-03:00$/.test(call.body.date_of_expiration), 'PIX com notification_url do servidor e validade no horário de Brasília');
  check(!JSON.stringify(ch).includes('TEST-TOKEN'), 'nenhuma chave do Mercado Pago vai para o jogo');
  const pixId = String(mp.nextId - 1);
  // status ainda pendente
  ana.send({ type: 'payment_status', charge_id: ch.id });
  let up = await ana.next('payment_update');
  check(up.charge.status === 'pending', 'antes de pagar: pendente');
  // webhook com assinatura ERRADA → recusado, nada liberado
  mp.payments.get(pixId).status = 'approved';
  let r = await notify(P, pixId, { secret: 'outro-segredo' });
  check(r.code === 401, 'webhook com assinatura errada é recusado (401)');
  ana.send({ type: 'acct_refresh' });
  let st = await ana.next('acct_state');
  check(!st.entitlements.is_founder, 'assinatura errada não libera nada');
  // webhook de outro tipo → ignorado
  r = await notify(P, '123', { type: 'merchant_order' });
  check(r.code === 200 && r.body === 'ignored', 'notificação que não é de pagamento: 200 e ignorada');
  // webhook certo → consulta a API e libera
  r = await notify(P, pixId);
  check(r.code === 200, 'webhook assinado aceito (200)');
  up = await ana.next(m => m.type === 'payment_update' && m.charge.status === 'paid', 4000);
  st = await ana.next('acct_state', 4000);
  check(up.charge.id === ch.id && st.entitlements.is_founder === true && st.entitlements.club_active === true, 'PIX aprovado → Fundador + 30 dias de Club, e o jogo é avisado na hora');
  check(st.founder_perks && st.founder_perks.whatsapp_url === 'https://chat.whatsapp.com/GRUPO-TESTE', 'Fundador de verdade recebe o link do grupo (só ele)');
  // webhook repetido → não libera de novo
  r = await notify(P, pixId);
  await settle();
  ana.send({ type: 'acct_refresh' }); st = await ana.next('acct_state');
  const exp1 = st.entitlements.club_expires_at;
  const days = (new Date(exp1) - Date.now()) / 86400000;
  check(r.code === 200 && days > 29 && days < 31, 'webhook repetido não soma outros 30 dias (%s dias)'.replace('%s', days.toFixed(1)));
  // Fundador não compra de novo
  ana.send({ type: 'payment_create', product_id: 'founder', method: 'pix' });
  let err = await ana.next('payment_error');
  check(err.code === 'already_founder', 'quem já é Fundador não compra o pacote de novo');
  // ---------- Club no cartão (Checkout Pro) ----------
  ana.send({ type: 'payment_create', product_id: 'club_monthly', method: 'card' });
  ch = (await ana.next('payment_charge', 5000)).charge;
  const pref = mp.prefs[mp.prefs.length - 1];
  check(ch.method === 'card' && ch.checkout_url.includes('pref_id=') && pref.items[0].unit_price === 19.9 && pref.items[0].currency_id === 'BRL' && pref.external_reference === ch.id && pref.back_urls.success, 'cartão: link do checkout do Mercado Pago (19,90 BRL, referência interna, volta para o jogo)');
  // 1ª tentativa recusada, 2ª aprovada (mesmo checkout)
  const cardRej = String(mp.nextId++); mp.payments.set(cardRej, { id: Number(cardRej), status: 'rejected', transaction_amount: 19.9, currency_id: 'BRL', external_reference: ch.id });
  r = await notify(P, cardRej); await settle();
  ana.send({ type: 'payment_status', charge_id: ch.id });
  up = await ana.next('payment_update');
  check(up.charge.status === 'pending', 'cartão recusado não encerra o pedido (dá para tentar outro cartão)');
  const cardOk = String(mp.nextId++); mp.payments.set(cardOk, { id: Number(cardOk), status: 'approved', transaction_amount: 19.9, currency_id: 'BRL', external_reference: ch.id });
  r = await notify(P, cardOk);
  st = await ana.next('acct_state', 4000);
  const days2 = (new Date(st.entitlements.club_expires_at) - Date.now()) / 86400000;
  check(days2 > 59 && days2 < 61, 'Club no cartão aprovado soma +30 dias ao que restava (%s dias)'.replace('%s', days2.toFixed(1)));
  // ---------- reembolso do Club → tira os 30 dias ----------
  mp.payments.get(cardOk).status = 'refunded';
  r = await notify(P, cardOk);
  st = await ana.next('acct_state', 4000);
  const days3 = (new Date(st.entitlements.club_expires_at) - Date.now()) / 86400000;
  check(days3 > 29 && days3 < 31 && st.entitlements.is_founder, 'reembolso do Club tira os 30 dias dele (o Fundador continua)');
  // ---------- contestação do Fundador → perde tudo ----------
  mp.payments.get(pixId).status = 'charged_back';
  r = await notify(P, pixId);
  st = await ana.next('acct_state', 4000);
  check(!st.entitlements.is_founder && !st.entitlements.club_active && st.founder_perks == null, 'contestação (chargeback) do Fundador: perde selo de Fundador, Club e o link do grupo');
  // ---------- valor errado não libera ----------
  const { c: bia } = await login('BiaValor');
  bia.send({ type: 'payment_create', product_id: 'club_monthly', method: 'pix' });
  ch = (await bia.next('payment_charge', 5000)).charge;
  const pid2 = String(mp.nextId - 1);
  mp.payments.get(pid2).status = 'approved'; mp.payments.get(pid2).transaction_amount = 1.0;
  r = await notify(P, pid2); await settle(300);
  bia.send({ type: 'acct_refresh' }); st = await bia.next('acct_state');
  check(!st.entitlements.club_active, 'pagamento com valor diferente do preço NÃO libera o Club');
  // ---------- webhook perdido: o jogo pergunta e o servidor consulta o Mercado Pago ----------
  bia.send({ type: 'payment_create', product_id: 'club_monthly', method: 'pix' });
  ch = (await bia.next('payment_charge', 5000)).charge;
  const pid3 = String(mp.nextId - 1);
  mp.payments.get(pid3).status = 'approved';
  bia.send({ type: 'payment_status', charge_id: ch.id });
  up = await bia.next(m => m.type === 'payment_update' && m.charge.id === ch.id && m.charge.status === 'paid', 5000);
  st = await bia.next('acct_state', 4000);
  check(up.charge.status === 'paid' && st.entitlements.club_active, 'sem webhook: "já paguei?" consulta o Mercado Pago e libera o Club');
  // PIX expirado → cancelado
  bia.send({ type: 'payment_create', product_id: 'club_monthly', method: 'pix' });
  ch = (await bia.next('payment_charge', 5000)).charge;
  const pid4 = String(mp.nextId - 1);
  mp.payments.get(pid4).status = 'cancelled';
  r = await notify(P, pid4); await settle();
  bia.send({ type: 'payment_status', charge_id: ch.id });
  up = await bia.next(m => m.type === 'payment_update' && m.charge.id === ch.id);
  check(up.charge.status === 'cancelled', 'PIX expirado fica cancelado');
  // outro jogador não consulta pedido alheio
  ana.inbox.length = 0;
  ana.send({ type: 'payment_status', charge_id: ch.id });
  up = await ana.next(m => m.type === 'payment_update' && m.charge.id === ch.id);
  check(up.charge.status === 'unknown', 'ninguém vê o pedido de outro jogador');
  // ---------- limite de Fundadores ----------
  for (const n of ['Caio', 'Duda']) {
    const { c } = await login(n);
    c.send({ type: 'payment_create', product_id: 'founder', method: 'pix' });
    await c.next('payment_charge', 5000);
    const id = String(mp.nextId - 1); mp.payments.get(id).status = 'approved';
    await notify(P, id); await c.next('acct_state', 4000);
  }
  const { c: edu } = await login('Edu');
  edu.send({ type: 'payment_offer' }); off = await edu.next('payment_offer');
  check(off.founder_remaining === 0, 'oferta mostra 0 vagas quando o limite acaba');
  edu.send({ type: 'payment_create', product_id: 'founder', method: 'pix' });
  err = await edu.next('payment_error');
  check(err.code === 'founder_sold_out', 'vagas esgotadas: ninguém mais compra o Pacote Fundador');
  // convidado não compra
  const g = client(P); await g.open();
  g.send({ type: 'payment_create', product_id: 'club_monthly', method: 'pix' });
  err = await g.next('payment_error');
  check(err.code === 'auth_required', 'sem conta: pede para entrar');
  for (const c of [ana, bia, edu, g]) c.close();
  proc.stop(); fake.close();
  summary('MERCADOPAGO');
})().catch(e => { console.error(e); process.exit(1); });
