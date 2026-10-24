'use strict';
// R144 · FILA ONLINE de MARCHA REAL e XEQUE (contas). Mesa de 4: completa com outras pessoas da fila; se
// demorar, começa com quem estiver lá e bots nos lugares vazios.
//   · Entrada = GRUPO: sozinho (1) ou com um amigo (2, pelo convite "JOGAR ONLINE"). Na MARCHA o grupo é
//     uma DUPLA (lugares 0+2 ou 1+3); no XEQUE cada um joga por si.
//   · 4 pessoas → começa na hora. 2 ou 3 pessoas → começa depois de FILL_MS esperando (bots completam).
//   · Sozinho: R181 · depois de FRAIHA_QUEUE_AI_WAIT_MS (30 s) a mesa começa com bots nos lugares vazios.
//   · Nunca junta quem já está em partida, em outra fila ou com convite sendo aceito.
const env = process.env;
const num = (v, d) => (v !== undefined && v !== '' && Number.isFinite(Number(v)) ? Number(v) : d);
const FILL_MS = num(env.FRAIHA_PARTY_QUEUE_FILL_MS, 20000);
// R181 · TODAS as filas: sozinho (ou só a sua dupla) por FRAIHA_QUEUE_AI_WAIT_MS (padrão 30 s, o mesmo do Ranked/Casual)
// → a mesa começa com bots nos lugares vazios. Lido a cada verificação: muda no Render sem build novo.
const soloMs = () => num(process.env.FRAIHA_QUEUE_AI_WAIT_MS, 30000);
const TICK_MS = num(env.FRAIHA_PARTY_QUEUE_TICK_MS, 1000);
const GAMES = ['marcha', 'xeque'];

// Lugares na mesa a partir dos grupos (ordem de chegada). Devolve [{member, seat}].
function seatGroups(game, groups) {
  const out = [];
  if (game === 'marcha') {
    const teams = [[0, 2], [1, 3]], used = new Set();
    let t = 0;
    for (const g of groups.filter(g => g.members.length === 2)) {   // duplas primeiro: cada uma num time
      const team = teams[t++];
      g.members.forEach((m, i) => { out.push({ member: m, seat: team[i] }); used.add(team[i]); });
    }
    const free = [0, 1, 2, 3].filter(s => !used.has(s));
    for (const g of groups.filter(g => g.members.length === 1)) out.push({ member: g.members[0], seat: free.shift() });   // solos: 0, 1… (adversários)
    return out;
  }
  let s = 0;
  for (const g of groups) for (const m of g.members) out.push({ member: m, seat: s++ });
  return out;
}

