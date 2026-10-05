'use strict';
// R40 · Cartão DENTRO do jogo (Card Payment Brick → token → servidor cria o pagamento).
// Contra o Mercado Pago FALSO (fake_mercadopago.cjs). Confere: Public Key vai para o jogo (Access Token não),
// preço sempre do servidor, 1x, binary_mode, idempotência por tentativa, device id, recusado → motivo em
// português e pode tentar de novo, aprovado → libera na hora, webhook depois não libera 2x, pedido de outro
// jogador é recusado, token inválido é recusado, limite de tentativas, sem Public Key → só página do MP.
const { spawn } = require('child_process');
const path = require('path');
const http = require('http');
const { startServer, client, check, summary } = require('./helpers.cjs');

const get = (port, p) => new Promise((ok, ko) => http.get({ host: '127.0.0.1', port, path: p }, r => { let t = ''; r.on('data', d => t += d); r.on('end', () => ok(JSON.parse(t))); }).on('error', ko));

(async () => {
  const MPP = 27000 + Math.floor(Math.random() * 2000);
  const fake = spawn(process.execPath, [path.join(__dirname, 'fake_mercadopago.cjs'), String(MPP)], { stdio: 'ignore' });
  await new Promise(r => setTimeout(r, 400));
  const base = { FRAIHA_DEV_AUTH: '1', FRAIHA_PAYMENT_PROVIDER: 'mercadopago', FRAIHA_MP_ACCESS_TOKEN: 'TEST-TOKEN', FRAIHA_MP_WEBHOOK_SECRET: 's',
    FRAIHA_MP_API: 'http://127.0.0.1:' + MPP, FRAIHA_PUBLIC_URL: 'https://servidor.fraiha.test', FRAIHA_FOUNDER_LIMIT: '5' };
  const proc = await startServer({ ...base, FRAIHA_MP_PUBLIC_KEY: 'APP_USR-public-key-teste' });
  const P = proc.port;
  async function login(port, name) {
    const c = client(port); await c.open();
    c.send({ type: 'acct_auth', access_token: 'dev:' + name }); await c.next('acct_state');
    c.send({ type: 'acct_create_profile', nickname: name }); await c.next('acct_state');
    return c;
  }
  const bia = await login(P, 'BiaCard');
  // ---------- pedido de cartão: Public Key vem, Access Token não ----------
  bia.send({ type: 'payment_create', product_id: 'club_monthly', method: 'card' });
  const ch = (await bia.next('payment_charge', 5000)).charge;
  check(ch.method === 'card' && ch.public_key === 'APP_USR-public-key-teste' && /^https:\/\//.test(ch.checkout_url) && ch.amount_cents === 1990, 'cartão: Public Key (pública) para o formulário no jogo + página do Mercado Pago como alternativa');
  check(!JSON.stringify(ch).includes('TEST-TOKEN'), 'o Access Token nunca vai para o jogo');
  // ---------- token inválido ----------
  bia.send({ type: 'payment_card_pay', charge_id: ch.id, token: 'x', payment_method_id: 'master' });
  let r = await bia.next('payment_card_result');
  check(r.status === 'rejected' && /incompletos/.test(r.message), 'token inválido é recusado antes de ir ao Mercado Pago');
  // ---------- recusado por saldo → motivo em português, pedido continua aberto ----------
  bia.send({ type: 'payment_card_pay', charge_id: ch.id, token: 'tok-reject-0001', payment_method_id: 'master', issuer_id: '24', installments: 12, transaction_amount: 0.01, id_type: 'CPF', id_number: '123.456.789-09', device_id: 'dev-abc' });
  r = await bia.next('payment_card_result', 5000);
  check(r.status === 'rejected' && r.detail === 'cc_rejected_insufficient_amount' && /Saldo ou limite insuficiente/.test(r.message), 'cartão recusado: motivo claro em português (saldo/limite)');
  let cards = await get(MPP, '/__cards');
  const c1 = cards[cards.length - 1];
  check(c1.transaction_amount === 19.9 && c1.installments === 1 && c1.binary_mode === true, 'preço SEMPRE do servidor (19,90, ignora 0,01 do navegador), 1x, aprovação imediata (binary_mode)');
  check(c1.payer.email === 'BiaCard@dev.local' && c1.payer.identification.number === '12345678909' && c1.issuer_id === '24' && c1._session === 'dev-abc', 'e-mail da conta, CPF só com números, banco emissor e device id (antifraude) enviados');
  const it = c1.additional_info && c1.additional_info.items && c1.additional_info.items[0];
  check(it && it.id === 'club_monthly' && it.category_id === 'virtual_goods' && it.quantity === 1 && it.unit_price === 19.9 && /Club FRAIHA/.test(it.description), 'R40.1: detalhes do item enviados ao Mercado Pago (antifraude): categoria, descrição, quantidade e preço');
  check(c1._idem === ch.id + ':card:' + require('crypto').createHash('sha256').update('tok-reject-0001').digest('hex').slice(0, 24), 'idempotência pelo token: clique repetido com o mesmo cartão nunca cobra duas vezes');
  bia.send({ type: 'payment_status', charge_id: ch.id });
  let up = await bia.next('payment_update');
  check(up.charge.status === 'pending', 'depois da recusa o pedido continua aberto (pode tentar outro cartão)');
  // ---------- CVV errado ----------
  bia.send({ type: 'payment_card_pay', charge_id: ch.id, token: 'tok-cvv-0002', payment_method_id: 'visa' });
  r = await bia.next('payment_card_result', 5000);
  check(r.status === 'rejected' && /CVV/.test(r.message), 'CVV errado: mensagem própria');
  // ---------- pedido de OUTRO jogador ----------
  const caio = await login(P, 'CaioCard');
  caio.send({ type: 'payment_card_pay', charge_id: ch.id, token: 'tok-approve-9999', payment_method_id: 'master' });
  r = await caio.next('payment_card_result', 5000);
  check(r.status === 'error' && /não encontrado/.test(r.message), 'ninguém paga (nem libera) o pedido de outro jogador');
  // ---------- aprovado → libera na hora ----------
  bia.send({ type: 'payment_card_pay', charge_id: ch.id, token: 'tok-approve-0003', payment_method_id: 'master' });
  const upd = await bia.next(m => m.type === 'payment_update' && m.charge.status === 'paid', 5000);
  const st = await bia.next('acct_state', 5000);
  r = await bia.next('payment_card_result', 5000);
  check(upd.charge.id === ch.id && st.entitlements.club_active === true && r.status === 'approved', 'cartão aprovado → Club liberado na hora e o jogo é avisado (payment_update + acct_state)');
  const exp1 = st.entitlements.club_expires_at;
  // ---------- de novo no mesmo pedido: não cobra outra vez ----------
  const before = (await get(MPP, '/__cards')).length;
  bia.send({ type: 'payment_card_pay', charge_id: ch.id, token: 'tok-approve-0004', payment_method_id: 'master' });
  r = await bia.next('payment_card_result', 5000);
  check(r.status === 'approved' && (await get(MPP, '/__cards')).length === before, 'pedido já pago: não cobra de novo');
  // ---------- webhook do mesmo pagamento depois: não libera 2x ----------
  bia.send({ type: 'payment_status', charge_id: ch.id });
  up = await bia.next('payment_update', 9000);
  bia.send({ type: 'acct_refresh' });
  const st2 = await bia.next('acct_state');
  check(up.charge.status === 'paid' && st2.entitlements.club_expires_at === exp1, 'consulta/notificação depois não soma dias de novo');
  // ---------- PIX não aceita token de cartão ----------
  bia.send({ type: 'payment_create', product_id: 'founder', method: 'pix' });
  const pix = (await bia.next('payment_charge', 5000)).charge;
  check(pix.public_key == null, 'PIX não leva Public Key');
  bia.send({ type: 'payment_card_pay', charge_id: pix.id, token: 'tok-approve-0005', payment_method_id: 'master' });
  r = await bia.next('payment_card_result', 5000);
  check(r.status === 'error', 'pedido PIX não pode ser pago com token de cartão');
  // ---------- limite de tentativas ----------
  bia.send({ type: 'payment_create', product_id: 'founder', method: 'card' });
  const ch2 = (await bia.next('payment_charge', 5000)).charge;
  let last;
  // (com pausa entre tentativas: o servidor derruba conexões com mais de 20 mensagens/s)
  for (let i = 0; i < 7; i++) { await new Promise(z => setTimeout(z, 150)); bia.send({ type: 'payment_card_pay', charge_id: ch2.id, token: 'tok-reject-' + (100 + i), payment_method_id: 'master' }); last = await bia.next('payment_card_result', 5000); }
  check(last.status === 'rejected' && /Muitas tentativas/.test(last.message), 'limite de tentativas por pedido (evita teste de cartões em massa)');
  bia.close(); caio.close(); proc.stop();
  // ---------- servidor sem Public Key: cartão continua só na página do Mercado Pago ----------
  const proc2 = await startServer(base);
  const dan = await login(proc2.port, 'DanCard');
  dan.send({ type: 'payment_create', product_id: 'club_monthly', method: 'card' });
  const ch3 = (await dan.next('payment_charge', 5000)).charge;
  check(ch3.public_key == null && /^https:\/\//.test(ch3.checkout_url), 'sem FRAIHA_MP_PUBLIC_KEY: sem formulário no jogo, só a página do Mercado Pago (como no R39)');
  dan.close(); proc2.stop(); fake.kill();
  summary('card_inline_test');
})().catch(e => { console.error(e); process.exit(1); });
