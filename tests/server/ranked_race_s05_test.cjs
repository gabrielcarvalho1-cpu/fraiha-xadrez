'use strict';
// S05 race regressions. Run: node --test tests/server/ranked_race_s05_test.cjs
// Assert safe behavior; the original 7 failures reproduce on base dddf4f8.
// Real Backend routing, busy checks, cleanup, MatchService and Matchmaker;
// authenticated socket fakes, MemoryStore, manually released stats promises/ticks.
// No server, credentials, network, sleeps or production-code patches.
const assert = require('node:assert/strict');
const { test, before, after, mock } = require('node:test');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { MODES } = require('../../online_v021/ranked/config');

before(() => {
  const deny = () => { throw new Error('S05 tests forbid network access'); };
  mock.method(globalThis, 'fetch', deny);
  mock.method(require('node:http'), 'request', deny);
  mock.method(require('node:https'), 'request', deny);
  mock.method(require('node:net').Socket.prototype, 'connect', deny);
  mock.method(Math, 'random', () => 0);
});
after(() => mock.restoreAll());

function deferred() {
  let resolve, reject;
  const promise = new Promise((r, j) => { resolve = r; reject = j; });
  return { promise, resolve, reject };
}
function stats() {
  return Object.fromEntries(Object.keys(MODES).map(mode => [mode, {
    league: 0, pl: 0, matches: 0, wins: 0, losses: 0, draws: 0, highest_league: 0,
  }]));
}
function harness(t) {
  const send = (ws, msg) => {
    // Same closed-socket policy and JSON serialization as server.js send().
    if (ws && ws.readyState === 1) ws.sent.push(JSON.parse(JSON.stringify(msg)));
  };
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send });
  const cfg = {
    baseMs: () => 300000, startDelayMs: 0, reconnectGraceMs: 60000, tickMs: 200,
    matchmaking: { initialPlWindow: 20, expandEveryMs: 10000, expandStep: 40, maxWindow: 1100 },
  };
  const ranked = new Ranked({ send, cfg, now: () => 1000 });
  const casual = new Ranked({ send, cfg, now: () => 1000, kind: 'casual' });
  backend.attachRanked(ranked);
  backend.attachCasual(casual);
  // No automatic ticks: every matchmaking step in these tests is explicit.
  const stop = () => {
    ranked.stop(); casual.stop(); backend.invites.stop(); backend.presence.stop();
    backend.party.stop(); clearInterval(backend.sweeper);
  };
  stop(); t.after(stop);
  const reads = [];
  backend.store.getRankedStats = uid => {
    const read = { uid, ...deferred() };
    reads.push(read);
    return read.promise;
  };
  const handle = (ws, type, mode) => backend.handle(ws, { type, ...(mode ? { mode } : {}) });
  const queue = (ws, mode = 'ranked_3min') => {
    const before = reads.length;
    const completion = handle(ws, 'ranked_queue', mode);
    assert.equal(reads.length, before + 1, 'request must reach the deferred stats read');
    assert.equal(reads[before].uid, ws.user.id);
    return { completion, read: reads[before] };
  };
  const release = async request => { request.read.resolve(stats()); await request.completion; };
  const socket = name => {
    const ws = { readyState: 1, sent: [], user: { id: 's05-' + name },
      profile: { nickname: name, avatar_id: 'warrior' } };
    backend.store.stats.set(ws.user.id, stats()); // fixture real do MemoryStore para finalizar partidas
    backend.setIdentity(ws, { id: ws.user.id, nickname: name, avatar: 'warrior', guest: false });
    return ws;
  };
  const state = ws => {
    const uid = 's05-' + ws.profileName;
    const queues = g => [...g.mm.queues].filter(([, q]) => q.some(e => e.userId === uid)).map(([mode]) => mode);
    // Enumerate matches, not just byUser: a second match can hide the first index.
    const active = g => [...g.matches.values()].filter(m => m.status !== 'finished' && m.colorOf(uid) !== null);
    return {
      rankedQueues: queues(ranked), casualQueues: queues(casual),
      rankedMatches: active(ranked).map(m => m.id), casualMatches: active(casual).map(m => m.id),
      rankedByUser: ranked.byUser.get(uid) || null, casualByUser: casual.byUser.get(uid) || null,
      rankedSocketRegistered: ranked.sockets.get(uid) === ws,
      authenticated: !!ws.user, online: backend.online.has(uid),
    };
  };
  const account = name => { const ws = socket(name); ws.profileName = name; return ws; };
  const trace = (ws, label) => t.diagnostic(JSON.stringify({ step: label, state: state(ws), messages: ws.sent.map(m => ({
    type: m.type, ...(m.code ? { code: m.code } : {}),
    ...(m.was_queued !== undefined ? { was_queued: m.was_queued } : {}),
  })) }));
  return { backend, ranked, casual, reads, handle, queue, release, account, state, trace };
}