class PartyQueue {
  constructor(party, { now = () => Date.now() } = {}) {
    this.party = party; this.now = now;
    this.queues = { marcha: [], xeque: [] };   // [{id, game, members:[{user_id,nickname,avatar_id,...look}], since}]
    this.timer = setInterval(() => this.tick(), TICK_MS); this.timer.unref && this.timer.unref();
  }
  get backend() { return this.party.backend; }
  groupOf(uid) { for (const g of GAMES) { const e = this.queues[g].find(x => x.members.some(m => m.user_id === uid)); if (e) return e; } return null; }
  has(uid) { return !!this.groupOf(uid); }
  waiting(game) { return this.queues[game].reduce((n, g) => n + g.members.length, 0); }
  // Motivo para NÃO entrar na fila (ou null).
  problem(uid) {
    const b = this.backend;
    if (this.party.roomOf(uid)) return ['busy', 'Você já está numa mesa.'];
    if (b && b.inMatch && b.inMatch(uid)) return ['busy', 'Você já está em uma partida.'];
    if (b && b.games && b.games().some(g => g.mm && g.mm.has(uid))) return ['busy', 'Saia da fila do xadrez primeiro.'];
    if (b && b.invites && b.invites.reserved && b.invites.reserved(uid)) return ['busy', 'Sua partida do convite está começando.'];
    if (this.has(uid)) return ['already_queued', 'Você já está na fila.'];
    return null;
  }
  // members: [{user_id, nickname, avatar_id, ...look}] (1 ou 2). Devolve null ou [code, message].
  join(game, members) {
    if (!GAMES.includes(game)) return ['invalid', 'Modo inválido.'];
    const b = this.backend;
    if (b && b.modeOpen && !b.modeOpen(game)) return ['mode_disabled', require('../admin/controls').CLOSED_MESSAGE];
    for (const m of members) { const p = this.problem(m.user_id); if (p) return p; }
    for (const m of members) if (b && b.invites && b.invites.onQueue) b.invites.onQueue(m.user_id);   // fila cancela convite pendente
    const g = { id: require('crypto').randomUUID(), game, members, since: this.now() };
    this.queues[game].push(g);
    for (const m of members) if (b && b.presenceChanged) b.presenceChanged(m.user_id);
    this.status(game);
    return null;
  }
  cancel(uid) {
    const g = this.groupOf(uid);
    if (!g) return false;
    this.queues[g.game] = this.queues[g.game].filter(x => x !== g);
    // grupo de amigos: os dois saem (o outro é avisado)
    for (const m of g.members) {
      this.party.toUser(m.user_id, { type: 'party_queue_cancelled', game: g.game, by_friend: m.user_id !== uid });
      if (this.backend && this.backend.presenceChanged) this.backend.presenceChanged(m.user_id);
    }
    this.status(g.game);
    return true;
  }
  status(game) {
    const n = this.waiting(game), now = this.now();
    for (const g of this.queues[game]) for (const m of g.members)
      this.party.toUser(m.user_id, { type: 'party_queue_status', game, waiting: n, group: g.members.length, waited_ms: now - g.since, fill_ms: FILL_MS });
  }
  online(uid) { return this.party.sockets(uid).length > 0; }
  tick() {
    const now = this.now();
    for (const game of GAMES) {
      let q = this.queues[game];
      // quem caiu da conexão sai da fila (o grupo inteiro)
      for (const g of [...q]) if (!g.members.every(m => this.online(m.user_id))) { this.cancel(g.members.find(m => !this.online(m.user_id)).user_id); }
      q = this.queues[game];
      if (this.backend && this.backend.modeOpen && !this.backend.modeOpen(game)) continue;
      q.sort((a, b) => a.since - b.since);
      while (true) {
        const pick = this.pick(q, now);
        if (!pick) break;
        this.queues[game] = q = q.filter(g => !pick.includes(g));
        this.startTable(game, pick);
      }
      if (q.length) this.status(game);
    }
  }
  // Grupos para uma mesa: 4 pessoas na hora; 2–3 depois de FILL_MS (contando do mais antigo). Na MARCHA, no
  // máximo 2 duplas por mesa (cada uma num time).
  pick(q, now) {
    const chosen = []; let n = 0, duos = 0;
    for (const g of q) {
      const k = g.members.length;
      if (n + k > 4) continue;
      if (q[0].game === 'marcha' && k === 2 && duos >= 2) continue;
      chosen.push(g); n += k; if (k === 2) duos++;
      if (n === 4) return chosen;
    }
    if (n >= 2 && chosen.length >= 2 && now - chosen[0].since >= FILL_MS) return chosen;   // 2–3 pessoas (de grupos diferentes) + bots
    if (n >= 1 && chosen.length >= 1 && now - chosen[0].since >= soloMs()) return chosen;   // R181 · ninguém veio: bots completam
    return null;
  }
  startTable(game, groups) {
    const seated = seatGroups(game, groups);
    try {
      const room = this.party.start(game, seated.map(x => x.member), { seats: seated.map(x => x.seat), online: true });
      console.log('[party_queue]', game, room.id, seated.map(x => x.seat + ':' + x.member.nickname).join(' '));
    } catch (e) {
      console.error('party queue start', e && e.message);
      for (const g of groups) for (const m of g.members) this.party.toUser(m.user_id, { type: 'party_queue_cancelled', game, error: 'Não foi possível montar a mesa. Tente de novo.' });
    }
  }
  stop() { clearInterval(this.timer); }
}
module.exports = { PartyQueue, seatGroups, FILL_MS };
