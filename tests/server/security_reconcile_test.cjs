'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { IDS } = require('../../online_v021/bots/service');
const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const C = '33333333-3333-4333-a333-333333333333';
const user = id => ({ id, email: 'local@dev.invalid', provider: 'dev' });
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const flush = async () => { for (let count = 0; count < 100; count++) await Promise.resolve(); };
class Clock {
  time = 1700000000000;
  timers = new Map();
  now = () => this.time;
  set = (callback, delay) => { const timer = { callback, at: this.time + delay, unref() {} }; this.timers.set(timer, timer); return timer; };
  clear = timer => this.timers.delete(timer);
  async advance(delay) {
    const end = this.time + delay;
    for (;;) {
      const timer = [...this.timers.values()].filter(entry => entry.at <= end).sort((left, right) => left.at - right.at)[0];
      if (!timer) break;
      this.time = timer.at; this.timers.delete(timer); timer.callback(); await flush();
    }
    this.time = end; await flush();
  }
}
async function fixture(t) {
  const clock = new Clock(), messages = [], sockets = [A, B, C].map(() => ({ readyState: 1 }));
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }), now: clock.now, setTimer: clock.set, clearTimer: clock.clear });
  backend.auth = { verify: async token => [A, B, C].includes(token) ? user(token) : null };
  backend.attachRanked(new Ranked({ send: backend.send, now: clock.now }));
  backend.attachCasual(new Ranked({ send: backend.send, kind: 'casual', now: clock.now }));
  backend.ranked.stop(); backend.casual.stop(); clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  const login = (socket, id) => backend.handle(socket, { type: 'acct_auth', access_token: id });
  for (const [index, id] of [A, B, C].entries()) {
    await backend.store.createProfile(id, ['AliceTest', 'BobTest', 'CarolTest'][index], 'warrior');
    await login(sockets[index], id);
  }
  await backend.store.addFriendship(A, C);
  t.after(() => { for (const socket of sockets) backend.onClose(socket); backend.party.stop(); clock.timers.clear(); });
  const act = message => backend.handle(sockets[0], message);
  return { backend, clock, messages, sockets, login, act };
}
test('combined Ranked: pending Auth never enqueues stats completion', async t => {
  const h = await fixture(t), stats = deferred(), auth = deferred();
  const get = h.backend.store.getRankedStats.bind(h.backend.store);
  h.backend.store.getRankedStats = id => id === A ? stats.promise : get(id);
  const request = h.act({ type: 'ranked_queue', mode: 'ranked_3min' }); await flush();
  h.backend.auth.verify = token => token === A ? auth.promise : Promise.resolve(user(token));
  await h.clock.advance(60000); stats.resolve(await get(A)); await flush();
  assert.equal(h.backend.ranked.mm.has(A), false);
  auth.resolve(user(A)); await request;
  assert.equal(h.backend.ranked.mm.has(A), true);
});
test('combined Ranked: suspended participant and opponent remain queued until Auth', async t => {
  const h = await fixture(t), auth = deferred();
  await h.act({ type: 'ranked_queue', mode: 'ranked_3min' });
  await h.backend.handle(h.sockets[1], { type: 'ranked_queue', mode: 'ranked_3min' });
  h.backend.auth.verify = token => token === A ? auth.promise : Promise.resolve(user(token));
  await h.clock.advance(60000); h.backend.ranked.tick();
  assert.equal(h.backend.ranked.matches.size, 0);
  assert.equal(h.backend.ranked.mm.has(A), true); assert.equal(h.backend.ranked.mm.has(B), true);
  auth.resolve(user(A)); await flush(); h.backend.ranked.tick();
  assert.equal(h.backend.ranked.matches.size, 1);
});
for (const service of ['bot', 'dm', 'invite', 'social']) {
  test(`delegate ${service}: identity swap after read starts no new write or third-party broadcast`, async t => {
    const h = await fixture(t), slow = deferred(), writes = [];
    let request, resolve;
    if (service === 'bot') {
      const get = h.backend.store.getBotProgress.bind(h.backend.store);
      h.backend.store.getBotProgress = id => id === A ? slow.promise : get(id);
      h.backend.store.recordBotVictory = async id => { writes.push(id); return true; };
      request = h.act({ type: 'bot_victory', bot_id: IDS[0], human_color: 'b', moves: ['f2f3', 'e7e5', 'g2g4', 'd8h4'] });
      resolve = [];
    } else {
      const get = h.backend.store.getRelations.bind(h.backend.store);
      h.backend.store.getRelations = id => id === A ? slow.promise : get(id);
      resolve = await get(A);
      if (service === 'dm') {
        h.backend.store.addDirectMessage = async (...args) => { writes.push(args); return { id: 1 }; };
        request = h.act({ type: 'dm_send', user_id: C, text: 'hello' });
      }
      if (service === 'invite') request = h.act({ type: 'invite_send', user_id: C, mode: 'casual_3min' });
      if (service === 'social') {
        h.backend.store.addRequest = async (...args) => { writes.push(args); };
        request = h.act({ type: 'social_request', user_id: B });
      }
    }
    await flush(); await h.login(h.sockets[0], B); const count = h.messages.length;
    slow.resolve(resolve); await request;
    assert.deepEqual(writes, []); assert.equal(h.backend.invites.invites.size, 0);
    assert.equal(h.messages.length, count);
  });
}