test('S05 control: cancel after completed read removes the entry', async t => {
  const h = harness(t), a = h.account('a');
  await h.release(h.queue(a));
  assert.equal(h.ranked.mm.has(a.user.id), true);
  await h.handle(a, 'ranked_cancel');
  assert.equal(a.sent.at(-1).was_queued, true);
  assert.deepEqual(h.state(a).rankedQueues, []);
});

test('S05 control: Casual occupancy BEFORE Ranked request blocks the read', async t => {
  const h = harness(t), a = h.account('a'), b = h.account('b');
  await h.handle(a, 'casual_queue', 'casual_3min');
  await h.handle(a, 'ranked_queue', 'ranked_3min');
  assert.equal(a.sent.at(-1).code, 'busy');
  assert.equal(h.reads.length, 0);
  await h.handle(b, 'casual_queue', 'casual_3min'); h.casual.tick();
  assert.equal(h.state(a).casualMatches.length, 1);
  await h.handle(a, 'ranked_queue', 'ranked_3min');
  assert.equal(a.sent.at(-1).code, 'busy');
  assert.equal(h.reads.length, 0);
  assert.deepEqual(h.state(a).rankedQueues, []);
});

test('S05 control: concurrent reads cannot duplicate an entry still in Ranked queue', async t => {
  const h = harness(t), a = h.account('a');
  const old = h.queue(a), newer = h.queue(a, 'ranked_5min');
  await h.release(newer); await h.release(old);
  assert.equal(a.sent.at(-1).code, 'already_queued');
  assert.deepEqual(h.state(a).rankedQueues, ['ranked_5min']);
});

test('S05 control: Ranked active BEFORE another request blocks the read', async t => {
  const h = harness(t), a = h.account('a'), b = h.account('b');
  await h.release(h.queue(a)); await h.release(h.queue(b)); h.ranked.tick();
  const first = h.ranked.activeMatchOf(a.user.id);
  assert.ok(first);
  const reads = h.reads.length;
  await h.handle(a, 'ranked_queue', 'ranked_5min');
  assert.equal(h.reads.length, reads);
  assert.equal(a.sent.at(-1).type, 'ranked_state');
  assert.deepEqual(h.state(a).rankedQueues, []);
  assert.equal(h.ranked.activeMatchOf(a.user.id), first);
});

test('S05: cancel during stats read must prevent late enqueue', async t => {
  const h = harness(t), a = h.account('a');
  const old = h.queue(a);
  assert.deepEqual(h.state(a).rankedQueues, []);
  await h.handle(a, 'ranked_cancel');
  assert.equal(a.sent.at(-1).type, 'ranked_cancelled');
  assert.equal(a.sent.at(-1).was_queued, false);
  h.trace(a, 'cancel acknowledged while read pending');
  await h.release(old);
  h.trace(a, 'old read completed after cancel');
  assert.deepEqual(h.state(a).rankedQueues, [], 'cancelled request must not enqueue later');
});

