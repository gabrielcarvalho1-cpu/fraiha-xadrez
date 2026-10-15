'use strict';
// R103 · nova oferta: Fundador Lendário, Club anual, PIX com desconto, Fundador por tempo limitado, pedido de Fundador
// em aberto, pagamento que nunca fica "pago sem vantagem", reconciliação e histórico de compras.
const { MemoryStore } = require('../../online_v021/accounts/store');
const { Payments } = require('../../online_v021/payments/service');
let checks = 0, fails = 0;
const check = (ok, m) => { checks++; if (!ok) fails++; console.log((ok ? 'PASS ' : 'FAIL ') + m); };
function setup(env = {}) {
  const store = new MemoryStore(); const sent = [];
  const backend = { store, socketsOf: () => [], state: async () => {} };
  const pay = new Payments({ send: (ws, o) => sent.push(o), backend, env: { FRAIHA_PAYMENT_PROVIDER: '', ...env } });
  pay.provider = { name: 'fake', ready: () => true, createCharge: async ({ ref, amountCents }) => ({ id: ref, method: 'pix', status: 'pending', amount: amountCents }) };
  const ws = id => ({ user: { id, email: id + '@x.dev' }, profile: { nickname: id } });
  const last = t => [...sent].reverse().find(o => o.type === t);
  return { store, pay, sent, ws, last };
}
(async () => {
  const quiet = console.error; console.error = () => {}; console.warn = () => {};
  let t = setup();
  await t.pay.handle(t.ws('ana'), { type: 'payment_offer' });
  const off = t.last('payment_offer');
  check(off.prices.founder_legend === 9990 && off.prices.club_yearly === 14990 && off.prices_pix.founder === 4490 && off.prices_pix.club_monthly === 1790, 'oferta com Lendário, anual e preços do PIX');
  check(off.founder_open === true && off.founder_remaining === null, 'Fundador à venda, sem limite de vagas');
  await t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'founder', method: 'pix' });
  check(t.last('payment_charge').charge.amount_cents === 4490, 'PIX do Fundador sai com desconto (R$ 44,90)');
  await t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'founder_legend', method: 'card' });
  check(t.last('payment_error').code === 'order_open', 'com um Fundador em aberto, não abre outro');
  // paga o 1º: Fundador #1 com 90 dias
  const ref = t.last('payment_charge').charge.id;
  await t.pay.apply({ providerRef: ref, status: 'paid', amountCents: 4490, currency: 'BRL' });
  let e = await t.store.getEntitlements('ana');
  const days = d => (new Date(d) - Date.now()) / 86400e3;
  check(e.is_founder && e.founder_number === 1 && e.founder_tier === 'founder' && days(e.club_expires_at) > 89 && days(e.club_expires_at) < 91, 'Fundador #1 com 90 dias de Club');
  await t.pay.apply({ providerRef: ref, status: 'paid', amountCents: 4490, currency: 'BRL' });
  e = await t.store.getEntitlements('ana');
  check(days(e.club_expires_at) < 91, 'aviso repetido não entrega duas vezes');
  await t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'founder', method: 'pix' });
  check(t.last('payment_error').code === 'already_founder', 'Fundador não compra Fundador de novo');
  await t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'founder_legend', method: 'card' });
  const ref2 = t.last('payment_charge').charge.id;
  await t.pay.apply({ providerRef: ref2, status: 'paid', amountCents: 9990, currency: 'BRL' });
  e = await t.store.getEntitlements('ana');
  check(e.founder_tier === 'legend' && e.founder_number === 1 && days(e.club_expires_at) > 454, 'Fundador vira Lendário, mantém o número e soma 365 dias');
  // Club anual para outra pessoa
  await t.pay.handle(t.ws('bia'), { type: 'payment_create', product_id: 'club_yearly', method: 'pix' });
  const ref3 = t.last('payment_charge').charge.id;
  check(t.last('payment_charge').charge.amount_cents === 13490, 'Club anual no PIX: R$ 134,90');
  // entrega falha → pedido continua pendente; na próxima notificação entrega
  t.store.failGrant = true;
  let threw = false; try { await t.pay.apply({ providerRef: ref3, status: 'paid', amountCents: 13490, currency: 'BRL' }); } catch (_) { threw = true; }
  check(threw && (await t.store.getPayment('fake', ref3)).status === 'pending', 'entrega falhou: pedido continua pendente (o provedor tenta de novo)');
  t.store.failGrant = false;
  await t.pay.apply({ providerRef: ref3, status: 'paid', amountCents: 13490, currency: 'BRL' });
  e = await t.store.getEntitlements('bia');
  check(e.club_active && !e.is_founder && days(e.club_expires_at) > 364, 'na nova tentativa: Club anual entregue (365 dias)');
  // reconciliação de pedido antigo "pago sem vantagem"
  t.store.payments.push({ provider: 'fake', provider_ref: 'velho', user_id: 'caio', product_id: 'club_monthly', status: 'paid', created_at: new Date().toISOString() });
  const rc = await t.pay.reconcile();
  check(rc.granted === 1 && (await t.store.getEntitlements('caio')).club_active, 'reconciliação entrega pagamento antigo sem vantagem');
  await t.pay.handle(t.ws('ana'), { type: 'payment_history' });
  const h = t.last('payment_history');
  check(h.items.length === 2 && h.items.every(i => i.status === 'paid') && /Lendário/.test(h.items[0].title), 'histórico de compras do jogador');
  // Fundador fora do prazo
  t = setup({ FRAIHA_FOUNDER_UNTIL: '2020-01-01' });
  await t.pay.handle(t.ws('dan'), { type: 'payment_offer' });
  check(t.last('payment_offer').founder_open === false, 'depois da data: Fundador fora de venda na oferta');
  await t.pay.handle(t.ws('dan'), { type: 'payment_create', product_id: 'founder', method: 'pix' });
  check(t.last('payment_error').code === 'founder_closed', 'depois da data: não cria pedido de Fundador');
  await t.pay.handle(t.ws('dan'), { type: 'payment_create', product_id: 'club_monthly', method: 'card' });
  check(t.last('payment_charge').charge.amount_cents === 1990, 'Club continua à venda (cartão R$ 19,90)');
  // Dono encerra a venda quando quiser (sem data)
  t = setup({ FRAIHA_FOUNDER_OPEN: 'nao' });
  await t.pay.handle(t.ws('eva'), { type: 'payment_offer' });
  check(t.last('payment_offer').founder_open === false && t.last('payment_offer').founder_until === null, 'FRAIHA_FOUNDER_OPEN=nao: Fundador encerrado sem precisar de data');
  t = setup({});
  await t.pay.handle(t.ws('eva'), { type: 'payment_offer' });
  check(t.last('payment_offer').founder_open === true && t.last('payment_offer').founder_until === null, 'sem configuração: Fundador à venda, por tempo limitado sem data');
  // R109 · Salão dos Fundadores: lista pública por número
  t = setup({});
  await t.store.createProfile('11111111-1111-4111-a111-111111111111', 'SalaoUm', 'warrior');
  await t.store.createProfile('22222222-2222-4222-a222-222222222222', 'SalaoDois', 'warrior');
  await t.store.grantEntitlement('22222222-2222-4222-a222-222222222222', 'founder_legend', 'pix');
  await t.store.grantEntitlement('11111111-1111-4111-a111-111111111111', 'founder', 'pix');
  await t.pay.handle({ readyState: 1 }, { type: 'payment_founders' });
  const fl = t.last('payment_founders');
  check(fl && fl.founders.length === 2 && fl.founders[0].nickname === 'SalaoDois' && fl.founders[0].tier === 'legend' && fl.founders[1].number === 2, 'Salão dos Fundadores: por número, com o nível (até para quem não entrou)');
  // Título "Fundador Lendário" só para o Lendário
  const Cos = require('../../online_v021/accounts/cosmetics.js');
  check(!!Cos.validate({ title: 'lendario' }, { is_founder: true, founder_tier: 'legend' }, []).ok, 'Lendário pode usar o título Fundador Lendário');
  check(Cos.validate({ title: 'lendario' }, { is_founder: true, founder_tier: 'founder' }, []).code === 'cosmetic_locked', 'Fundador comum não usa o título Lendário');
  check(Cos.effective({ profile_title: 'lendario' }, { is_founder: true, founder_tier: 'founder' }).title === '', 'título Lendário some se o direito não for Lendário');
  check(Cos.effective({ profile_title: 'lendario' }, { is_founder: true, founder_tier: 'legend' }).title === 'lendario', 'outros jogadores veem o título Lendário');
  console.error = quiet;
  console.log(`OFERTAS_R103 CHECKS=${checks} FAILURES=${fails}`); process.exitCode = fails ? 1 : 0;
})().catch(e => { console.log(e); process.exitCode = 1; });
