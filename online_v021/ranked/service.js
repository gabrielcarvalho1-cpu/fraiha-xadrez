'use strict';
const { look: publicLook } = require('../accounts/cosmetics');
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
    this.pendingQueues = new Map(); // uid -> revisão vigente e leituras ainda em andamento
    this.timer = setInterval(() => this.tick(), cfg.tickMs); this.timer.unref && this.timer.unref();
  }
  fail(ws, message, code = '') { this.send(ws, { type: this.p + 'error', message, code }); }
  uidOf(ws) { return ws.identity ? ws.identity.id : ws.user ? ws.user.id : null; }
  // Partida ainda não encerrada deste usuário (para impedir duas partidas ao mesmo tempo).
  activeMatchOf(uid) { const m = this.matches.get(this.byUser.get(uid)); return m && m.status !== 'finished' ? m : null; }
  matchOf(uid) { return this.matches.get(this.byUser.get(uid)) || null; }
  busyElsewhere(uid) { return this.backend && this.backend.busyElsewhere ? this.backend.busyElsewhere(uid, this) : false; }
  presence(uid) { if (this.backend && this.backend.presenceChanged) this.backend.presenceChanged(uid); }
  invalidateQueue(uid) { this.pendingQueues.delete(uid); }
  sessionRevision(ws) {
    if (this.backend && typeof this.backend.session === 'function' && typeof this.backend.current === 'function')
      return this.backend.session(ws).revision;
  }
  sessionLive(ws, uid, revision) {
    return !!uid && !!ws && ws.readyState === 1 && this.uidOf(ws) === uid && this.sockets.get(uid) === ws
      && (!this.rated || !!(ws.user && ws.user.id === uid && ws.profile) ||
        !!(this.backend && this.backend.session && this.backend.session(ws).authPending && this.backend.session(ws).authPrevious?.user.id === uid))
      && (!(this.backend && typeof this.backend.session === 'function' && typeof this.backend.current === 'function')
        || this.backend.current(ws, revision === undefined ? this.sessionRevision(ws) : revision));
  }
  sessionReady(ws, uid, revision) {
    return this.sessionLive(ws, uid, revision) &&
      (!(this.backend && this.backend.ready) || this.backend.ready(ws, revision === undefined ? this.sessionRevision(ws) : revision));
  }
  queueEligible(uid) {
    return this.sessionLive(this.sockets.get(uid), uid) && !this.activeMatchOf(uid) && !this.busyElsewhere(uid);
  }
  canStartMatch(a, b) {
    if (a.userId === b.userId) return false;
    return [a, b].every(e => {
      const uid = e.userId;
      if (!this.sessionReady(this.sockets.get(uid), uid) || this.activeMatchOf(uid) || this.mm.has(uid)) return false;
      // Convites já reservam os dois usuários antes de chamar startMatch. A reserva
      // não é outra partida; filas, partidas e mesas continuam sendo exclusivas.
      if (this.backend && this.backend.inMatch && this.backend.inMatch(uid)) return false;
      return !(this.backend && this.backend.games && this.backend.games().some(g => g !== this && g.mm.has(uid)));
    });
  }
  handle(ws, m) {
    const a = String(m.type || ''), uid = this.uidOf(ws), now = this.now();
    if (this.sockets.get(uid) !== ws) this.invalidateQueue(uid);
    this.sockets.set(uid, ws);
    const match = this.matches.get(this.byUser.get(uid));
    if (a === this.p + 'queue') {
      const mode = String(m.mode || '');
      if (!this.modes[mode]) return this.fail(ws, 'Modalidade inválida.');
      if (this.backend && this.backend.modeOpen && !this.backend.modeOpen(this.kind, mode)) return this.fail(ws, require('../admin/controls').CLOSED_MESSAGE, 'mode_disabled');   // Admin: ritmo/fila desativado
      if (match && match.status !== 'finished') return this.pushState(match, now);
      if (this.busyElsewhere(uid)) return this.fail(ws, 'Você já está em outra partida ou fila.', 'busy');
      let revision, operation;
      const live = () => this.sessionReady(ws, uid, revision && revision.sessionRevision) && (!this.rated ||
        (this.pendingQueues.get(uid) === revision && revision.user === ws.user));
      const enqueue = stats => {
        if (!live()) return;
        // A leitura mais recente decide a busca. Uma conclusão antiga não pode
        // restaurar a modalidade anterior, mesmo se a nova busca já terminou.
        if (this.rated && revision.latest !== operation) {
          if (this.mm.has(uid)) return this.fail(ws, 'Você já está na fila.', 'already_queued');
          return;
        }
        const id = ws.identity || { nickname: ws.profile.nickname, avatar: ws.profile.avatar_id };
        const entry = { userId: uid, nickname: id.nickname, avatar: id.avatar, ...publicLook(id), stats, since: this.now() };
        // Última revalidação e mutação são síncronas, sem await entre elas.
        const active = this.activeMatchOf(uid);
        if (active) return this.pushState(active, this.now());
        if (this.busyElsewhere(uid)) return this.fail(ws, 'Você já está em outra partida ou fila.', 'busy');
        if (this.backend && this.backend.modeOpen && !this.backend.modeOpen(this.kind, mode)) return this.fail(ws, require('../admin/controls').CLOSED_MESSAGE, 'mode_disabled');   // Admin: modo/ritmo desativado durante a leitura do PL
        if (!this.mm.enqueue(mode, entry)) return this.fail(ws, 'Você já está na fila.', 'already_queued');
        const out = { type: this.p + 'queued', mode, mode_name: this.modes[mode].name };
        if (stats) { out.league = stats.league; out.pl = stats.pl; }
        this.send(ws, out);
      };
      if (!this.rated) return enqueue(null);
      revision = this.pendingQueues.get(uid);
      const sessionRevision = this.sessionRevision(ws);
      if (!revision || revision.user !== ws.user || revision.sessionRevision !== sessionRevision) {
        revision = { ws, user: ws.user, sessionRevision, pending: 0, latest: null };
        this.pendingQueues.set(uid, revision);
      }
      operation = {}; revision.latest = operation; revision.pending++;
      // PL/liga sempre lidos do servidor, nunca do cliente.
      return this.backend.store.getRankedStats(uid).then(async all => {
        if (this.backend.ensureSession && this.backend.current(ws, revision.sessionRevision)) {
          if (!(await this.backend.ensureSession(ws))) return;
        }
        return enqueue(all[mode]);
      })
        .catch(() => { if (live() && revision.latest === operation) this.fail(ws, 'Não foi possível entrar na fila agora.'); })
        .finally(() => {
          if (--revision.pending === 0 && this.pendingQueues.get(uid) === revision) this.pendingQueues.delete(uid);
        });
    }
    if (a === this.p + 'cancel') { this.invalidateQueue(uid); const e = this.mm.cancel(uid); return this.send(ws, { type: this.p + 'cancelled', was_queued: !!e }); }
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
  // FRAIHA Admin: modo desativado → quem estava esperando sai da fila com aviso (o cliente já trata *_error na busca).
  purgeQueue(message, onlyMode = null) {
    let n = 0;
    for (const [mode, q] of this.mm.queues) for (const e of [...q]) {
      if (onlyMode && mode !== onlyMode) continue;
      this.mm.cancel(e.userId); this.invalidateQueue(e.userId); n++;
      const ws = this.sockets.get(e.userId); if (ws) this.fail(ws, message, 'mode_disabled');
    }
    return n;
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
    { const am = this.backend && this.backend.adminMetrics; if (am) am.onMatch('finished', this.kind, match.mode, match.result && match.result.reason); }
    let saved = false;
    if (this.rated) {
      try { await this.backend.store.recordRankedMatch(match.record()); saved = true; }
      catch (e) { console.error('ranked persist failed', match.id, e && e.message); }
    }
    match.saved = saved;
    if (!this.rated && match.result) this.recordCasual(match);
    for (const c of ['w', 'b']) {
      const uid = match.players[c].userId, ws = this.sockets.get(uid);
      if (ws && match.players[c].connected) this.send(ws, match.resultFor(c, saved));
      if (this.byUser.get(uid) === match.id) this.byUser.delete(uid);
      this.presence(uid);
    }
    setTimeout(() => this.matches.delete(match.id), 60000).unref();
  }
  // R37 · placar do Casual por conta (cartão de perfil). Convidados não têm placar. Falha não atrapalha a partida.
  recordCasual(match) {
    const st = this.backend && this.backend.store;
    if (!st || !st.recordModeResult) return;
    const { UUID_RE } = require('../accounts/store');
    const w = match.result.winner;
    for (const c of ['w', 'b']) {
      const uid = match.players[c].userId;
      if (!UUID_RE.test(String(uid || ''))) continue;
      const res = w === 'draw' ? 'draw' : w === c ? 'win' : 'loss';
      st.recordModeResult(uid, 'casual', res).catch(e => console.error('mode stats (casual) failed', e && e.message));
    }
  }
  // Cria a partida entre duas entradas {userId,nickname,avatar,stats}. Usado pela fila e pelos convites.
  startMatch(mode, a, b, now = this.now()) {
    if (!this.canStartMatch(a, b)) {
      const error = new Error('Jogador indisponível para iniciar partida.'); error.code = 'player_unavailable'; throw error;
    }
    // Servidor sorteia as cores. FRAIHA_TEST_FIXED_COLORS=1 (só testes): quem entrou primeiro joga de Brancas.
    const flip = process.env.FRAIHA_TEST_FIXED_COLORS === '1' ? (a.since || 0) <= (b.since || 0) : Math.random() < 0.5;
    const [w, bl] = flip ? [a, b] : [b, a];
    const seat = e => ({ userId: e.userId, nickname: e.nickname, avatar: e.avatar, ...publicLook(e), stats: e.stats, connected: true, leftAt: 0 });
    const match = new RankedMatch({ mode, white: seat(w), black: seat(bl), now, cfg: this.cfg, rated: this.rated, prefix: this.kind });
    this.matches.set(match.id, match); this.byUser.set(w.userId, match.id); this.byUser.set(bl.userId, match.id);
    { const am = this.backend && this.backend.adminMetrics; if (am) am.onMatch('started', this.kind, mode); }
    this.invalidateQueue(w.userId); this.invalidateQueue(bl.userId);
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
    // Remover entradas inválidas antes de parear preserva o oponente disponível.
    for (const q of this.mm.queues.values()) for (const e of [...q]) if (!this.queueEligible(e.userId)) {
      this.mm.cancel(e.userId); this.invalidateQueue(e.userId);
    }
    const eligible = entry => {
      const ws = this.sockets.get(entry.userId);
      if (!this.sessionReady(ws, entry.userId)) {
        if (ws && this.backend && this.backend.ensureSession) void this.backend.ensureSession(ws);
        return false;
      }
      return true;
    };
    const open = !(this.backend && this.backend.modeOpen) || this.backend.modeOpen(this.kind);   // Admin: modo desativado = sem novos pareamentos
    for (const { mode, a, b } of open ? this.mm.tick(now, eligible) : []) {
      if (this.backend && this.backend.modeOpen && !this.backend.modeOpen(this.kind, mode)) { for (const e of [a, b]) if (this.queueEligible(e.userId)) this.mm.enqueue(mode, e); continue; }   // ritmo fechado: sem pareamento
      try { this.startMatch(mode, a, b, now); const am = this.backend && this.backend.adminMetrics; if (am) am.onPaired(this.kind, mode, [now - a.since, now - b.since]); }
      catch (error) {
        if (error.code !== 'player_unavailable') throw error;
        for (const e of [a, b]) if (this.queueEligible(e.userId)) this.mm.enqueue(mode, e);
      }
    }
    for (const q of this.mm.queues.values()) for (const e of [...q]) if (!this.queueEligible(e.userId)) {
      this.mm.cancel(e.userId); this.invalidateQueue(e.userId);
    }
    for (const match of this.matches.values()) if (match.status !== 'finished' && match.tick(now)) this.after(match, now);
  }
  onAuthenticated(ws) {
    const uid = this.uidOf(ws); if (!uid) return;
    this.invalidateQueue(uid);
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
    if (this.pendingQueues.get(uid)?.ws === ws) this.invalidateQueue(uid);
    if (this.sockets.get(uid) !== ws) return;               // outra aba/conexão mais nova
    this.sockets.delete(uid); this.mm.cancel(uid);
    const match = this.matches.get(this.byUser.get(uid));
    if (match && match.status !== 'finished') {
      const c = match.colorOf(uid);
      match.players[c].connected = false; match.players[c].leftAt = this.now();   // relógio continua correndo
      this.pushState(match, this.now());
    }
  }
  stop() { clearInterval(this.timer); this.pendingQueues.clear(); }
}
module.exports = { Ranked, MatchService: Ranked };