test('S05: cancel a visible queue must also invalidate an older pending read', async t => {
  const h = harness(t), a = h.account('a');
  const old = h.queue(a), newer = h.queue(a, 'ranked_5min');
  await h.release(newer);
  await h.handle(a, 'ranked_cancel');
  assert.equal(a.sent.at(-1).was_queued, true);
  assert.deepEqual(h.state(a).rankedQueues, []);
  h.trace(a, 'visible newer queue cancelled');
  await h.release(old);
  h.trace(a, 'older read completed after cancel');
  assert.deepEqual(h.state(a).rankedQueues, [], 'older read must not resurrect a cancelled search');
});

test('S05: entering Casual queue during stats read must prevent double queue', async t => {
  const h = harness(t), a = h.account('a');
  const old = h.queue(a);
  await h.handle(a, 'casual_queue', 'casual_3min');
  assert.deepEqual(h.state(a).casualQueues, ['casual_3min']);
  assert.equal(h.backend.busyElsewhere(a.user.id, h.ranked), true);
  h.trace(a, 'Casual queued while Ranked read pending');
  await h.release(old);
  h.trace(a, 'late Ranked enqueue alongside Casual queue');
  assert.deepEqual(h.state(a).rankedQueues, [], 'one user must not occupy Casual and Ranked queues');
});

test('S05: Casual match during stats read must prevent simultaneous Ranked match', async t => {
  const h = harness(t), a = h.account('a'), b = h.account('b'), c = h.account('c');
  const old = h.queue(a);
  await h.handle(a, 'casual_queue', 'casual_3min');
  await h.handle(b, 'casual_queue', 'casual_3min'); h.casual.tick();
  const first = h.casual.activeMatchOf(a.user.id);
  assert.ok(first);
  assert.equal(h.backend.busyElsewhere(a.user.id, h.ranked), true);
  h.trace(a, 'Casual playing while Ranked read pending');
  await h.release(old);
  h.trace(a, 'late Ranked enqueue while Casual playing');
  await h.release(h.queue(c)); h.ranked.tick();
  h.trace(a, 'Ranked tick after adding compatible opponent');
  assert.equal(h.casual.activeMatchOf(a.user.id), first);
  assert.deepEqual(h.state(a).rankedMatches, [], 'Casual player must not start a simultaneous Ranked match');
});

for (const oldMode of ['ranked_3min', 'ranked_5min']) {
  test(`S05: two pending requests (${oldMode} / ranked_3min) must not overwrite active match`, async t => {
    const h = harness(t), a = h.account('a'), b = h.account('b'), c = h.account('c');
    const old = h.queue(a, oldMode), newer = h.queue(a);
    await h.release(newer); await h.release(h.queue(b)); h.ranked.tick();
    const first = h.ranked.activeMatchOf(a.user.id);
    assert.ok(first);
    assert.deepEqual(h.state(a).rankedQueues, []);
    h.trace(a, 'newer request matched; older read still pending');
    await h.release(old);
    h.trace(a, 'older read completed during first Ranked match');
    await h.release(h.queue(c, oldMode)); h.ranked.tick();
    h.trace(a, 'second matchmaking tick');
    assert.notEqual(first.status, 'finished', 'first match remains active');
    assert.equal(h.ranked.matches.get(first.id), first, 'first match is retained in matches');
    assert.deepEqual({
      matches: h.state(a).rankedMatches, indexed: h.state(a).rankedByUser,
    }, { matches: [first.id], indexed: first.id }, 'one active Ranked match and its original byUser index must survive');
  });
}

test('S05: close during stats read must prevent orphaned queue and match', async t => {
  const h = harness(t), a = h.account('a'), b = h.account('b');
  const uid = a.user.id, old = h.queue(a);
  a.readyState = 3; h.backend.onClose(a);
  assert.equal(h.backend.online.has(uid), false);
  assert.equal(h.ranked.sockets.has(uid), false);
  assert.deepEqual(h.state(a).rankedQueues, []);
  h.trace(a, 'socket closed and cleaned up while read pending');
  await h.release(old);
  h.trace(a, 'old read completed on closed socket');
  await h.release(h.queue(b)); h.ranked.tick();
  h.trace(a, 'orphaned entry processed by matchmaking');
  const match = h.ranked.activeMatchOf(uid);
  if (match) t.diagnostic(JSON.stringify({ connected: match.players[match.colorOf(uid)].connected }));
  assert.deepEqual(h.state(a).rankedMatches, [], 'closed pending search must not create a disconnected match');
});

