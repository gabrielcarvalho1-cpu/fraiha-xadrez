'use strict';
const { look: publicLook } = require('../accounts/cosmetics');
// Serviço de partidas online: filas, partidas autoritativas, reconexão e resultado.
// A mesma classe atende o Ranked (kind='ranked': PL, conta obrigatória, grava no banco)
// e o Casual (kind='casual': sem PL, aceita convidado, nada é gravado).
const { MODES, CASUAL_MODES, ALL_MODES, CONFIG } = require('./config');
const { Matchmaker } = require('./matchmaker');
const { RankedMatch } = require('./match');
const { persistRanked } = require('./persist');
const { ChallengerLadder } = require('./challenger');
const RESULT_KEEP_MS = Number(process.env.FRAIHA_RESULT_KEEP_MS || 10 * 60 * 1000);

class Ranked {
  constructor({ send, cfg = CONFIG, now = () => Date.now(), kind = 'ranked' }) {
    this.send = send; this.cfg = cfg; this.now = now; this.backend = null;
    this.kind = kind; this.p = kind + '_'; this.rated = kind === 'ranked';
    this.modes = this.rated ? MODES : CASUAL_MODES; this.label = this.rated ? 'Ranked' : 'Casual';
    this.mm = new Matchmaker(cfg.matchmaking, this.modes, { open: !this.rated });
    this.matches = new Map(); this.byUser = new Map(); this.sockets = new Map();
    this.pendingQueues = new Map(); // uid -> revisão vigente e leituras ainda em andamento
    this.timer = setInterval(() => this.tick(), cfg.tickMs); this.timer.unref && this.timer.unref();
    this.challenger = this.rated ? new ChallengerLadder(this) : null;   // R143 · vagas do Challenger
  }
  // R143 · PL/liga + Força oculta (lidos do servidor, nunca do cliente)
  statsFull(uid) { return this.backend.store.getRankedStats(uid, { forca: true }); }
  fail(ws, message, code = '') { this.send(ws, { type: this.p + 'error', message, code }); }
  uidOf(ws) { return ws.identity ? ws.identity.id : ws.user ? ws.user.id : null; }
  // Partida ainda não encerrada deste usuário (para impedir duas partidas ao mesmo tempo).
  activeMatchOf(uid) { const m = this.matches.get(this.byUser.get(uid)); return m && m.status !== 'finished' ? m : null; }
  // H03 · resultado Ranked ainda sendo gravado (com novas tentativas). Enquanto isso o jogador não entra em outra
  // partida Ranked: o PL "antes" da próxima seria lido do banco ainda sem esta partida e a gravação dela falharia.
  persistPending(uid) { const m = this.matches.get(this.byUser.get(uid)); return !!(this.rated && m && m.status === 'finished' && m.persisting && m.saved === undefined); }
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
    return this.sessionLive(this.sockets.get(uid), uid) && !this.activeMatchOf(uid) && !this.persistPending(uid) && !this.busyElsewhere(uid);
  }
  canStartMatch(a, b) {
    if (a.userId === b.userId) return false;
    return [a, b].every(e => {
      const uid = e.userId;
      if (!this.sessionReady(this.sockets.get(uid), uid) || this.activeMatchOf(uid) || this.persistPending(uid) || this.mm.has(uid)) return false;
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
      if (this.persistPending(uid)) return this.fail(ws, 'Gravando o resultado da partida anterior. Tente de novo em instantes.', 'result_pending');
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
        if (this.persistPending(uid)) return this.fail(ws, 'Gravando o resultado da partida anterior. Tente de novo em instantes.', 'result_pending');
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
      return this.statsFull(uid).then(async all => {
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
    if (a === this.p + 'sync') return this.sync(ws, uid, match, m, now);
    if (a === this.p + 'rematch' || a === this.p + 'rematch_cancel') return this.rematch(ws, uid, m, a.endsWith('_cancel'), now);
    if (!match || match.id !== String(m.match_id || match.id)) return this.fail(ws, `Nenhuma partida ${this.label} ativa.`, 'no_match');
    const color = match.colorOf(uid);
    if (a === this.p + 'move') {
      const r = match.move(color, { from: m.from, to: m.to, promotion: String(m.promotion || 'Q') }, now);
      if (r.error) { this.fail(ws, r.error, 'move_rejected'); return this.pushState(match, now, color); }
      return this.after(match, now);
    }
    if (a === this.p + 'resign') { match.resign(color, now); return this.after(match, now); }
    if (a === this.p + 'draw_offer' || a === this.p + 'draw_accept' || a === this.p + 'draw_decline') {
      const r = a === this.p + 'draw_offer' ? match.offerDraw(color, now) : match.answerDraw(color, a === this.p + 'draw_accept', now);
      if (r.error) { this.fail(ws, r.error, 'draw_rejected'); return this.pushState(match, now, color); }
      if (a === this.p + 'draw_decline') { const ows = this.sockets.get(match.players[color === 'w' ? 'b' : 'w'].userId); if (ows) this.send(ows, { type: this.p + 'draw_declined', match_id: match.id }); }
      return this.after(match, now);
    }
    return this.fail(ws, `Ação ${this.label} desconhecida.`);
  }
  // R53 · sincronia pedida pelo cliente (ao reconectar no meio de uma partida). A partida pedida pode já ter
  // terminado enquanto ele estava fora (o adversário desistiu, o tempo acabou): o servidor guarda a partida
  // encerrada por RESULT_KEEP_MS e devolve o estado FINAL + o resultado só para quem jogou nela. Partida
  // desconhecida (expirou / servidor reiniciou): *_idle com o match_id pedido, para o cliente sair do estado preso.
  sync(ws, uid, match, m, now) {
    const askedId = m.match_id ? String(m.match_id) : '';
    const asked = askedId ? this.matches.get(askedId) : match;
    const c = asked ? asked.colorOf(uid) : null;
    if (!asked || !c) return this.send(ws, { type: this.p + 'idle', match_id: askedId });
    asked.players[c].connected = true; asked.players[c].leftAt = 0;
    if (asked.status !== 'finished') return this.pushState(asked, now, c);
    this.send(ws, asked.state(c, now));
    // resultado já gravado: manda agora; gravação em andamento: persist() manda quando terminar (conectado de novo)
    if (asked.saved !== undefined) this.send(ws, asked.resultFor(c, asked.saved));
  }
  // R98 · REVANCHE: depois do fim, os dois pedem (ou um pede e o outro aceita) → nova partida no mesmo ritmo,
  // cores trocadas. No Ranked o PL é lido de novo do banco (já com a partida anterior gravada).
  rematchStatus(old, extra = {}) {
    for (const c of ['w', 'b']) {
      const ws = this.sockets.get(old.players[c].userId), o = c === 'w' ? 'b' : 'w';
      if (ws) this.send(ws, { type: this.p + 'rematch_status', match_id: old.id, mine: old.rematch[c], theirs: old.rematch[o], ...(extra[c] || {}) });
    }
  }
  rematch(ws, uid, m, cancel, now) {
    const old = this.matches.get(String(m.match_id || '')), c = old ? old.colorOf(uid) : null;
    const gone = msg => this.send(ws, { type: this.p + 'rematch_status', match_id: String(m.match_id || ''), mine: false, theirs: false, closed: true, message: msg });
    if (this.rated) return gone('Revanche só existe na partida casual.');   // R158 · nunca no ranked
    if (!old || !c || old.status !== 'finished' || old.rematchId) return gone('A revanche não está mais disponível.');
    const o = c === 'w' ? 'b' : 'w', oppUid = old.players[o].userId;
    if (cancel) {
      const declined = old.rematch[o] && !old.rematch[c];
      old.rematch[c] = false; if (declined) old.rematch[o] = false;
      return this.rematchStatus(old, declined ? { [o]: { declined: true, message: 'O adversário recusou a revanche.' } } : {});
    }
    if (old.rematchStarting) return;
    if (this.activeMatchOf(uid) || this.busyElsewhere(uid)) return gone('Você já está em outra partida ou fila.');
    if (!this.sessionLive(this.sockets.get(oppUid), oppUid)) return gone('O adversário saiu.');
    if (this.activeMatchOf(oppUid) || this.busyElsewhere(oppUid) || this.mm.has(oppUid)) return gone('O adversário já está em outra partida.');
    if (this.backend && this.backend.modeOpen && !this.backend.modeOpen(this.kind, old.mode)) return gone(require('../admin/controls').CLOSED_MESSAGE);
    if (this.rated && old.saved === undefined) return this.fail(ws, 'Gravando o resultado da partida. Tente de novo em instantes.', 'result_pending');
    this.mm.cancel(uid);
    old.rematch[c] = true;
    if (!old.rematch[o]) return this.rematchStatus(old);
    old.rematchStarting = true;
    const entry = (col, stats) => {
      const p = old.players[col], pws = this.sockets.get(p.userId);
      const id = (pws && pws.identity) || p;
      return { userId: p.userId, nickname: id.nickname || p.nickname, avatar: id.avatar || p.avatar, ...publicLook(id), stats, since: this.now() };
    };
    const stats = this.rated ? Promise.all(['w', 'b'].map(col => this.statsFull(old.players[col].userId).then(all => all[old.mode])))
      : Promise.resolve([null, null]);
    return stats.then(([sw, sb]) => {
      // cores trocadas: quem era Pretas agora joga de Brancas
      const match = this.startMatch(old.mode, entry('b', sb), entry('w', sw), this.now(), true);
      old.rematchId = match.id;
      console.log('[rematch]', old.id, '->', match.id, this.kind);
    }).catch(error => {
      old.rematch = { w: false, b: false };
      const msg = error && error.code === 'player_unavailable' ? 'Um dos jogadores não está mais disponível.' : 'Não foi possível começar a revanche agora.';
      this.rematchStatus(old, { w: { closed: true, message: msg }, b: { closed: true, message: msg } });
    }).finally(() => { old.rematchStarting = false; });
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
      // H03: novas tentativas seguras; nunca aplica PL duas vezes (ver ranked/persist.js)
      const r = await persistRanked(this.backend.store, match.record());
      saved = r.saved;
      if (r.attempts > 1 || r.already) console.log('ranked persist', match.id, JSON.stringify({ saved: r.saved, attempts: r.attempts, already: r.already }));
    }
    match.saved = saved;
    if (this.challenger) {
      match.challengerSlots = this.challenger.slots[match.mode] || 0;
      if (saved) void this.challenger.sync(match.mode);   // alguém pode ter chegado a Grão-Mestre 100 / caído do Challenger
    }
    if (!this.rated && match.result) this.recordCasual(match);
    // R105 · indicação: partida online terminada contra outra pessoa conta para a conta convidada
    const R = this.backend && this.backend.referrals;
    if (R && match.result && ((match.pos && match.pos.ply) || 0) >= 10) {   // pelo menos 5 lances de cada lado (desistência na hora não conta)
      const { UUID_RE } = require('../accounts/store');
      const ids = ['w', 'b'].map(c => String(match.players[c].userId || ''));
      if (ids.every(id => UUID_RE.test(id)) && ids[0] !== ids[1]) for (const id of ids) R.onGame(id);
    }
    // R112 · Coroas: cada conta da partida (10+ lances) ganha pela vitória / pela partida jogada
    const CR = this.backend && this.backend.crowns;
    if (CR && match.result && ((match.pos && match.pos.ply) || 0) >= 10) {
      const w = match.result.winner;
      for (const c of ['w', 'b']) CR.onGame(String(match.players[c].userId || ''), { kind: this.kind, ref: match.id, result: w === 'draw' ? 'draw' : w === c ? 'win' : 'loss' });
    }
    for (const c of ['w', 'b']) {
      const uid = match.players[c].userId, ws = this.sockets.get(uid);
      if (ws && match.players[c].connected) this.send(ws, match.resultFor(c, saved));
      if (this.byUser.get(uid) === match.id) this.byUser.delete(uid);
      this.presence(uid);
    }
    // R53 · a partida encerrada fica guardada um tempo: quem caiu bem na hora do fim recebe o resultado ao voltar
    setTimeout(() => this.matches.delete(match.id), RESULT_KEEP_MS).unref();
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
  startMatch(mode, a, b, now = this.now(), aIsWhite = false) {
    if (!this.canStartMatch(a, b)) {
      const error = new Error('Jogador indisponível para iniciar partida.'); error.code = 'player_unavailable'; throw error;
    }
    // Servidor sorteia as cores. FRAIHA_TEST_FIXED_COLORS=1 (só testes): quem entrou primeiro joga de Brancas.
    const flip = aIsWhite ? true : process.env.FRAIHA_TEST_FIXED_COLORS === '1' ? (a.since || 0) <= (b.since || 0) : Math.random() < 0.5;
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
  stop() { clearInterval(this.timer); this.pendingQueues.clear(); if (this.challenger) this.challenger.stop(); }
}
module.exports = { Ranked, MatchService: Ranked };
