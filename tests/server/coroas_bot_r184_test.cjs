'use strict';
// R184e · Coroas da 1ª vitória contra cada bot do Desafio das Ligas: Madeira 50, +25 por bot, Challenger 300; uma vez só.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Crowns, botCrowns } = require('../../online_v021/economy/crowns');
const LADDER = require('../../bot/bot_ladder.json');

test('tabela: Madeira 50 … Challenger 300', () => {
  assert.equal(botCrowns(0), 50);
  assert.equal(botCrowns(1), 75);
  assert.equal(botCrowns(LADDER.bots.length - 1), 300);
  assert.equal(botCrowns(-1), 0);
});

test('paga uma vez por (conta, bot) e avisa o jogador', async () => {
  const ledger = new Set(); const sent = [];
  const store = {
    crownAward: async (uid, d, reason, ref) => { const k = uid + reason + ref; if (ledger.has(k)) return null; ledger.add(k); return 1; },
    crownWallet: async () => ({ balance: 50 }), crownDaily: async () => ({}), crownLedger: async () => [],
  };
  const ws = { user: { id: '11111111-1111-4111-8111-111111111111' } };
  const backend = { store, socketsOf: () => [ws] };
  const c = new Crowns({ backend, send: (w, o) => sent.push(o) });
  const uid = ws.user.id;
  assert.deepEqual(await c.onBotWin(uid, 'madeira', 0, 'BOT MADEIRA'), { gained: 50 });
  assert.equal(await c.onBotWin(uid, 'madeira', 0, 'BOT MADEIRA'), null, 'segunda vez não paga');
  const r = sent.find(o => o.type === 'crowns_reward');
  assert.ok(r && r.gained === 50 && /BOT MADEIRA \+50/.test(r.lines[0]));
  assert.equal(await c.onBotWin('nao-uuid', 'ferro', 1), null);
});