async function change(h, reason, pending) {
  if (reason === 'swap') await h.login(h.sockets[0], B);
  if (reason === 'aba') { await h.login(h.sockets[0], B); await h.login(h.sockets[0], A); }
  if (reason === 'refresh') await h.login(h.sockets[0], A);
  if (reason === 'logout') await h.act({ type: 'acct_logout' });
  if (reason === 'close') { h.sockets[0].readyState = 3; h.backend.onClose(h.sockets[0]); }
  if (reason === 'invalid') await h.login(h.sockets[0], 'invalid');
  if (reason === 'cancel') await h.act({ type: 'ranked_cancel' });
  if (reason === 'exp') {
    const session = h.backend.session(h.sockets[0]); session.expiresAt = h.clock.now() + 1;
    h.backend.armSession(h.sockets[0], session.revision); await h.clock.advance(1);
  }
  if (reason === 'rejected' || reason === 'timeout' || reason === 'valid') {
    h.backend.auth.verify = token => token === A ? pending.promise : Promise.resolve(user(token));
    await h.clock.advance(60000);
    if (reason === 'timeout') await h.clock.advance(10000);
  }
}
for (const reason of ['swap', 'aba', 'refresh', 'logout', 'close', 'invalid', 'cancel', 'exp', 'rejected', 'timeout', 'valid']) {
  test(`combined Ranked stats → ${reason}: latest intention and authority`, async t => {
    const h = await fixture(t), stats = deferred(), auth = deferred();
    const get = h.backend.store.getRankedStats.bind(h.backend.store); let first = true;
    h.backend.store.getRankedStats = id => id === A && first ? (first = false, stats.promise) : get(id);
    const request = h.act({ type: 'ranked_queue', mode: 'ranked_3min' }); await flush();
    await change(h, reason, auth); stats.resolve(await get(A)); await flush();
    assert.equal(h.backend.ranked.mm.has(A), false);
    const count = h.messages.length;
    auth.resolve(reason === 'valid' ? user(A) : null); await request; await flush();
    assert.equal(h.backend.ranked.mm.has(A), reason === 'valid');
    assert.equal(h.backend.ranked.matches.size, 0);
    if (!['valid', 'rejected'].includes(reason)) assert.equal(h.messages.length, count);
  });
}
for (const reason of ['rejected', 'timeout', 'exp']) {
  test(`combined Ranked pairing → ${reason}: preserve healthy opponent`, async t => {
    const h = await fixture(t), auth = deferred();
    await h.act({ type: 'ranked_queue', mode: 'ranked_3min' });
    await h.backend.handle(h.sockets[1], { type: 'ranked_queue', mode: 'ranked_3min' });
    await change(h, reason, auth);
    h.backend.ranked.tick();
    assert.equal(h.backend.ranked.matches.size, 0); assert.equal(h.backend.ranked.mm.has(B), true);
    if (reason === 'rejected') { assert.equal(h.backend.ranked.mm.has(A), true); auth.resolve(null); await flush(); }
    else auth.resolve(user(A));
    h.backend.ranked.tick();
    assert.equal(h.backend.ranked.mm.has(A), false); assert.equal(h.backend.ranked.mm.has(B), true);
    await h.backend.handle(h.sockets[2], { type: 'ranked_queue', mode: 'ranked_3min' });
    h.backend.ranked.tick();
    assert.equal(h.backend.ranked.activeMatchOf(B), h.backend.ranked.activeMatchOf(C));
    assert.ok(h.backend.ranked.activeMatchOf(B));
  });
}
test('combined Ranked: direct startMatch rejects due, pending and expired sessions before mutation', async t => {
  const h = await fixture(t), auth = deferred();
  const entry = id => ({ userId: id, nickname: id, stats: { pl: 0, league: 0 } });
  h.backend.session(h.sockets[0]).revalidateAt = h.clock.now();
  assert.throws(() => h.backend.ranked.startMatch('ranked_3min', entry(A), entry(B)), { code: 'player_unavailable' });
  h.backend.auth.verify = () => auth.promise; const revalidate = h.backend.ensureSession(h.sockets[0]); await flush();
  assert.throws(() => h.backend.ranked.startMatch('ranked_3min', entry(A), entry(B)), { code: 'player_unavailable' });
  auth.resolve(user(A)); await revalidate;
  h.backend.session(h.sockets[0]).expiresAt = h.clock.now();
  assert.throws(() => h.backend.ranked.startMatch('ranked_3min', entry(A), entry(B)), { code: 'player_unavailable' });
  assert.equal(h.backend.ranked.byUser.size, 0); assert.equal(h.backend.ranked.matches.size, 0);
});
for (const service of ['bot', 'dm', 'invite', 'social']) {
  for (const reason of ['logout', 'close', 'aba', 'refresh', 'exp', 'rejected', 'timeout', 'valid']) {
    test(`delegate ${service} paused → ${reason}: guard store, maps and every recipient`, async t => {
      const h = await fixture(t), slow = deferred(), auth = deferred(), writes = [];
      const method = service === 'bot' ? 'getBotProgress' : 'getRelations';
      const read = h.backend.store[method].bind(h.backend.store); let first = true;
      const result = await read(A);
      h.backend.store[method] = id => id === A && first ? (first = false, slow.promise) : read(id);
      const write = service === 'bot' ? 'recordBotVictory' : service === 'dm' ? 'addDirectMessage' : service === 'social' ? 'addRequest' : null;
      if (write) {
        const original = h.backend.store[write].bind(h.backend.store);
        h.backend.store[write] = (...args) => { writes.push(args); return original(...args); };
      }
      const messages = {
        bot: { type: 'bot_victory', bot_id: IDS[0], human_color: 'b', moves: ['f2f3', 'e7e5', 'g2g4', 'd8h4'] },
        dm: { type: 'dm_send', user_id: C, text: 'hello' },
        invite: { type: 'invite_send', user_id: C, mode: 'casual_3min' },
        social: { type: 'social_request', user_id: B },
      };
      const request = h.act(messages[service]); await flush(); await change(h, reason, auth);
      slow.resolve(result); await flush();
      assert.deepEqual(writes, []); assert.equal(h.backend.invites.invites.size, 0);
      const count = h.messages.length;
      auth.resolve(reason === 'valid' ? user(A) : null); await request; await flush();
      if (reason === 'valid') {
        if (write) { assert.equal(writes.length, 1); assert.equal(writes[0][0], A); }
        else assert.equal(h.backend.invites.invites.size, 1);
        const outgoing = h.messages.filter(message => message.type === 'invite_received' || (message.type === 'dm_msg' && message.from));
        for (const message of outgoing) assert.equal((message.from || message.invite.from).nickname, 'AliceTest');
      } else {
        assert.deepEqual(writes, []); assert.equal(h.backend.invites.invites.size, 0);
        if (reason !== 'rejected') assert.equal(h.messages.length, count);
      }
    });
  }
}
for (const service of ['bot', 'dm', 'social']) {
  test(`delegate ${service}: write already started persists for A, no continuation after swap`, async t => {
    const h = await fixture(t), slow = deferred(), writes = [];
    const method = service === 'bot' ? 'recordBotVictory' : service === 'dm' ? 'addDirectMessage' : 'removeRequest';
    const original = h.backend.store[method].bind(h.backend.store);
    if (service === 'social') { await h.backend.store.removeFriendship(A, C); await h.backend.store.addRequest(C, A); }
    h.backend.store[method] = async (...args) => { writes.push(args); const result = await original(...args); await slow.promise; return result; };
    let subsequent = 0;
    if (service === 'social') h.backend.store.addFriendship = async () => { subsequent++; };
    const message = service === 'bot' ? { type: 'bot_victory', bot_id: IDS[0], human_color: 'b', moves: ['f2f3', 'e7e5', 'g2g4', 'd8h4'] }
      : service === 'dm' ? { type: 'dm_send', user_id: C, text: 'already authorized' }
        : { type: 'social_accept', user_id: C };
    const request = h.act(message); await flush(); assert.equal(writes.length, 1);
    await h.login(h.sockets[0], B); const count = h.messages.length;
    slow.resolve(); await request;
    assert.equal(h.messages.length, count); assert.equal(subsequent, 0);
    if (service === 'bot') assert.equal((await h.backend.store.getBotProgress(A)).length, 1);
    if (service === 'dm') assert.equal((await h.backend.store.getConversation(A, C, 50, 0)).length, 1);
  });
}
for (const kind of ['queue', 'ranked', 'casual', 'party']) {
  test(`refresh same UID preserves ${kind} through Auth and slow store`, async t => {
    const h = await fixture(t);
    let match;
    if (kind === 'queue' || kind === 'ranked') {
      await h.act({ type: 'ranked_queue', mode: 'ranked_3min' });
      if (kind === 'ranked') { await h.backend.handle(h.sockets[1], { type: 'ranked_queue', mode: 'ranked_3min' }); h.backend.ranked.tick(); match = h.backend.ranked.activeMatchOf(A); }
    }
    if (kind === 'casual') {
      await h.act({ type: 'casual_queue', mode: 'casual_3min' }); await h.backend.handle(h.sockets[1], { type: 'casual_queue', mode: 'casual_3min' }); h.backend.casual.tick(); match = h.backend.casual.activeMatchOf(A);
    }
    if (kind === 'party') match = h.backend.party.start('xeque', [{ user_id: A, nickname: 'AliceTest' }, { user_id: B, nickname: 'BobTest' }], { seed: 123 });
    const auth = deferred(), store = deferred(), get = h.backend.store.getProfile.bind(h.backend.store);
    h.backend.auth.verify = token => token === A ? auth.promise : Promise.resolve(user(token));
    h.backend.store.getProfile = id => id === A ? store.promise : get(id);
    const revision = h.backend.session(h.sockets[0]).revision;
    const refresh = h.login(h.sockets[0], A); await flush();
    assert.equal(h.backend.session(h.sockets[0]).revision, revision + 1); assert.equal(h.backend.ready(h.sockets[0]), false);
    if (kind === 'queue') { h.backend.ranked.tick(); assert.equal(h.backend.ranked.mm.has(A), true); }
    else {
      const seat = kind === 'party' ? match.seats.find(entry => entry.uid === A) : match.players[match.colorOf(A)];
      assert.equal(seat.connected, true); assert.equal(seat.leftAt || seat.away_since || 0, 0);
    }
    auth.resolve(user(A)); await flush(); assert.equal(h.backend.ready(h.sockets[0]), true);
    if (kind === 'queue') assert.equal(h.backend.ranked.mm.has(A), true);
    else assert.equal(h.backend.inMatch(A), true);
    store.resolve(await get(A)); await refresh;
    assert.equal(h.sockets[0].identity.id, A);
    if (kind === 'queue') assert.equal(h.backend.ranked.mm.has(A), true);
    else assert.equal((kind === 'party' ? match.seats.find(entry => entry.uid === A) : match.players[match.colorOf(A)]).connected, true);
  });
}
for (const reason of ['invalid', 'logout', 'close', 'swap']) {
  test(`refresh attempted → ${reason}: cleanup and no old authorization restored`, async t => {
    const h = await fixture(t), auth = deferred();
    await h.act({ type: 'ranked_queue', mode: 'ranked_3min' });
    h.backend.auth.verify = token => token === A ? auth.promise : token === B ? Promise.resolve(user(B)) : Promise.resolve(null);
    const refresh = h.login(h.sockets[0], A); await flush();
    await change(h, reason); auth.resolve(user(A)); await refresh;
    assert.equal(h.backend.ranked.mm.has(A), false);
    assert.equal(h.sockets[0].user && h.sockets[0].user.id, reason === 'swap' ? B : null);
  });
}
test('refresh Auth exception and timeout invalidate retained queue', async t => {
  const h = await fixture(t);
  await h.act({ type: 'ranked_queue', mode: 'ranked_3min' });
  h.backend.auth.verify = async () => { throw new Error('local auth failure'); };
  await h.login(h.sockets[0], A);
  assert.equal(h.sockets[0].identity, null); assert.equal(h.backend.ranked.mm.has(A), false);
  h.backend.auth.verify = async () => user(A); await h.login(h.sockets[0], A);
  await h.act({ type: 'ranked_queue', mode: 'ranked_3min' });
  const auth = deferred(); h.backend.auth.verify = () => auth.promise;
  const refresh = h.login(h.sockets[0], A); await flush(); await h.clock.advance(10000); await refresh;
  assert.equal(h.sockets[0].identity, null); assert.equal(h.backend.ranked.mm.has(A), false);
  auth.resolve(user(A)); await flush(); assert.equal(h.sockets[0].identity, null);
});
test('cancel while Auth is pending immediately cancels old intent and never restores it', async t => {
  const h = await fixture(t), stats = deferred(), auth = deferred();
  const get = h.backend.store.getRankedStats.bind(h.backend.store);
  h.backend.store.getRankedStats = () => stats.promise;
  const request = h.act({ type: 'ranked_queue', mode: 'ranked_3min' }); await flush();
  h.backend.auth.verify = token => token === A ? auth.promise : Promise.resolve(user(token));
  await h.clock.advance(60000);
  await h.act({ type: 'ranked_cancel' });
  assert.equal(h.messages.at(-1).type, 'ranked_cancelled');
  stats.resolve(await get(A)); await flush(); auth.resolve(user(A)); await request;
  assert.equal(h.backend.ranked.mm.has(A), false);
  assert.equal(h.messages.some(message => message.type === 'ranked_queued' && message.socket === h.sockets[0]), false);
});
for (const reason of ['swap', 'aba', 'logout', 'close', 'rejected', 'valid']) {
  test(`invite accept reserved → ${reason}: actor revision, sockets and cleanup`, async t => {
    const h = await fixture(t), slow = deferred(), auth = deferred();
    await h.act({ type: 'invite_send', user_id: C, mode: 'casual_3min' });
    const invitation = h.backend.invites.openOf(A);
    const get = h.backend.store.getRelations.bind(h.backend.store); let first = true;
    h.backend.store.getRelations = id => id === C && first ? (first = false, slow.promise) : get(id);
    const acceptance = h.backend.handle(h.sockets[2], { type: 'invite_accept', invite_id: invitation.id }); await flush();
    assert.equal(invitation.status, 'starting'); assert.equal(h.backend.invites.reserved(A), true);
    if (['swap', 'aba', 'logout', 'close'].includes(reason)) {
      if (reason === 'swap' || reason === 'aba') await h.login(h.sockets[2], B);
      if (reason === 'aba') await h.login(h.sockets[2], C);
      if (reason === 'logout') await h.backend.handle(h.sockets[2], { type: 'acct_logout' });
      if (reason === 'close') { h.sockets[2].readyState = 3; h.backend.onClose(h.sockets[2]); }
      const other = { readyState: 1 }; h.sockets.push(other); await h.login(other, C);
    } else {
      h.backend.auth.verify = token => token === C ? auth.promise : Promise.resolve(user(token));
      await h.clock.advance(60000);
    }
    slow.resolve(await get(C)); await flush();
    assert.equal(h.backend.casual.matches.size, 0);
    auth.resolve(reason === 'valid' ? user(C) : null); await acceptance;
    assert.equal(invitation.status, reason === 'valid' ? 'accepted' : 'failed');
    assert.equal(h.backend.invites.reserved(A), false); assert.equal(h.backend.invites.reserved(C), false);
    assert.equal(h.backend.casual.matches.size, reason === 'valid' ? 1 : 0);
  });
}
for (const pause of ['entitlements', 'quota', 'auth']) {
  for (const reason of ['swap', 'logout', 'close', 'rejected']) {
    test(`analysis paused at ${pause} → ${reason}: never grants old authority`, async t => {
      const h = await fixture(t), slow = deferred(), auth = deferred();
      let request;
      if (pause === 'auth') {
        h.backend.auth.verify = token => token === A ? auth.promise : Promise.resolve(user(token));
        await h.clock.advance(60000); request = h.act({ type: 'analysis_request' });
      } else {
        const method = pause === 'entitlements' ? 'getEntitlements' : 'analysisConsume';
        const original = h.backend.store[method].bind(h.backend.store); let first = true;
        h.backend.store[method] = (...args) => args[0] === A && first ? (first = false, slow.promise) : original(...args);
        request = h.act({ type: 'analysis_request' });
      }
      await flush();
      if (reason === 'rejected') {
        if (pause !== 'auth') { h.backend.auth.verify = token => token === A ? auth.promise : Promise.resolve(user(token)); await h.clock.advance(60000); }
      } else await change(h, reason);
      slow.resolve(pause === 'quota' ? { ok: true, used: 1 } : { club_active: false });
      auth.resolve(reason === 'rejected' ? null : user(A)); await request;
      assert.equal(h.messages.some(message => message.type === 'analysis_granted'), false);
      assert.equal(h.backend.inMatch(A), false);
    });
  }
}
for (const pause of ['entitlements', 'quota']) {
  for (const club of pause === 'entitlements' ? [false, true] : [false]) {
    test(`analysis ${pause} includes extra Auth await: another socket starts PvP (club=${club})`, async t => {
      const h = await fixture(t), slow = deferred(), auth = deferred();
      await h.backend.store.setEntitlements(A, { club_active: club });
      const method = pause === 'entitlements' ? 'getEntitlements' : 'analysisConsume';
      h.backend.store[method] = () => slow.promise;
      const request = h.act({ type: 'analysis_request' }); await flush();
      h.backend.auth.verify = token => token === A ? auth.promise : Promise.resolve(user(token));
      await h.clock.advance(60000);
      slow.resolve(pause === 'quota' ? { ok: true, used: 1 } : { club_active: club }); await flush();
      assert.equal(h.messages.some(message => message.type === 'analysis_granted'), false);
      const other = { readyState: 1 }; h.sockets.push(other);
      h.backend.auth.verify = async token => user(token);
      const ent = h.backend.store.getEntitlements;
      h.backend.store.getEntitlements = async () => ({ club_active: club });
      await h.login(other, A); h.backend.store.getEntitlements = ent;
      const entry = id => ({ userId: id, nickname: id, stats: { pl: 0, league: 0 } });
      h.backend.ranked.startMatch('ranked_3min', entry(A), entry(B));
      auth.resolve(user(A)); await request;
      assert.equal(h.messages.some(message => message.type === 'analysis_granted'), false);
      assert.equal(h.messages.filter(message => message.socket === h.sockets[0] && message.type === 'analysis_denied').at(-1).code, 'in_match');
    });
  }
}
test('account continuation invalidated between checked completion and write dispatch starts no new write', async t => {
  const h = await fixture(t);
  const checked = h.backend.checked.bind(h.backend);
  const get = h.backend.store.getEntitlements.bind(h.backend.store);
  h.backend.store.getEntitlements = async id => ({ ...(await get(id)), race_marker: true });
  let armed = true, writes = 0;
  h.backend.checked = async (...args) => {
    const value = await checked(...args);
    if (armed && value && value.race_marker) {
      armed = false;
      queueMicrotask(() => h.backend.handle(h.sockets[0], { type: 'acct_logout' }));
    }
    return value;
  };
  h.backend.store.setCosmetics = async () => { writes++; return { profile: {} }; };
  await h.act({ type: 'acct_set_cosmetics', badge: '' });
  assert.equal(writes, 0); assert.equal(h.sockets[0].user, null);
});
test('explicit token renewal always verifies Auth freshly; valid game actions do not', async t => {
  const h = await fixture(t), calls = [];
  h.backend.auth.verify = async (token, options) => { calls.push({ token, options }); return user(token); };
  await h.login(h.sockets[0], A); await h.login(h.sockets[0], A);
  assert.equal(calls.length, 2); assert.equal(calls.every(call => call.options.force === true), true);
  await h.act({ type: 'ranked_queue', mode: 'ranked_3min' });
  await h.act({ type: 'ranked_cancel' }); await h.act({ type: 'acct_refresh' });
  assert.equal(calls.length, 2);
});
