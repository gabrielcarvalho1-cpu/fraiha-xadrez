'use strict';
// R171 · causa dos 13 testes de sessão que falhavam desde R112: a "entrada do dia" das Coroas rodava solta depois
// do login. Além de chegar fora de ordem, ela lia as conexões ANTES de esperar o banco e mandava o saldo para quem
// estivesse nelas depois — inclusive se a pessoa tivesse saído e OUTRA conta entrado no mesmo aparelho.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';

test('entrada do dia de A não chega à conta B que entrou no mesmo aparelho enquanto o banco respondia', async t => {
  const out = [];
  const origLog = console.log; console.log = () => {}; t.after(() => { console.log = origLog; });
  const be = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (ws, m) => out.push({ ws, ...m }) });
  clearInterval(be.sweeper); be.presence.stop();
  t.after(() => be.party.stop());
  be.auth = { verify: async tok => tok === 'A' ? { id: A, email: 'a@x', provider: 'dev' } : tok === 'B' ? { id: B, email: 'b@x', provider: 'dev' } : null };
  await be.store.createProfile(A, 'AliceTest', 'warrior');
  await be.store.createProfile(B, 'BobTest', 'warrior');
  await be.store.crownAward(A, 5000, 'admin', 'marca');   // saldo de A é inconfundível (5010 depois da entrada do dia)
  let release;
  const slow = new Promise(r => { release = r; });
  const orig = be.store.crownWallet.bind(be.store);
  be.store.crownWallet = async uid => { if (uid === A) await slow; return orig(uid); };   // o banco demora para A
  const ws = { readyState: 1 };
  const loginA = be.handle(ws, { type: 'acct_auth', access_token: 'A' });
  for (let i = 0; i < 300; i++) await Promise.resolve();
  await be.handle(ws, { type: 'acct_logout' });
  await be.handle(ws, { type: 'acct_auth', access_token: 'B' });
  assert.equal(ws.user.id, B);
  release(); await loginA; await new Promise(r => setTimeout(r, 30));
  const cut = out.findIndex(x => x.type === 'acct_logged_out');
  const leaked = out.slice(cut + 1).filter(m => m.ws === ws && m.type && m.type.startsWith('crowns_') && Number(m.balance) >= 5000);
  assert.equal(leaked.length, 0, 'o saldo de A não aparece para B: ' + JSON.stringify(leaked.map(m => [m.type, m.balance])));
});
