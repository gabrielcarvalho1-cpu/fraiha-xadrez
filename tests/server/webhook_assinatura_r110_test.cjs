'use strict';
// R110 · aviso do Mercado Pago sem assinatura: recusado com FRAIHA_MP_REQUIRE_SIGNATURE=1; sem a variável continua
// aceito (vai para a consulta na API) e fica no log. Assinatura errada é sempre recusada.
const crypto = require('crypto');
const { MercadoPago } = require('../../online_v021/payments/providers/mercadopago');
let checks = 0, fails = 0;
const check = (ok, l) => { checks++; if (!ok) fails++; console.log((ok ? 'PASS ' : 'FAIL ') + l); };
const req = (headers = {}) => ({ url: '/webhooks/payments?type=payment&data.id=12345', headers });
(async () => {
  const warn = console.warn; const warned = []; console.warn = m => warned.push(m);
  const base = { FRAIHA_MP_ACCESS_TOKEN: 'TEST', FRAIHA_MP_WEBHOOK_SECRET: 'segredo' };
  const soft = new MercadoPago(base); soft.lookup = async id => ({ providerRef: 'r', status: 'paid', id });
  check((await soft.verifyWebhook(req(), '')).id === '12345' && warned.length === 1, 'sem a exigência: aviso sem assinatura segue para a consulta e fica no log');
  const hard = new MercadoPago({ ...base, FRAIHA_MP_REQUIRE_SIGNATURE: '1' }); hard.lookup = soft.lookup;
  check(await hard.verifyWebhook(req(), '') === null, 'com FRAIHA_MP_REQUIRE_SIGNATURE=1: aviso sem assinatura é recusado');
  check(await hard.verifyWebhook(req({ 'x-signature': 'ts=1,v1=abc' }), '') === null, 'assinatura errada é recusada');
  const ts = '1700000000', v1 = crypto.createHmac('sha256', 'segredo').update('id:12345;ts:' + ts + ';').digest('hex');
  check((await hard.verifyWebhook(req({ 'x-signature': `ts=${ts},v1=${v1}` }), '')).id === '12345', 'assinatura certa é aceita');
  const nosecret = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'TEST', FRAIHA_MP_REQUIRE_SIGNATURE: '1' }); nosecret.lookup = soft.lookup;
  check((await nosecret.verifyWebhook(req(), '')).id === '12345', 'sem segredo configurado a exigência não trava os pagamentos');
  console.warn = warn;
  // R110 · Admin Log no banco
  const { AuditLog } = require('../../online_v021/admin/audit');
  const db = [{ id: 'a1', at: '2026-10-01T00:00:00Z', action: 'queue_off', actor: { name: 'boss' } }];
  const store = { insertAudit: async e => { db.unshift(e); }, listAudit: async () => db.slice() };
  const log = new AuditLog({ store, log: () => {} });
  await log.ready;
  check(log.persistent && log.list({ limit: 10 }).some(e => e.id === 'a1'), 'Admin Log carrega o que estava no banco ao subir');
  log.record({ actor: { id: 'x', name: 'boss', role: 'owner' }, action: 'player_suspend', reason: 'teste' });
  await new Promise(r => setImmediate(r));
  check(db.length === 2 && db[0].action === 'player_suspend', 'cada ação nova é gravada no banco');
  const err = new Error('relation "public.admin_audit" does not exist'); err.code = '42P01';
  const noTable = new AuditLog({ store: { insertAudit: async () => { throw err; }, listAudit: async () => { throw err; } }, log: () => {} });
  await noTable.ready;
  noTable.record({ action: 'x' });
  check(!noTable.persistent && noTable.list().length === 1, 'sem a 0015: continua na memória, sem erro');
  console.log(`WEBHOOK_R110 CHECKS=${checks} FAILURES=${fails}`); process.exitCode = fails ? 1 : 0;
})();