test('S05: logout during stats read must not enqueue the former identity', async t => {
  const h = harness(t), a = h.account('a'), old = h.queue(a);
  await h.handle(a, 'acct_logout');
  assert.equal(a.sent.at(-1).type, 'acct_logged_out');
  assert.equal(a.identity, null); assert.equal(a.user, null); assert.equal(a.profile, null);
  h.trace(a, 'logout completed while read pending');
  await h.release(old);
  h.trace(a, 'old read completed after logout');
  assert.deepEqual(h.state(a).rankedQueues, []);
  assert.equal(a.sent.some(m => m.type === 'ranked_queued'), false);
  // Invalidated callbacks are silent: logout is the final acknowledged action.
  // The old ranked_error came from dereferencing a cleared profile, not a contract.
  assert.equal(a.sent.at(-1).type, 'acct_logged_out');
  assert.deepEqual(h.state(a).rankedMatches, []);
});

test('S05: cancelled read cannot replace or cancel a fresh search', async t => {
  const h = harness(t), a = h.account('a');
  const old = h.queue(a);
  await h.handle(a, 'ranked_cancel');
  const fresh = h.queue(a, 'ranked_5min');
  const messages = a.sent.length;
  await h.release(old);
  assert.deepEqual(h.state(a).rankedQueues, []);
  assert.equal(a.sent.length, messages, 'invalidated completion is silent');
  await h.release(fresh);
  assert.deepEqual(h.state(a).rankedQueues, ['ranked_5min']);
});

test('S05: superseded read cannot enqueue if the latest read fails', async t => {
  const h = harness(t), a = h.account('a');
  const old = h.queue(a), fresh = h.queue(a, 'ranked_5min');
  fresh.read.reject(new Error('local stats failure')); await fresh.completion;
  assert.equal(a.sent.at(-1).type, 'ranked_error');
  const messages = a.sent.length;
  await h.release(old);
  assert.deepEqual(h.state(a).rankedQueues, [], 'failed latest intent must not fall back to an older search');
  assert.equal(a.sent.length, messages);
});

test('S05: rejected old read after cancel must not report an error on the fresh search', async t => {
  const h = harness(t), a = h.account('a');
  const old = h.queue(a);
  await h.handle(a, 'ranked_cancel');
  const fresh = h.queue(a, 'ranked_5min');
  await h.release(fresh);
  const messages = a.sent.length;
  old.read.reject(new Error('cancelled local stats failure')); await old.completion;
  assert.deepEqual(h.state(a).rankedQueues, ['ranked_5min']);
  assert.equal(a.sent.length, messages);
});

for (const name of ['a', 'different']) {
  test(`S05: logout and reauthenticate as ${name} must invalidate the former read`, async t => {
    const h = harness(t), a = h.account('a'), old = h.queue(a);
    await h.handle(a, 'acct_logout');
    // Install an authenticated session just as the harness does at its entry point;
    // auth/storage behavior is exercised by the real Ranked/Casual flow suites.
    a.user = { id: 's05-' + name }; a.profile = { nickname: name, avatar_id: 'warrior' };
    h.backend.setIdentity(a, { id: a.user.id, nickname: name, avatar: 'warrior', guest: false });
    h.ranked.onAuthenticated(a);
    const fresh = h.queue(a, 'ranked_5min');
    const messages = a.sent.length;
    await h.release(old);
    assert.equal(a.sent.length, messages);
    assert.equal(h.ranked.mm.has('s05-a'), false);
    assert.equal(h.ranked.mm.has('s05-' + name), false);
    await h.release(fresh);
    assert.equal(h.ranked.mm.has(a.user.id), true);
    assert.equal(a.sent.at(-1).mode, 'ranked_5min');
  });
}

