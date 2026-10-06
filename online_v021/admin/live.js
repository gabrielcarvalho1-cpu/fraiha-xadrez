'use strict';
// FRAIHA Admin · leitura do estado AO VIVO direto da memória do servidor (instância única).
// Só LÊ os mapas existentes (online, filas, partidas, mesas, voz). Nunca altera nada.
const FAMILY_OF_RANKED = { ranked: 'ranked', casual: 'casual' };
const isGuest = uid => String(uid || '').startsWith('guest:');

function liveSnapshot(backend, now = Date.now()) {
  const games = [backend.ranked, backend.casual].filter(Boolean);
  const party = backend.party;
  const queue = { ranked: [], casual: [] };
  for (const g of games) for (const [mode, q] of g.mm.queues) for (const e of q) queue[FAMILY_OF_RANKED[g.kind]].push({ uid: e.userId, mode, since: e.since, wait_ms: Math.max(0, now - e.since), nickname: e.nickname, guest: isGuest(e.userId) });
  const matches = [];
  for (const g of games) for (const m of g.matches.values()) {
    if (m.status === 'finished') continue;
    matches.push({ id: m.id, family: g.kind, mode: m.mode, status: m.status, started_at: m.startedAt || m.startsAt || m.createdAt || null,
      players: ['w', 'b'].map(c => ({ uid: m.players[c].userId, nickname: m.players[c].nickname, connected: !!m.players[c].connected, guest: isGuest(m.players[c].userId) })) });
  }
  if (party) for (const r of party.rooms.values()) {
    if (r.ended) continue;
    matches.push({ id: r.id, family: r.game === 'xeque' ? 'xeque' : 'marcha', mode: r.game, status: 'playing', started_at: r.started_at || null,
      players: r.seats.map(s => s.kind === 'human' ? { uid: s.uid, nickname: s.nickname, connected: !!s.connected && !s.left, guest: isGuest(s.uid) } : { bot: true, nickname: s.nickname }) });
  }
  const voice = new Set();
  if (backend.voice && backend.voice.present) for (const [key, set] of backend.voice.present) if (set.size) voice.add(key.slice(0, key.indexOf('|')));
  const inMatch = new Set(), inQueue = new Set();
  for (const m of matches) for (const p of m.players) if (p.uid) inMatch.add(p.uid);
  for (const f of Object.keys(queue)) for (const e of queue[f]) inQueue.add(e.uid);
  const online = [...(backend.online ? backend.online.keys() : [])];
  const accounts = online.filter(u => !isGuest(u)).length;
  const lobby = online.filter(u => !inMatch.has(u) && !inQueue.has(u)).length;
  return { now, online, accounts, guests: online.length - accounts, inMatch, inQueue, lobby, queue, matches, voice };
}

function whereIs(backend, uid, snap) {
  const s = snap || liveSnapshot(backend);
  if (!s.online.includes(uid)) return { place: 'offline' };
  const m = s.matches.find(x => x.players.some(p => p.uid === uid));
  if (m) return { place: 'match', family: m.family, mode: m.mode, match_id: m.id, voice: s.voice.has(uid) };
  for (const f of Object.keys(s.queue)) { const e = s.queue[f].find(x => x.uid === uid); if (e) return { place: 'queue', family: f, mode: e.mode, wait_ms: e.wait_ms }; }
  return { place: 'lobby' };
}
module.exports = { liveSnapshot, whereIs, isGuest };
