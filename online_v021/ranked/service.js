'use strict';
// Serviço Ranked: filas, partidas autoritativas, reconexão e gravação do resultado.
const { MODES, CONFIG } = require('./config');
const { Matchmaker } = require('./matchmaker');
const { RankedMatch } = require('./match');

class Ranked {
  constructor({ send, cfg = CONFIG, now = () => Date.now() }) {
    this.send = send; this.cfg = cfg; this.now = now; this.backend = null;
    this.mm = new Matchmaker(cfg.matchmaking); this.matches = new Map(); this.byUser = new Map(); this.sockets = new Map();
    this.timer = setInterval(() => this.tick(), cfg.tickMs); this.timer.unref && this.timer.unref();
  }
  fail(ws, message, code = '') { this.send(ws, { type: 'ranked_error', message, code }); }
  handle(ws, m) {
    const a = String(m.type || ''), uid = ws.user.id, now = this.now();
    this.sockets.set(uid, ws);
    const match = this.matches.get(this.byUser.get(uid));
    if (a === 'ranked_queue') {
      const mode = String(m.mode || '');
      if (!MODES[mode]) return this.fail(ws, 'Modalidade inválida.');
      if (match && match.status !== 'finished') return this.pushState(match, now);
      return this.backend.store.getRankedStats(uid).then(all => {
        // PL/liga sempre lidos do servidor, nunca do cliente.
        const entry = { userId: uid, nickname: ws.profile.nickname, avatar: ws.profile.avatar_id, stats: all[mode], since: this.now() };
        if (!this.mm.enqueue(mode, entry)) return this.fail(ws, 'Você já está na fila.', 'already_queued');
        this.send(ws, { type: 'ranked_queued', mode, mode_name: MODES[mode].name, league: entry.stats.league, pl: entry.stats.pl });
      }).catch(() => this.fail(ws, 'Não foi possível entrar na fila agora.'));
    }
    if (a === 'ranked_cancel') { const e = this.mm.cancel(uid); return this.send(ws, { type: 'ranked_cancelled', was_queued: !!e }); }
    if (a === 'ranked_sync') { if (match) return this.pushState(match, now); return this.send(ws, { type: 'ranked_idle' }); }
    if (!match || match.id !== String(m.match_id || match.id)) return this.fail(ws, 'Nenhuma partida Ranked ativa.', 'no_match');
    const color = match.colorOf(uid);
    if (a === 'ranked_move') {
      const r = match.move(color, { from: m.from, to: m.to, promotion: String(m.promotion || 'Q') }, now);
      if (r.error) { this.fail(ws, r.error, 'move_rejected'); return this.pushState(match, now, color); }
      return this.after(match, now);
    }
    if (a === 'ranked_resign') { match.resign(color, now); return this.after(match, now); }
    return this.fail(ws, 'Ação Ranked desconhecida.');
  }
  pushState(match, now, only = null) {
    for (const c of only ? [only] : ['w', 'b']) { const ws = this.sockets.get(match.players[c].userId); if (ws && match.players[c].connected) this.send(ws, match.state(c, now)); }
  }
  after(match, now) {
    this.pushState(match, now);
    if (match.status === 'finished' && !match.persisting) this.persist(match);
  }
  async persist(match) {
    match.persisting = true;
    let saved = false;
    try { await this.backend.store.recordRankedMatch(match.record()); saved = true; }
    catch (e) { console.error('ranked persist failed', match.id, e && e.message); }
    match.saved = saved;
    for (const c of ['w', 'b']) {
      const uid = match.players[c].userId, ws = this.sockets.get(uid);
      if (ws && match.players[c].connected) this.send(ws, match.resultFor(c, saved));
      if (this.byUser.get(uid) === match.id) this.byUser.delete(uid);
    }
    setTimeout(() => this.matches.delete(match.id), 60000).unref();
  }
  tick() {
    const now = this.now();
    for (const { mode, a, b } of this.mm.tick(now)) {
      // Servidor sorteia as cores. FRAIHA_TEST_FIXED_COLORS=1 (só testes): quem entrou primeiro joga de Brancas.
      const flip = process.env.FRAIHA_TEST_FIXED_COLORS === '1' ? a.since <= b.since : Math.random() < 0.5;
      const [w, bl] = flip ? [a, b] : [b, a];
      const seat = e => ({ userId: e.userId, nickname: e.nickname, avatar: e.avatar, stats: e.stats, connected: true, leftAt: 0 });
      const match = new RankedMatch({ mode, white: seat(w), black: seat(bl), now, cfg: this.cfg });
      this.matches.set(match.id, match); this.byUser.set(w.userId, match.id); this.byUser.set(bl.userId, match.id);
      for (const c of ['w', 'b']) {
        const me = match.players[c], opp = match.publicPlayer(c === 'w' ? 'b' : 'w');
        const ws = this.sockets.get(me.userId);
        if (ws) this.send(ws, { type: 'ranked_found', match_id: match.id, mode, mode_name: MODES[mode].name, you: c, opponent: opp });
        if (!ws || ws.readyState !== 1) { me.connected = false; me.leftAt = now; }
      }
      this.pushState(match, now);
    }
    for (const match of this.matches.values()) if (match.status !== 'finished' && match.tick(now)) this.after(match, now);
  }
  onAuthenticated(ws) {
    const uid = ws.user.id; this.sockets.set(uid, ws);
    const match = this.matches.get(this.byUser.get(uid));
    if (!match) return;
    const c = match.colorOf(uid);
    match.players[c].connected = true; match.players[c].leftAt = 0;
    const now = this.now();
    this.send(ws, { type: 'ranked_found', match_id: match.id, mode: match.mode, mode_name: MODES[match.mode].name, you: c, opponent: match.publicPlayer(c === 'w' ? 'b' : 'w'), resumed: true });
    this.pushState(match, now);
    if (match.status === 'finished' && match.saved !== undefined) this.send(ws, match.resultFor(c, match.saved));
  }
  onClose(ws) {
    if (!ws.user) return;
    const uid = ws.user.id;
    if (this.sockets.get(uid) !== ws) return;               // outra aba/conexão mais nova
    this.sockets.delete(uid); this.mm.cancel(uid);
    const match = this.matches.get(this.byUser.get(uid));
    if (match && match.status !== 'finished') {
      const c = match.colorOf(uid);
      match.players[c].connected = false; match.players[c].leftAt = this.now();   // relógio continua correndo
      this.pushState(match, this.now());
    }
  }
  stop() { clearInterval(this.timer); }
}
module.exports = { Ranked };
