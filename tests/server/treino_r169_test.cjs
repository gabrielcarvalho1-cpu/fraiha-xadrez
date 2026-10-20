'use strict';
// R169 · TREINE SEUS ERROS: 3 por dia sem Club; Club e Fundador ilimitado; convidado não treina.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const A = '11111111-1111-4111-a111-111111111111';
const F = '22222222-2222-4222-a222-222222222222';

test('treinos: 3 por dia; o 4º é negado; Fundador ilimitado; status conta', async t => {
  const out = [];
  const origLog = console.log; console.log = () => {}; t.after(() => { console.log = origLog; });
  const b = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (s, m) => out.push({ s, ...m }) });
  b.auth = { verify: async tok => { const m = /^tok-(.+)$/.exec(tok); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  b.attachRanked(new Ranked({ send: b.send })); b.attachCasual(new Ranked({ send: b.send, kind: 'casual' }));
  b.ranked.stop(); b.casual.stop(); clearInterval(b.sweeper); b.presence.stop(); b.invites.stop();
  t.after(() => b.party.stop());
  await b.store.createProfile(A, 'Alice', 'warrior');
  await b.store.createProfile(F, 'Fund', 'warrior');
  await b.store.setEntitlements(F, { is_founder: true });
  const sa = { readyState: 1 }, sf = { readyState: 1 }, sg = { readyState: 1 };
  await b.handle(sa, { type: 'acct_auth', access_token: 'tok-' + A });
  await b.handle(sf, { type: 'acct_auth', access_token: 'tok-' + F });
  const last = (s, ty) => out.filter(x => x.s === s && x.type.startsWith(ty)).pop();
  for (let i = 1; i <= 3; i++) {
    await b.handle(sa, { type: 'train_request' });
    const r = last(sa, 'train_');
    assert.equal(r.type, 'train_granted'); assert.equal(r.used, i); assert.equal(r.limit, 3);
  }
  await b.handle(sa, { type: 'train_request' });
  assert.equal(last(sa, 'train_').type, 'train_denied');
  assert.equal(last(sa, 'train_').code, 'quota');
  await b.handle(sa, { type: 'train_status' });
  assert.equal(last(sa, 'train_').used, 3);
  for (let i = 0; i < 5; i++) await b.handle(sf, { type: 'train_request' });
  const rf = last(sf, 'train_');
  assert.equal(rf.type, 'train_granted'); assert.equal(rf.unlimited, true);
  await b.handle(sg, { type: 'train_request' });
  const g = last(sg, 'train_');
  assert.ok(!g || g.code === 'auth_required', 'convidado nunca recebe treino liberado');
});
