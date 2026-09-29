'use strict';
// Serviço de partidas online: filas, partidas autoritativas, reconexão e resultado.
// A mesma classe atende o Ranked (kind='ranked': PL, conta obrigatória, grava no banco)
// e o Casual (kind='casual': sem PL, aceita convidado, nada é gravado).
const { MODES, CASUAL_MODES, ALL_MODES, CONFIG } = require('./config');
const { Matchmaker } = require('./matchmaker');
const { RankedMatch } = require('./match');

class Ranked {
  constructor({ send, cfg = CONFIG, now = () => Date.now(), kind = 'ranked' }) {
    this.send = send; this.cfg = cfg; this.now = now; this.backend = null;
    this.kind = kind; this.p = kind + '_'; this.rated = kind === 'ranked';
    this.modes = this.rated ? MODES : CASUAL_MODES; this.label = this.rated ? 'Ranked' : 'Casual';
    this.mm = new Matchmaker(cfg.matchmaking, this.modes, { open: !this.rated });
    this.matches = new Map(); this.byUser = new Map(); this.sockets = new Map();
    this.timer = setInterval(() => this.tick(), cfg.tickMs); this.timer.unref && this.timer.unref();
  }
  fail(ws, message, code = '') { this.send(ws, { type: this.p + 'error', message, code }); }
  uidOf(ws) { return ws.identity ? ws.identity.id : ws.user ? ws.user.id : null; }
  // Partida ainda não encerrada deste usuário (para impedir duas partidas ao mesmo tempo).
  activeMatchOf(uid) { const m = this.matches.get(this.byUser.get(uid)); return m && m.status !== 'finished' ? m : null; }
  matchOf(uid) { return this.matches.get(this.byUser.get(uid)) || null; }
  busyElsewhere(uid) { return this.backend && this.backend.busyElsewhere ? this.backend.busyElsewhere(uid, this) : false; }
  presence(uid) { if (this.backend && this.backend.presenceChanged) this.backend.presenceChanged(uid); }
  handle(ws, m) {
    const a = String(m.type || ''), uid = this.uidOf(ws), now = this.now();
    this.sockets.set(uid, ws);
    const match = this.matches.get(this.byUser.get(uid));
    if (a === this.p + 'queue') {
      const mode = String(m.mode || '');
      if (!this.modes[mode]) return this.fail(ws, 'Modalidade inválida.');
      if (match && match.status !== 'finished') return this.pushState(match, now);
      if (this.busyElsewhere(uid)) return this.fail(ws, 'Você já está em outra partida ou fila.', 'busy');
      const enqueue = stats => {
        const id = ws.identity || { nickname: ws.profile.nickname, avatar: ws.profile.avatar_id };
        const entry = { userId: uid, nickname: id.nickname, avatar: id.avatar, stats, since: this.now() };
        if (!this.mm.enqueue(mode, entry)) return this.fail(ws, 'Você já está na fila.', 'already_queued');
        const out = { type: this.p + 'queued', mode, mode_name: this.modes[mode].name };
        if (stats) { out.league = stats.league; out.pl = stats.pl; }
        this.send(ws, out);
      };
      if (!this.rated) return enqueue(null);
      // PL/liga sempre lidos do servidor, nunca do cliente.
      return this.backend.store.getRankedStats(uid).then(all => enqueue(all[mode]))
        .catch(() => this.fail(ws, 'Não foi possível entrar na fila agora.'));
    }
    if (a === this.p + 'cancel') { const e = this.mm.cancel(uid); return this.send(ws, { type: this.p + 'cancelled', was_queued: !!e }); }
    if (a === this.p + 'sync') { if (match) return this.pushState(match, now); return this.send(ws, { type: this.p + 'idle' }); }
    if (!match || match.id !== String(m.match_id || match.id)) return this.fail(ws, `Nenhuma partida ${this.label} ativa.`, 'no_match');
    const color = match.colorOf(uid);
    if (a === this.p + 'move') {
      const r = match.move(color, { from: m.from, to: m.to, promotion: String(m.promotion || 'Q') }, now);
      if (r.error) { this.fail(ws, r.error, 'move_rejected'); return this.pushState(match, now, color); }
      return this.after(match, now);
    }
    if (a === this.p + 'resign') { match.resign(color, now); return this.after(match, now); }
    return this.fail(ws, `Ação ${this.label} desconhecida.`);
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
    if (this.rated) {
      try { await this.backend.store.recordRankedMatch(match.record()); saved = true; }
      catch (e) { console.error('ranked persist failed', match.id, e && e.message); }
    }
    match.saved = saved;
    for (const c of ['w', 'b']) {
      const uid = match.players[c].userId, ws = this.sockets.get(uid);
      if (ws && match.players[c].connected) this.send(ws, match.resultFor(c, saved));
      if (this.byUser.get(uid) === match.id) this.byUser.delete(uid);
      this.presence(uid);
    }
    setTimeout(() => this.matches.delete(match.id), 60000).unref();
  }
  // Cria a partida entre duas entradas {userId,nickname,avatar,stats}. Usado pela fila e pelos convites.
  startMatch(mode, a, b, now = this.now()) {
    // Servidor sorteia as cores. FRAIHA_TEST_FIXED_COLORS=1 (só testes): quem entrou primeiro joga de Brancas.
    const flip = process.env.FRAIHA_TEST_FIXED_COLORS === '1' ? (a.since || 0) <= (b.since || 0) : Math.random() < 0.5;
    const [w, bl] = flip ? [a, b] : [b, a];
    const seat = e => ({ userId: e.userId, nickname: e.nickname, avatar: e.avatar, stats: e.stats, connected: true, leftAt: 0 });
    const match = new RankedMatch({ mode, white: seat(w), black: seat(bl), now, cfg: this.cfg, rated: this.rated, prefix: this.kind });
    this.matches.set(match.id, match); this.byUser.set(w.userId, match.id); this.byUser.set(bl.userId, match.id);
    for (const c of ['w', 'b']) {
      const me = match.players[c], opp = match.publicPlayer(c === 'w' ? 'b' : 'w');
      const ws = this.sockets.get(me.userId);
      if (ws) this.send(ws, { type: this.p + 'found', match_id: match.id, mode, mode_name: ALL_MODES[mode].name, you: c, opponent: opp });
      if (!ws || ws.readyState !== 1) { me.connected = false; me.leftAt = now; }
      this.presence(me.userId);
    }
    this.pushState(match, now);
    return match;
  }
  tick() {
    const now = this.now();
    for (const { mode, a, b } of this.mm.tick(now)) this.startMatch(mode, a, b, now);
    for (const match of this.matches.values()) if (match.status !== 'finished' && match.tick(now)) this.after(match, now);
  }
  onAuthenticated(ws) {
    const uid = this.uidOf(ws); if (!uid) return;
    this.sockets.set(uid, ws);
    const match = this.matches.get(this.byUser.get(uid));
    if (!match) return;
    const c = match.colorOf(uid);
    match.players[c].connected = true; match.players[c].leftAt = 0;
    const now = this.now();
    this.send(ws, { type: this.p + 'found', match_id: match.id, mode: match.mode, mode_name: ALL_MODES[match.mode].name, you: c, opponent: match.publicPlayer(c === 'w' ? 'b' : 'w'), resumed: true });
    this.pushState(match, now);
    if (this.backend && this.backend.chat) this.send(ws, this.backend.chat.history(match));
    if (match.status === 'finished' && match.saved !== undefined) this.send(ws, match.resultFor(c, match.saved));
  }
  onClose(ws) {
    const uid = this.uidOf(ws); if (!uid) return;
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
module.exports = { Ranked, MatchService: Ranked };
