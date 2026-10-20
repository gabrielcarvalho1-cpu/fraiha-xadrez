'use strict';
// R112 · COROAS — a moeda do FRAIHA. Por enquanto só se GANHA jogando (sem venda). O servidor é a autoridade:
// o cliente só pede o estado (crowns_get) e mostra os avisos (crowns_reward).
//   • partida online terminada (Casual / Ranqueada com 10+ lances; XEQUE / Marcha sem sair no meio):
//       vitória +10, derrota ou empate +3 — limite de 150 Coroas por dia vindas de partidas;
//       Club FRAIHA: +25% nas Coroas de partida;
//   • entrada do dia +10; sequência de dias seguidos: 3º dia +20 extra, 7º dia +50 extra (e assim por diante);
//   • 3 missões do dia (as mesmas para todo mundo, trocam à meia-noite de Brasília).
// Cada ganho tem (motivo, referência) únicos no banco (0016): a mesma partida ou missão nunca paga duas vezes.
// Sem a 0016 o jogo segue normal e as Coroas aparecem como indisponíveis (fail-soft, com log).

const WIN = 10, PLAY = 3, MATCH_CAP = 150, CLUB_BONUS = 0.25;
const DAILY = 10, STREAK_BONUS = { 3: 20, 0: 50 };   // chave = sequência % 7
const MIN_PLY = 10;
const POOL = [
  { id: 'play3', title: 'Jogue 3 partidas online', key: 'games', target: 3, reward: 20, group: 'play' },
  { id: 'play5', title: 'Jogue 5 partidas online', key: 'games', target: 5, reward: 35, group: 'play' },
  { id: 'win1', title: 'Vença 1 partida online', key: 'wins', target: 1, reward: 15, group: 'win' },
  { id: 'win3', title: 'Vença 3 partidas online', key: 'wins', target: 3, reward: 40, group: 'win' },
  { id: 'xeque1', title: 'Jogue 1 partida de XEQUE', key: 'xeque', target: 1, reward: 20, group: 'xeque' },
  { id: 'marcha1', title: 'Jogue 1 partida de MARCHA', key: 'marcha', target: 1, reward: 20, group: 'marcha' },
  { id: 'ranked2', title: 'Jogue 2 partidas Ranqueadas', key: 'ranked', target: 2, reward: 30, group: 'ranked' },
];
const REASONS = { game: 'Partida', daily: 'Entrada do dia', streak: 'Sequência de dias', mission: 'Missão do dia', buy: 'Compra na Loja', tournament: 'Prêmio de torneio', admin: 'Presente do FRAIHA', pass: 'Passe da Temporada' };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const missing = e => /42P01|42703|42883|PGRST200|PGRST202|PGRST204|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));

// dia de Brasília (UTC−3, sem horário de verão)
const dayOf = ms => new Date(ms - 3 * 3600e3).toISOString().slice(0, 10);
const nextDayMs = ms => { const d = Date.parse(dayOf(ms) + 'T03:00:00Z'); return d + 86400e3; };

// 3 missões do dia, iguais para todos, de grupos diferentes (sorteio fixo pela data)
function missionsFor(day) {
  let h = 2166136261;
  for (const ch of day) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619) >>> 0; }
  const order = POOL.map((m, i) => ({ m, k: (Math.imul(h ^ (i * 2654435761), 2246822519) >>> 0) })).sort((a, b) => a.k - b.k).map(x => x.m);
  const out = [], used = new Set();
  for (const m of order) { if (used.has(m.group)) continue; used.add(m.group); out.push(m); if (out.length === 3) break; }
  return out;
}