test('S05: replacement socket and late old close preserve the new search', async t => {
  const h = harness(t), oldSocket = h.account('a'), old = h.queue(oldSocket);
  const current = h.account('a'); h.ranked.onAuthenticated(current);
  const fresh = h.queue(current, 'ranked_5min');
  oldSocket.readyState = 3; h.backend.onClose(oldSocket);
  await h.release(old);
  assert.deepEqual(h.state(current).rankedQueues, []);
  await h.release(fresh);
  assert.deepEqual(h.state(current).rankedQueues, ['ranked_5min']);
  assert.equal(h.state(current).rankedSocketRegistered, true);
  assert.equal(current.sent.filter(m => m.type === 'ranked_queued').length, 1);
});

test('S05: closed socket without cleanup cannot enqueue on stats completion', async t => {
  const h = harness(t), a = h.account('a'), old = h.queue(a);
  a.readyState = 3;
  await h.release(old);
  assert.deepEqual(h.state(a).rankedQueues, []);
});

test('S05: old read remains invalid after a newer match finishes', async t => {
  const h = harness(t), a = h.account('a'), b = h.account('b');
  const old = h.queue(a), fresh = h.queue(a, 'ranked_5min');
  await h.release(fresh); await h.release(h.queue(b, 'ranked_5min')); h.ranked.tick();
  const first = h.ranked.activeMatchOf(a.user.id);
  await h.backend.handle(a, { type: 'ranked_resign', match_id: first.id });
  assert.equal(first.status, 'finished');
  assert.equal(h.ranked.activeMatchOf(a.user.id), null);
  const messages = a.sent.length;
  await h.release(old);
  assert.deepEqual(h.state(a).rankedQueues, []);
  assert.equal(a.sent.length, messages);
  await h.release(h.queue(a));
  assert.deepEqual(h.state(a).rankedQueues, ['ranked_3min'], 'a fresh search after the match is permitted');
});

test('S05: startMatch rejects an occupied UID and preserves the existing index', async t => {
  const h = harness(t), a = h.account('a'), b = h.account('b'), c = h.account('c');
  await h.release(h.queue(a)); await h.release(h.queue(b)); h.ranked.tick();
  const first = h.ranked.activeMatchOf(a.user.id);
  const entry = ws => ({ userId: ws.user.id, nickname: ws.profile.nickname, stats: stats().ranked_3min });
  h.ranked.onAuthenticated(c); h.casual.onAuthenticated(a); h.casual.onAuthenticated(c);
  assert.throws(() => h.ranked.startMatch('ranked_3min', entry(a), entry(c)));
  assert.throws(() => h.casual.startMatch('casual_3min', entry(a), entry(c)));
  assert.deepEqual(h.state(a).rankedMatches, [first.id]);
  assert.equal(h.state(a).rankedByUser, first.id);
  assert.deepEqual(h.state(a).casualMatches, []);
  assert.deepEqual(h.state(c).rankedMatches, []);
  assert.deepEqual(h.state(c).casualMatches, []);
});

test('S05: startMatch rejects a UID queued elsewhere without consuming that queue', async t => {
  const h = harness(t), a = h.account('a'), b = h.account('b');
  await h.handle(a, 'casual_queue', 'casual_3min');
  h.ranked.onAuthenticated(a); h.ranked.onAuthenticated(b);
  const entry = ws => ({ userId: ws.user.id, nickname: ws.profile.nickname, stats: stats().ranked_3min });
  assert.throws(() => h.ranked.startMatch('ranked_3min', entry(a), entry(b)));
  assert.deepEqual(h.state(a).casualQueues, ['casual_3min']);
  assert.deepEqual(h.state(a).rankedMatches, []);
});

