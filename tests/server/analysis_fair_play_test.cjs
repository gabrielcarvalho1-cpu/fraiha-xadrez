'use strict';
// S11: direct backend requests, real match registries, DevAuth/MemoryStore only.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { Position } = require('../../online_v021/chess_rules');

async function fixture(t, entitlements = {}) {
  const sent = [];
  let ws;
  const sockets = [];
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, msg) => { if (socket === ws) sent.push(msg); } });
  backend.attachRanked(new Ranked({ send: backend.send, now: () => 1000 }));
  backend.attachCasual(new Ranked({ send: backend.send, kind: 'casual', now: () => 1000 }));
  // Advance clocks explicitly; no background matchmaking or network services.
  backend.ranked.stop(); backend.casual.stop();
  t.after(() => {
    clearInterval(backend.sweeper);
    backend.presence.stop();
    backend.party.stop();
    backend.invites.stop();
    for (const socket of sockets) backend.onClose(socket);
  });
  const uid = 'analysis-player';
  await backend.store.createProfile(uid, 'AnalysisPlayer', 'warrior');
  await backend.store.setEntitlements(uid, entitlements);
  // A separate connection has no match ID or identity cache. The user ID is authoritative.
  backend.auth = { verify: async token => ({ id: token, provider: 'dev' }) };
  ws = { readyState: 1 }; sockets.push(ws);
  await backend.handle(ws, { type: 'acct_auth', access_token: uid });
  const players = new Map();
  for (const [id, nickname] of [[uid, 'AnalysisPlayer'], ['human-opponent', 'HumanOpponent'], ['human-friend', 'HumanFriend']]) {
    if (id !== uid) await backend.store.createProfile(id, nickname, 'warrior');
    const socket = { readyState: 1 }; sockets.push(socket); players.set(id, socket);
    await backend.handle(socket, { type: 'acct_auth', access_token: id });
  }
  const request = async (extra = {}) => {
    sent.length = 0;
    await backend.handle(ws, { type: 'analysis_request', ...extra });
    assert.equal(sent.length, 1);
    return sent[0];
  };
  return { backend, uid, ws, request, sent, players };
}

function startChess(f, kind) {
  const entry = userId => ({ userId, nickname: userId, avatar: 'warrior', stats: { league: 0, pl: 0 } });
  return f.backend[kind].startMatch(kind + '_3min', entry(f.uid), entry('human-opponent'), 1000);
}

function startParty(f, game) {
  return f.backend.party.start(game, [
    { user_id: f.uid, nickname: 'AnalysisPlayer' },
    { user_id: 'human-friend', nickname: 'HumanFriend' },
  ], { seed: 123 });
}

const modes = {
  ranked: f => startChess(f, 'ranked'),
  casual: f => startChess(f, 'casual'),
  marcha: f => startParty(f, 'marcha'),
  xeque: f => startParty(f, 'xeque'),
};
const tiers = { free: {}, founder: { is_founder: true }, club: { club_active: true } };

for (const [mode, start] of Object.entries(modes)) {
  for (const [tier, entitlements] of Object.entries(tiers)) {
    test(`${mode}: active human match denies analysis (${tier}), without consuming quota`, async t => {
      const f = await fixture(t, entitlements);
      const match = start(f);
      if (mode === 'ranked' || mode === 'casual') match.tick(match.startsAt);
      else assert.equal(match.seats.filter(s => s.kind === 'human').length, 2);
      assert.equal(f.backend.inMatch(f.uid), true);
      const msg = await f.request({ mode: 'bot', finished: true, user_id: 'someone-else' });
      assert.equal(msg.type, 'analysis_denied');
      assert.equal(msg.code, 'in_match');
      assert.equal(await f.backend.store.analysisUsage(f.uid, new Date().toISOString().slice(0, 10)), 0);
    });
  }
  test(`${mode}: finished match allows normal post-match analysis`, async t => {
    const f = await fixture(t);
    const match = start(f);
    if (mode === 'ranked' || mode === 'casual') match.resign('w', 1001);
    else f.backend.party.finish(match);
    assert.equal(f.backend.inMatch(f.uid), false);
    const msg = await f.request();
    assert.equal(msg.type, 'analysis_granted');
    assert.equal(msg.unlimited, false);
    assert.equal(msg.used, 1);
  });
}

test('starting and disconnected human matches still deny analysis', async t => {
  const f = await fixture(t);
  const match = startChess(f, 'casual');
  assert.equal(match.status, 'starting');
  for (const id of [f.uid, 'human-opponent']) {
    const socket = f.players.get(id);
    socket.readyState = 3;
    f.backend.onClose(socket);
  }
  assert.equal(match.players.w.connected, false);
  assert.equal(match.players.b.connected, false);
  assert.equal((await f.request()).code, 'in_match');
});

test('local bot game and bot service remain available', async t => {
  const f = await fixture(t);
  // Bot gameplay lives in the client, not Ranked/Casual/Party match registries.
  const botPosition = new Position();
  assert.ok(botPosition.play({ from: [4, 6], to: [4, 4] }));
  assert.equal(botPosition.outcome(), '');
  assert.equal(f.backend.inMatch(f.uid), false);
  assert.equal((await f.request({ mode: 'bot' })).type, 'analysis_granted');
  f.sent.length = 0;
  await f.backend.handle(f.ws, { type: 'bot_progress' });
  assert.equal(f.sent[0].type, 'bot_progress');
  assert.equal(f.sent[0].available, true);
});

test('outside a match: free quota and exhausted-quota denial are preserved', async t => {
  const f = await fixture(t);
  const ent = await f.backend.store.getEntitlements(f.uid);
  const { limit } = await f.backend.analysisSummary(f.uid, ent);
  assert.ok(limit > 0);
  for (let used = 1; used <= limit; used++) {
    const msg = await f.request();
    assert.equal(msg.type, 'analysis_granted');
    assert.equal(msg.used, used);
    assert.equal(msg.limit, limit);
    assert.equal(msg.unlimited, false);
    assert.ok(msg.resets_at);
  }
  assert.equal((await f.request()).code, 'quota');
});

test('outside a match: Club still grants unlimited analysis', async t => {
  const f = await fixture(t, tiers.club);
  assert.deepEqual(await f.request(), { type: 'analysis_granted', unlimited: true, used: 0, limit: 0, resets_at: null });
});

for (const tier of ['free', 'club']) {
  test(`PvP starting during entitlement lookup denies analysis (${tier})`, async t => {
    const f = await fixture(t, tiers[tier]);
    const getEntitlements = f.backend.store.getEntitlements.bind(f.backend.store);
    f.backend.store.getEntitlements = async uid => {
      const ent = await getEntitlements(uid);
      startChess(f, 'casual');
      return ent;
    };
    assert.equal((await f.request()).code, 'in_match');
    assert.equal(await f.backend.store.analysisUsage(f.uid, new Date().toISOString().slice(0, 10)), 0);
  });
}

test('PvP starting during quota consumption never receives an analysis grant', async t => {
  const f = await fixture(t);
  const consume = f.backend.store.analysisConsume.bind(f.backend.store);
  f.backend.store.analysisConsume = async (...args) => {
    const result = await consume(...args);
    startChess(f, 'ranked');
    return result;
  };
  assert.equal((await f.request()).code, 'in_match');
});