class Crowns {
  constructor({ backend, send, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.backend = backend; this.send = send; this.now = now; this.log = log;
    this.offUntil = 0;   // sem a 0016: não insiste por 10 min
  }
  get store() { return this.backend.store; }
  ok() { return !!(this.store && this.store.crownAward) && this.offUntil <= this.now(); }
  off(e, where) {
    if (missing(e)) { this.offUntil = this.now() + 600e3; return; }
    console.error('[coroas] ' + where, e && e.message);
  }

  rules() {
    return { win: WIN, play: PLAY, match_cap: MATCH_CAP, club_bonus_pct: Math.round(CLUB_BONUS * 100), daily: DAILY, streak3: STREAK_BONUS[3], streak7: STREAK_BONUS[0], min_moves: MIN_PLY / 2 };
  }

  async handle(ws, m) {
    if (String(m.type) !== 'crowns_get') return;
    const uid = ws.user && ws.user.id;
    if (!uid || !ws.profile) return this.send(ws, { type: 'crowns_state', available: false, message: 'Entre na sua conta para ganhar Coroas.' });
    return this.sendState(ws, uid);
  }

  async snapshot(uid) {
    const day = dayOf(this.now());
    const [w, daily, recent] = await Promise.all([this.store.crownWallet(uid), this.store.crownDaily(uid, day), this.store.crownLedger(uid, 20)]);
    const c = daily || {};
    return {
      type: 'crowns_state', available: true, day,
      balance: w ? w.balance : 0, earned_total: w ? w.earned_total : 0,
      streak: w && w.last_daily && (w.last_daily === day || w.last_daily === dayOf(this.now() - 86400e3)) ? w.streak : 0,
      daily_claimed: !!(w && w.last_daily === day),
      match_today: c.match_crowns || 0, match_cap: MATCH_CAP,
      missions: missionsFor(day).map(x => ({ id: x.id, title: x.title, target: x.target, reward: x.reward, progress: Math.min(x.target, c[x.key] || 0), done: (c[x.key] || 0) >= x.target })),
      resets_in_s: Math.max(0, Math.round((nextDayMs(this.now()) - this.now()) / 1000)),
      recent: (recent || []).filter(r => r.delta !== 0).map(r => ({ delta: r.delta, reason: r.reason, label: REASONS[r.reason] || r.reason, at: r.created_at })),
      rules: this.rules(),
    };
  }

  async sendState(ws, uid) {
    if (!this.ok()) return this.send(ws, { type: 'crowns_state', available: false, rules: this.rules() });
    try { this.send(ws, await this.snapshot(uid)); }
    catch (e) { this.off(e, 'estado'); this.send(ws, { type: 'crowns_state', available: false, rules: this.rules() }); }
  }

  // Entrada do dia: chamada depois do login. Paga +10 (e o bônus da sequência) uma vez por dia de Brasília.
  async onLogin(uid) {
    if (!this.ok() || !UUID.test(String(uid || ''))) return null;
    try {
      const day = dayOf(this.now());
      const streak = await this.store.crownCheckin(uid, day);
      if (!streak) return null;
      const lines = [];
      let gained = 0;
      if (await this.store.crownAward(uid, DAILY, 'daily', day) !== null) { gained += DAILY; lines.push(`Entrada do dia +${DAILY}`); }
      const bonus = STREAK_BONUS[streak % 7];
      if (bonus && await this.store.crownAward(uid, bonus, 'streak', day) !== null) { gained += bonus; lines.push(`${streak} dias seguidos +${bonus}`); }
      if (gained) await this.notify(uid, gained, lines, streak);
      if (this.backend.seasonPass) this.backend.seasonPass.add(uid, 'daily');   // R120 · XP do passe
      return { streak, gained };
    } catch (e) { this.off(e, 'entrada'); return null; }
  }

  // Partida online terminada. `kind`: casual | ranked | xeque | marcha; `result`: win | loss | draw.
  async onGame(uid, { kind, ref, result }) {
    if (!this.ok() || !UUID.test(String(uid || '')) || !ref) return null;
    try {
      const day = dayOf(this.now());
      let base = result === 'win' ? WIN : PLAY;
      const ent = this.store.getEntitlements ? await this.store.getEntitlements(uid).catch(() => null) : null;
      const club = !!(ent && ent.club_active);
      if (club) base = Math.round(base * (1 + CLUB_BONUS));
      const before = await this.store.crownDaily(uid, day) || {};
      const pay = Math.max(0, Math.min(base, MATCH_CAP - (before.match_crowns || 0)));
      // o lançamento da partida é a trava: se já foi contada (reconexão / repetição), não conta de novo
      if (await this.store.crownAward(uid, pay, 'game', kind + ':' + ref) === null) return null;
      const inc = { games: 1, match_crowns: pay };
      if (result === 'win') inc.wins = 1;
      if (kind === 'ranked' || kind === 'xeque' || kind === 'marcha') inc[kind] = 1;
      const counters = await this.store.crownBump(uid, day, inc);
      let gained = pay;
      const label = result === 'win' ? 'Vitória' : result === 'draw' ? 'Empate' : 'Partida jogada';
      const lines = [pay > 0 ? `${label} +${pay}${club ? ' (Club +25%)' : ''}` : `${label} · limite de ${MATCH_CAP} Coroas por partidas hoje`];
      // missões que completaram agora
      let missions = 0;
      for (const x of missionsFor(day)) {
        if ((before[x.key] || 0) >= x.target || (counters[x.key] || 0) < x.target) continue;
        if (await this.store.crownAward(uid, x.reward, 'mission', day + ':' + x.id) !== null) { gained += x.reward; missions++; lines.push(`Missão: ${x.title} +${x.reward}`); }
      }
      await this.notify(uid, gained, lines);
      const SP = this.backend.seasonPass;   // R120 · XP do passe (partida + missões)
      if (SP) { await SP.add(uid, result === 'win' ? 'win' : 'play'); if (missions) await SP.add(uid, 'mission', missions); }
      return { gained, lines };
    } catch (e) { this.off(e, 'partida'); return null; }
  }

  async notify(uid, gained, lines, streak) {
    if (!(this.backend.socketsOf ? this.backend.socketsOf(uid) : []).length) return;
    let state = null;
    try { state = await this.snapshot(uid); } catch { /* o aviso vai sem o estado */ }
    // R171 · as conexões são lidas DEPOIS da espera: quem saiu da conta (ou trocou de conta no mesmo aparelho)
    // nesse meio-tempo não recebe o saldo/sequência desta conta.
    const socks = (this.backend.socketsOf ? this.backend.socketsOf(uid) : []).filter(ws => !ws.user || ws.user.id === uid);
    for (const ws of socks) {
      this.send(ws, { type: 'crowns_reward', gained, lines, streak: streak || undefined, balance: state ? state.balance : undefined });
      if (state) this.send(ws, state);
    }
  }
}

module.exports = { Crowns, missionsFor, dayOf, WIN, PLAY, MATCH_CAP, DAILY, STREAK_BONUS, MIN_PLY, POOL };