test('S05: tick drops a closed queued socket while preserving its healthy opponent', async t => {
  const h = harness(t), a = h.account('a'), b = h.account('b'), c = h.account('c');
  await h.release(h.queue(a)); await h.release(h.queue(b));
  a.readyState = 3; // Transport close may be observed before the cleanup callback.
  h.ranked.tick();
  assert.deepEqual(h.state(a).rankedQueues, []);
  assert.deepEqual(h.state(a).rankedMatches, []);
  assert.deepEqual(h.state(b).rankedQueues, ['ranked_3min']);
  await h.release(h.queue(c)); h.ranked.tick();
  assert.equal(h.ranked.activeMatchOf(b.user.id), h.ranked.activeMatchOf(c.user.id));
  assert.ok(h.ranked.activeMatchOf(b.user.id));
});

test('S05: optional backend session revision rejects an old read across same-UID ABA', async t => {
  const h = harness(t), a = h.account('a');
  let revision = 1;
  // Optional integration contract: simulate session transitions without service
  // cleanup, keeping the same socket, UID and user object throughout.
  h.backend.session = () => ({ revision });
  h.backend.current = (_ws, expected) => expected === revision;
  const old = h.queue(a);
  revision++; // A -> B
  revision++; // B -> A (same account again, new session)
  const fresh = h.queue(a, 'ranked_5min');
  const messages = a.sent.length;
  await h.release(old);
  assert.equal(a.sent.length, messages);
  assert.deepEqual(h.state(a).rankedQueues, []);
  await h.release(fresh);
  assert.deepEqual(h.state(a).rankedQueues, ['ranked_5min']);
});

test('S05: optional backend validity blocks enqueue and match before an expiry timer runs', async t => {
  const h = harness(t), a = h.account('a'), b = h.account('b');
  let validA = true;
  h.backend.session = () => ({ revision: 1 });
  h.backend.current = (ws, expected) => expected === 1 && (ws !== a || validA);
  const old = h.queue(a);
  validA = false; // Expiry/revocation observed by authority, cleanup has not run.
  await h.release(old);
  assert.deepEqual(h.state(a).rankedQueues, []);
  assert.equal(a.sent.length, 0);
  validA = true;
  await h.release(h.queue(a)); await h.release(h.queue(b));
  validA = false;
  const entry = ws => ({ userId: ws.user.id, nickname: ws.profile.nickname, stats: stats().ranked_3min });
  // Remove queued entries only to exercise startMatch's own authority check.
  h.ranked.mm.cancel(a.user.id); h.ranked.mm.cancel(b.user.id);
  assert.throws(() => h.ranked.startMatch('ranked_3min', entry(a), entry(b)));
  assert.deepEqual(h.state(a).rankedMatches, []);
  validA = true;
  await h.release(h.queue(a)); await h.release(h.queue(b));
  validA = false; h.ranked.tick();
  assert.deepEqual(h.state(a).rankedMatches, []);
  assert.deepEqual(h.state(a).rankedQueues, []);
  assert.deepEqual(h.state(b).rankedQueues, ['ranked_3min']);
});

test('S05: validity expiring at match creation rejects the pair without crashing or losing the opponent', async t => {
  const h = harness(t), a = h.account('a'), b = h.account('b'), c = h.account('c');
  await h.release(h.queue(a)); await h.release(h.queue(b));
  let checkedA = false;
  h.backend.session = () => ({ revision: 1 });
  h.backend.current = (ws, expected) => {
    if (expected !== 1) return false;
    if (ws !== a) return true;
    // Authority initially admits the queued socket, then observes expiry when
    // the selected pair attempts to start. No cleanup timer fires in this test.
    if (!checkedA) { checkedA = true; return true; }
    return false;
  };
  assert.doesNotThrow(() => h.ranked.tick());
  assert.deepEqual(h.state(a).rankedMatches, []);
  assert.deepEqual(h.state(a).rankedQueues, []);
  assert.deepEqual(h.state(b).rankedQueues, ['ranked_3min']);
  await h.release(h.queue(c)); h.ranked.tick();
  assert.ok(h.ranked.activeMatchOf(b.user.id));
  assert.equal(h.ranked.activeMatchOf(b.user.id), h.ranked.activeMatchOf(c.user.id));
});
