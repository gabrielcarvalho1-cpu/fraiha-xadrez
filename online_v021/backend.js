'use strict';
// Camada do servidor: contas (acct_*), convidados (guest_auth), Ranked (ranked_*) e Casual (casual_*).
// As salas antigas por código continuam no server.js (uso interno), sem alterações.
const crypto = require('crypto');
const { AsyncLocalStorage } = require('async_hooks');
const { SupabaseAuth, DevAuth } = require('./accounts/auth');
const { MemoryStore, SupabaseStore, validateNickname, nextNickChange } = require('./accounts/store');
const { validateAvatarUpload } = require('./accounts/avatar');
const { ChatHub } = require('./chat');
const { Social } = require('./social/service');
const { DirectMessages } = require('./social/dm');
const { Invites } = require('./social/invites');
const { Presence } = require('./social/presence');
const { Payments } = require('./payments/service');
const { BotService } = require('./bots/service');
const { Party } = require('./modes/party');
const Cosmetics = require('./accounts/cosmetics');

const GUEST_TTL_MS = 24 * 3600e3;
const SESSION_REVALIDATE_MS = 60e3;
const SESSION_MAX_MS = 3600e3; // limite também para tokens opacos/dev sem exp
const AUTH_TIMEOUT_MS = 10e3;
const CANCELLED = Symbol('session_cancelled');
// Análise pós-partida: contas sem Club têm N análises por dia (dia UTC, relógio do servidor).
const ANALYSIS_FREE_PER_DAY = Number(process.env.FRAIHA_ANALYSIS_FREE_PER_DAY || 3);
// R44 · fase de testes: SEM LIMITE (0 = livre para todos). Para voltar a limitar: FRAIHA_MARCHA_FREE_PER_DAY=N no Render.
const MARCHA_FREE_PER_DAY = Number(process.env.FRAIHA_MARCHA_FREE_PER_DAY || 0);   // R32: Marcha Real sem Club
const utcDay = () => new Date().toISOString().slice(0, 10);
const nextUtcMidnight = () => { const d = new Date(); d.setUTCHours(24, 0, 0, 0); return d.toISOString(); };

function createBackend(env = process.env) {
  const url = env.SUPABASE_URL || '';
  const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_SECRET_KEY || '';
  // Teste local: Auth real (ou simulado) + armazenamento em memória. Nunca em produção.
  if (url && env.FRAIHA_DEV_STORE === 'memory') return { kind: 'dev', auth: new SupabaseAuth({ url, apiKey: env.SUPABASE_ANON_KEY || 'dev' }), store: new MemoryStore() };
  if (url && serviceKey) {
    return { kind: 'supabase', auth: new SupabaseAuth({ url, apiKey: env.SUPABASE_ANON_KEY || serviceKey }), store: new SupabaseStore({ url, serviceKey }) };
  }
  if (env.FRAIHA_DEV_AUTH === '1') return { kind: 'dev', auth: new DevAuth(), store: new MemoryStore() };
  return { kind: 'disabled', auth: null, store: null };
}

class Backend {
  constructor(opts = {}) {
    Object.assign(this, createBackend(opts.env || process.env));
    this.sessions = new WeakMap(); // token privado ao backend, nunca no payload público
    this.operations = new AsyncLocalStorage();
    this.now = opts.now || (() => Date.now());
    this.setTimer = opts.setTimer || setTimeout;
    this.clearTimer = opts.clearTimer || clearTimeout;
    const deliver = (ws, o) => {
      const s = this.session(ws);
      if (!s.closed && (ws.readyState === undefined || ws.readyState === 1)) opts.send(ws, o);
    };
    this.send = (ws, o) => {
      const op = this.operations.getStore();
      if (op && op.active && !this.current(op.ws, op.revision)) return;
      if (op && op.active && !op.auth && !this.ready(op.ws, op.revision)) {
        // R42: revalidação de rotina (a cada 60 s) em andamento no meio de uma operação longa
        // (ex.: pagamento esperando o Mercado Pago): a resposta espera a revalidação e só é
        // entregue se a sessão continuar válida — não é descartada. Login/troca de conta: descarta.
        if (this.session(op.ws).authPending) return;
        const { ws: opWs, revision } = op;
        this.operations.run(null, () => this.ensureSession(opWs)).then(ok => {
          if (ok && this.current(opWs, revision)) deliver(ws, o);
        }, () => {});
        return;
      }
      deliver(ws, o);
    };
    this.ranked = null; // conectado em attachRanked()
    this.casual = null; // conectado em attachCasual()
    this.guests = new Map(); // token -> { id, nickname, seen }
    this.chat = new ChatHub({ send: (ws, o) => this.send(ws, o) });
    this.online = new Map(); // uid -> Set(ws) (contas e convidados identificados)
    this.social = new Social({ send: (ws, o) => this.send(ws, o), backend: this });
    this.dm = new DirectMessages({ send: (ws, o) => this.send(ws, o), backend: this });
    this.invites = new Invites({ send: (ws, o) => this.send(ws, o), backend: this });
    this.presence = new Presence({ send: (ws, o) => this.send(ws, o), backend: this });
    this.payments = new Payments({ send: (ws, o) => this.send(ws, o), backend: this });
    this.party = new Party({ send: (ws, o) => this.send(ws, o), backend: this });   // R35: MARCHA REAL / XEQUE online
    this.bots = this.store ? new BotService({ store: this.store, send: (ws, o) => this.send(ws, o), backend: this }) : null;
    this.sweeper = setInterval(() => this.sweepGuests(), 600e3); this.sweeper.unref && this.sweeper.unref();
  }
  session(ws) {
    if (!this.sessions.has(ws)) this.sessions.set(ws, { revision: 0, stateRevision: 0, closed: false });
    return this.sessions.get(ws);
  }
  current(ws, revision) {
    const s = this.session(ws);
    return !s.closed && s.revision === revision && !ws.dead &&
      (ws.readyState === undefined || ws.readyState === 1) &&
      (!s.token || this.now() < s.expiresAt);
  }
  ready(ws, revision = this.session(ws).revision) {
    const s = this.session(ws);
    return this.current(ws, revision) && !s.authPending &&
      (!s.token || (!s.revalidation && this.now() < s.revalidateAt));
  }
  operation(ws) {
    const context = this.operations.getStore();
    ws = ws || (context && context.active && context.ws);
    if (!ws) return { assert() {}, wait: action => action() };
    const revision = context && context.active && context.ws === ws ? context.revision : this.session(ws).revision;
    const uid = ws.user ? ws.user.id : ws.identity && ws.identity.id;
    const profile = ws.profile && { ...ws.profile }, identity = ws.identity && { ...ws.identity };
    const assert = () => {
      if (!this.ready(ws, revision) || (ws.user ? ws.user.id : ws.identity && ws.identity.id) !== uid) throw CANCELLED;
    };
    return { uid, profile, identity, assert, wait: async action => {
      if (!this.current(ws, revision)) throw CANCELLED;
      if (!this.ready(ws, revision) && !(await this.ensureSession(ws))) throw CANCELLED;
      assert();
      const value = await this.checked(ws, revision, action());
      assert();
      return value;
    } };
  }
  cancelled(error) { return error === CANCELLED; }
  async checked(ws, revision, promise) {
    const value = await promise;
    if (!this.current(ws, revision)) throw CANCELLED;
    const s = this.session(ws);
    // Operação iniciada antes do prazo também precisa de validade ao retomar.
    if (s.authPending || (s.token && (s.revalidation || this.now() >= s.revalidateAt) && !(await this.ensureSession(ws)))) throw CANCELLED;
    if (!this.current(ws, revision)) throw CANCELLED;
    return value;
  }
  invalidate(ws, { closed = false } = {}) {
    const s = this.session(ws);
    ++s.revision; ++s.stateRevision;
    this.clearTimer(s.timer);
    s.timer = null; s.token = null; s.expiresAt = 0; s.revalidateAt = 0; s.revalidation = null;
    s.authPending = false; s.authPrevious = null;
    // Serviços recebem a identidade antiga para desligar filas/mesas antes da limpeza.
    this.operations.run(null, () => this.setIdentity(ws, null));
    ws.user = null; ws.profile = null; ws.guest = null;
    ws.cosmeticsAt = null; ws.guestAuthAt = null;
    s.closed = closed;
    return s.revision;
  }
  beginAuth(ws) {
    const s = this.session(ws);
    const previous = s.authPrevious || (ws.user && ws.profile && this.current(ws, s.revision)
      ? { user: ws.user, profile: ws.profile, expiresAt: s.expiresAt } : null);
    if (!previous || this.now() >= previous.expiresAt) this.invalidate(ws);
    else {
      ++s.revision; ++s.stateRevision;
      this.clearTimer(s.timer);
      s.timer = null; s.token = null; s.revalidation = null;
      for (const game of this.games()) if (game.invalidateQueue) game.invalidateQueue(previous.user.id);
      ws.user = null; ws.profile = null;
    }
    s.authPrevious = previous;
    s.authPending = true;
  }
  async verifyToken(token, force = false) {
    let timer;
    try {
      return await Promise.race([
        this.auth.verify(token, { force }),
        new Promise(resolve => { timer = this.setTimer(() => resolve(null), AUTH_TIMEOUT_MS); timer.unref && timer.unref(); }),
      ]);
    } finally { this.clearTimer(timer); }
  }
  armSession(ws, revision) {
    const s = this.session(ws);
    this.clearTimer(s.timer);
    const due = s.revalidation ? s.expiresAt : Math.min(s.expiresAt, s.revalidateAt);
    s.timer = this.setTimer(() => {
      if (s.revision !== revision || s.closed) return;
      if (this.now() >= s.expiresAt) return this.expireSession(ws);
      void this.ensureSession(ws);
    }, Math.max(0, due - this.now()));
    s.timer.unref && s.timer.unref();
  }
  expireSession(ws) {
    this.invalidate(ws);
    // Timer pode ter herdado um contexto antigo: erro de invalidação é da sessão atual.
    this.operations.run(null, () => this.fail(ws, 'Sessão inválida ou expirada. Entre novamente.', { code: 'invalid_token' }));
  }
  async ensureSession(ws) {
    const s = this.session(ws), revision = s.revision;
    if (s.authPending) return false;
    if (s.token && this.now() >= s.expiresAt) { this.expireSession(ws); return false; }
    if (!this.current(ws, revision)) return false;
    if (!s.token) return !s.closed;
    if (!s.revalidation && this.now() < s.revalidateAt) return true;
    if (!s.revalidation) {
      s.revalidation = (async () => {
        let user;
        try { user = await this.verifyToken(s.token, true); } catch { user = null; }
        if (!this.current(ws, revision)) return false;
        if (!user || !ws.user || user.id !== ws.user.id) { this.expireSession(ws); return false; }
        // Uma revalidação não prolonga o exp do token nem a duração máxima da sessão.
        s.revalidateAt = this.now() + SESSION_REVALIDATE_MS;
        return true;
      })();
      this.armSession(ws, revision); // expiração continua ativa durante Auth lento
    }
    const pending = s.revalidation;
    const ok = await pending;
    if (this.current(ws, revision) && s.revalidation === pending) {
      s.revalidation = null;
      this.armSession(ws, revision);
    }
    return ok && this.current(ws, revision);
  }
  attachRanked(ranked) { this.ranked = ranked; ranked.backend = this; }
  attachCasual(casual) { this.casual = casual; casual.backend = this; }
  games() { return [this.ranked, this.casual].filter(Boolean); }
  fail(ws, message, extra = {}) { this.send(ws, { type: 'acct_error', message, ...extra }); }
  // Usuário já está numa partida ativa ou fila de OUTRO serviço? (nunca duas partidas ao mesmo tempo)
  busyElsewhere(uid, service) {
    if (this.invites && this.invites.reserved(uid)) return true; // convite sendo aceito: partida prestes a começar
    for (const g of this.games()) if (g !== service && (g.activeMatchOf(uid) || g.mm.has(uid))) return true;
    if (this.party && this.party.activeMatchOf(uid)) return true;      // mesa online de MARCHA REAL / XEQUE
    return false;
  }
  // Amizade desfeita/bloqueio (chamados pelo serviço de Amigos): cancela convite pendente entre os dois.
  onBlocked(a, b) { if (this.invites) this.invites.onRelationChanged(a, b); }
  onUnfriended(a, b) { if (this.invites) this.invites.onRelationChanged(a, b); }
  // Entrar em fila (Casual/Ranked) cancela o convite pendente do jogador; durante o aceite, a fila é recusada.
  beforeQueue(ws, kind) {
    const uid = ws.identity && ws.identity.id;
    if (!uid || !this.invites) return true;
    if (this.invites.reserved(uid)) { this.send(ws, { type: kind + '_error', message: 'Sua partida do convite está começando.', code: 'busy' }); return false; }
    this.invites.onQueue(uid);
    return true;
  }
  inMatch(uid) { return this.games().some(g => !!g.activeMatchOf(uid)) || !!(this.party && this.party.activeMatchOf(uid)); }
  // Sessões/partidas mudaram: o serviço de presença recalcula (com tolerância) e avisa amigos se mudou.
  presenceChanged(uid) { if (this.presence) this.presence.changed(uid); }
  socketsOf(uid) { return [...(this.online.get(uid) || [])].filter(ws => ws.readyState === undefined || ws.readyState === 1); }
  // Presença pública publicada (com tolerância): só o estado, nunca dados de conexão.
  presenceOf(uid) { return this.presence ? this.presence.stateOf(uid) : 'offline'; }
  presenceRevOf(uid) { return this.presence ? this.presence.revOf(uid) : 0; }
  setIdentity(ws, identity) {
    const old = ws.identity;
    if (old && (!identity || old.id !== identity.id)) {
      for (const g of this.games()) g.onClose(ws);
      if (this.party) this.party.onClose(ws);
      this.unlink(ws, old.id);
    }
    ws.identity = identity;
    if (identity && (!old || old.id !== identity.id)) {
      if (!this.online.has(identity.id)) this.online.set(identity.id, new Set());
      const set = this.online.get(identity.id), was = set.size;
      set.add(ws);
      if (!was) this.presenceChanged(identity.id);
    }
  }
  unlink(ws, uid) {
    const set = this.online.get(uid);
    if (!set || !set.delete(ws)) return;
    if (!set.size) { this.online.delete(uid); this.presenceChanged(uid); }
  }
  // Resumo da cota de análise (servidor é a autoridade): usado/limite/renovação, ou ilimitado (Club).
  async analysisSummary(uid, ent) {
    if (ent && ent.club_active) return { unlimited: true, used: 0, limit: 0, resets_at: null };
    const used = await this.store.analysisUsage(uid, utcDay());
    return { unlimited: false, used, limit: ANALYSIS_FREE_PER_DAY, resets_at: nextUtcMidnight() };
  }
  async state(ws) {
    try { return await this.buildState(ws); }
    catch (e) { if (e === CANCELLED) return false; throw e; }
  }
  async buildState(ws) {
    const s = this.session(ws), revision = s.revision, op = this.operations.getStore();
    if (!ws.user || !this.current(ws, revision) || (op && op.ws === ws && op.revision !== revision)) return false;
    const stateRevision = ++s.stateRevision, u = ws.user;
    const profile = await this.checked(ws, revision, this.store.getProfile(u.id));
    const ranked = profile ? await this.checked(ws, revision, this.store.getRankedStats(u.id)) : null;
    const entitlements = profile ? await this.checked(ws, revision, this.store.getEntitlements(u.id)) : null;
    const analysis = profile ? await this.checked(ws, revision, this.analysisSummary(u.id, entitlements)) : null;
    const bots = profile && this.bots ? await this.checked(ws, revision, this.bots.summary(u.id)) : null;
    if (s.stateRevision !== stateRevision || !this.ready(ws, revision)) return false;
    ws.profile = profile;
    const look = profile ? Cosmetics.effective(profile, entitlements) : null;
    if (profile) { ws.guest = null; this.setIdentity(ws, { id: u.id, nickname: profile.nickname, avatar: look.avatar_id, badge: look.badge, title: look.title, frame: look.frame, founder: look.founder, club: look.club, guest: false }); }
    else this.setIdentity(ws, null);
    // nickname_next_change_at: calculado pelo SERVIDOR (cooldown de 30 dias); o cliente só exibe.
    const pubProfile = profile ? { ...profile, nickname_next_change_at: nextNickChange(profile) } : null;
    this.send(ws, { type: 'acct_state', user_id: u.id, email: u.email, provider: u.provider, profile: pubProfile,
      needs_nickname: !profile, ranked, persistent: !!this.store.persistent, backend: this.kind,
      entitlements: entitlements ? { is_founder: !!entitlements.is_founder, club_active: !!entitlements.club_active, club_expires_at: entitlements.club_expires_at || null } : null,
      founder_perks: this.payments ? this.payments.founderPerks(entitlements) : null,
      cosmetics: look ? { avatar_id: look.avatar_id, badge: look.badge, title: look.title, frame: look.frame } : null,
      analysis, bots });
    return true;
  }
  // Convidado: identidade só em memória, recuperável pelo token (reconexão ao Casual).
  guestAuth(ws, m) {
    if (ws.user && ws.profile) return this.send(ws, { type: 'guest_state', account: true, nickname: ws.profile.nickname });
    const now = Date.now();
    if (ws.guestAuthAt && now - ws.guestAuthAt < 2000) return this.send(ws, { type: 'guest_error', message: 'Aguarde um instante.' });
    this.invalidate(ws);
    ws.guestAuthAt = now;
    let token = String(m.token || '');
    let g = /^[a-f0-9]{48}$/.test(token) ? this.guests.get(token) : null;
    if (!g) {
      token = crypto.randomBytes(24).toString('hex');
      g = { id: 'guest:' + crypto.randomUUID(), nickname: 'Convidado ' + String(crypto.randomInt(1000, 10000)) };
      this.guests.set(token, g);
    }
    g.seen = now;
    ws.guest = g;
    this.setIdentity(ws, { id: g.id, nickname: g.nickname, avatar: 'warrior', guest: true });
    this.send(ws, { type: 'guest_state', token, nickname: g.nickname });
    if (this.casual) this.casual.onAuthenticated(ws);
  }
  sweepGuests() {
    const now = Date.now();
    for (const [t, g] of this.guests) if (now - (g.seen || 0) > GUEST_TTL_MS && !this.inMatch(g.id)) this.guests.delete(t);
  }
  async handle(ws, m) {
    const s = this.session(ws), a = String(m.type || '');
    if (s.closed || ws.dead || (ws.readyState !== undefined && ws.readyState !== 1)) return;
    if (a === 'acct_logout') {
      this.invalidate(ws);
      return this.send(ws, { type: 'acct_logged_out' });
    }
    if (a === 'guest_auth') {
      const revision = s.revision;
      if (s.token && this.now() >= Math.min(s.expiresAt, s.revalidateAt) && !(await this.ensureSession(ws))) return;
      if (!this.current(ws, revision)) return;
      return this.guestAuth(ws, m);
    }
    if ((a === 'ranked_cancel' || a === 'casual_cancel') && ws.identity && this.current(ws, s.revision)) {
      const game = a === 'ranked_cancel' ? this.ranked : this.casual;
      const uid = ws.identity.id;
      if (game && game.sockets.get(uid) === ws) {
        game.invalidateQueue(uid);
        const entry = game.mm.cancel(uid);
        return this.operations.run(null, () => this.send(ws, { type: game.p + 'cancelled', was_queued: !!entry }));
      }
    }
    if (a === 'acct_auth') this.beginAuth(ws);
    const revision = s.revision;
    if (a !== 'acct_auth' && !this.ready(ws, revision) && !(await this.ensureSession(ws))) return;
    if (!this.current(ws, revision)) return;
    const operation = { ws, revision, active: true, auth: a === 'acct_auth' };
    return this.operations.run(operation, async () => {
      try { return await this.handleCurrent(ws, m, revision); }
      finally { operation.active = false; }
    });
  }
  async handleCurrent(ws, m, revision) {
    const a = String(m.type || '');
    try {
      if (a.startsWith('casual_')) {
        if (!ws.identity) return this.send(ws, { type: 'casual_error', message: 'Conectando ao servidor… tente novamente.', code: 'identity_required' });
        if (ws.guest) ws.guest.seen = Date.now();
        if (a === 'casual_queue' && !this.beforeQueue(ws, 'casual')) return;
        return this.casual ? this.casual.handle(ws, m) : this.send(ws, { type: 'casual_error', message: 'Casual indisponível.' });
      }
      if (a.startsWith('chat_')) {
        const uid = ws.identity && ws.identity.id;
        if (!uid) return this.send(ws, { type: 'chat_error', message: 'Conectando ao servidor…', code: 'identity_required' });
        const g = this.games().find(x => x.activeMatchOf(uid)) || this.games().find(x => x.matchOf(uid));
        return this.chat.handle(ws, m, uid, g ? g.matchOf(uid) : null, g);
      }
      if (a.startsWith('ranked_')) {
        if (!ws.user || !ws.profile) return this.fail(ws, 'Crie uma conta ou entre para jogar partidas ranqueadas.', { code: 'auth_required' });
        if (a === 'ranked_queue' && !this.beforeQueue(ws, 'ranked')) return;
        return this.ranked ? this.ranked.handle(ws, m) : this.fail(ws, 'Ranked indisponível.');
      }
      if (this.kind === 'disabled') return this.fail(ws, 'Contas ainda não configuradas no servidor.', { code: 'accounts_disabled' });
      if (a.startsWith('invite_')) {
        if (!ws.user || !ws.profile) return this.send(ws, { type: 'invite_error', message: 'Entre ou crie uma conta para convidar amigos.', code: 'auth_required' });
        try { return await this.invites.handle(ws, m); }
        catch (e) {
          if (e === CANCELLED) return;
          console.error('invite', a, e && e.message);
          return this.send(ws, { type: 'invite_error', message: 'Erro temporário no servidor. Tente novamente.', code: 'server_error' });
        }
      }
      if (a.startsWith('party_')) {
        if (!ws.user || !ws.profile) return this.send(ws, { type: 'party_error', message: 'Entre na sua conta para jogar com amigos.', code: 'auth_required' });
        return this.party.handle(ws, m);
      }
      if (a.startsWith('dm_')) {
        if (!ws.user || !ws.profile) return this.send(ws, { type: 'dm_error', message: 'Entre ou crie uma conta para conversar com amigos.', code: 'auth_required' });
        try { return await this.dm.handle(ws, m); }
        catch (e) {
          if (e === CANCELLED) return;
          const uid = String(m.user_id || '');
          if (e && /42P01|PGRST205|direct_messages.*does not exist|Could not find the table/.test(String(e.code) + ' ' + String(e.message))) return this.send(ws, { type: 'dm_error', message: 'Mensagens ainda não configuradas no servidor (migração 0003 pendente).', code: 'not_configured', user_id: uid });
          console.error('dm', a, e && e.message);
          return this.send(ws, { type: 'dm_error', message: 'Erro temporário no servidor. Tente novamente.', code: 'server_error', user_id: uid });
        }
      }
      if (a.startsWith('social_')) {
        if (!ws.user || !ws.profile) return this.send(ws, { type: 'social_error', message: 'Entre ou crie uma conta para usar Amigos.', code: 'auth_required' });
        try { return await this.social.handle(ws, m); }
        catch (e) {
          if (e === CANCELLED) return;
          if (e && /42P01|PGRST205|does not exist|Could not find the table/.test(String(e.code) + ' ' + String(e.message))) return this.send(ws, { type: 'social_error', message: 'Amigos ainda não configurado no servidor (migração 0002 pendente).', code: 'not_configured' });
          console.error('social', a, e && e.message);
          return this.send(ws, { type: 'social_error', message: 'Erro temporário no servidor. Tente novamente.', code: 'server_error' });
        }
      }
      if (a.startsWith('payment_')) return this.payments.handle(ws, m);
      if (a.startsWith('bot_')) {
        try { return await this.bots.handle(ws, m); }
        catch (e) { if (e === CANCELLED) return; console.error('bots', a, e && e.message); return this.send(ws, { type: 'bot_error', code: 'server_error', message: 'Erro temporário no servidor. Tente novamente.' }); }
      }
      if (a === 'acct_auth') {
        const user = await this.verifyToken(m.access_token, true);
        if (!this.current(ws, revision)) return;
        if (!user) return this.expireSession(ws);
        const s = this.session(ws);
        const previous = s.authPrevious;
        const renewed = !!previous && previous.user.id === user.id;
        if (!renewed) this.setIdentity(ws, null);
        s.authPending = false; s.authPrevious = null;
        s.expiresAt = Math.min(this.now() + SESSION_MAX_MS, Number.isFinite(user.expires_at) ? user.expires_at : Infinity);
        if (s.expiresAt <= this.now()) return this.expireSession(ws);
        s.token = String(m.access_token || '');
        s.revalidateAt = this.now() + SESSION_REVALIDATE_MS;
        this.armSession(ws, revision);
        ws.user = user;
        ws.profile = renewed ? previous.profile : null;
        const loginOp = this.operation(ws);
        const existing = await this.checked(ws, revision, this.store.getProfile(user.id));
        if (existing) await loginOp.wait(() => this.store.touchLogin(user.id));
        if (!(await this.checked(ws, revision, this.state(ws)))) return;
        loginOp.assert();
        if (existing && !renewed) for (const g of this.games()) g.onAuthenticated(ws);
        if (existing) this.invites.onAuthenticated(ws);
        if (existing && !renewed) this.party.onAuthenticated(ws);
        if (existing) await this.checked(ws, revision, this.presence.snapshot(ws));
        return;
      }
      if (!ws.user) return this.fail(ws, 'Entre na sua conta primeiro.', { code: 'auth_required' });
      const accountId = ws.user.id;
      const op = this.operation(ws);
      if (a === 'acct_create_profile') {
        const v = validateNickname(m.nickname);
        if (v.error) return this.fail(ws, v.error, { code: 'nickname_invalid' });
        const r = await op.wait(() => this.store.createProfile(accountId, v.nickname, String(m.avatar_id || 'warrior')));
        if (r.error) return this.fail(ws, r.error, { code: r.code || 'profile_error' });
        if (!(await this.checked(ws, revision, this.state(ws)))) return;
        return this.presence.snapshot(ws);
      }
      if (a === 'acct_refresh') return await this.state(ws);
      // ---------- Análise pós-partida: pedir uma análise consome 1 do dia (Club: ilimitado) ----------
      if (a === 'analysis_request') {
        if (!ws.profile) return this.send(ws, { type: 'analysis_denied', code: 'auth_required', message: 'Entre na sua conta para analisar partidas.' });
        const denyInMatch = () => this.send(ws, { type: 'analysis_denied', code: 'in_match', message: 'Análise indisponível durante partida humana ativa. Aguarde o encerramento.' });
        if (this.inMatch(accountId)) return denyInMatch();
        const ent = await this.checked(ws, revision, this.store.getEntitlements(accountId));
        if (!this.ready(ws, revision)) return;
        if (this.inMatch(accountId)) return denyInMatch();
        if (ent.club_active) return this.send(ws, { type: 'analysis_granted', unlimited: true, used: 0, limit: 0, resets_at: null });
        const r = await op.wait(() => this.inMatch(accountId) ? { in_match: true } : this.store.analysisConsume(accountId, utcDay(), ANALYSIS_FREE_PER_DAY));
        if (!this.ready(ws, revision)) return;
        if (r.in_match || this.inMatch(accountId)) return denyInMatch();
        if (r.not_configured) return this.send(ws, { type: 'analysis_denied', code: 'not_configured', message: 'Análise ainda não configurada no servidor (migração 0005 pendente).' });
        if (!r.ok) return this.send(ws, { type: 'analysis_denied', code: 'quota', used: r.used, limit: ANALYSIS_FREE_PER_DAY, resets_at: nextUtcMidnight(), message: 'Você usou suas análises gratuitas de hoje.' });
        return this.send(ws, { type: 'analysis_granted', unlimited: false, used: r.used, limit: ANALYSIS_FREE_PER_DAY, resets_at: nextUtcMidnight() });
      }
      if (a === 'analysis_record') {
        if (!ws.profile) return;
        const sum = m.summary && typeof m.summary === 'object' ? m.summary : null;
        if (!sum) return;
        try { await op.wait(() => this.store.saveAnalysis(accountId, sum)); } catch (e) { /* histórico é opcional (0005) */ }
        return;
      }
      if (a === 'analysis_status') {
        if (!ws.profile) return this.send(ws, { type: 'analysis_state', unlimited: false, used: 0, limit: ANALYSIS_FREE_PER_DAY, resets_at: nextUtcMidnight(), guest: true });
        const ent = await this.checked(ws, revision, this.store.getEntitlements(accountId));
        return this.send(ws, { type: 'analysis_state', ...(await this.checked(ws, revision, this.analysisSummary(accountId, ent))) });
      }
      // ---------- R32 · MARCHA REAL: Club = ilimitado; sem Club = MARCHA_FREE_PER_DAY partidas por dia UTC ----------
      if (a === 'marcha_status' || a === 'marcha_start') {
        if (!ws.profile) return this.send(ws, { type: a === 'marcha_start' ? 'marcha_denied' : 'marcha_state', code: 'auth_required', unlimited: false, used: 0, limit: MARCHA_FREE_PER_DAY });
        const ent = await this.checked(ws, revision, this.store.getEntitlements(accountId));
        if (ent.club_active || MARCHA_FREE_PER_DAY <= 0) return this.send(ws, { type: a === 'marcha_start' ? 'marcha_granted' : 'marcha_state', unlimited: true, used: 0, limit: 0, free_for_all: !ent.club_active });
        if (a === 'marcha_status') {
          const used = await this.checked(ws, revision, this.store.marchaUsage(accountId, utcDay()));
          if (used && used.not_configured) return this.send(ws, { type: 'marcha_state', code: 'not_configured', unlimited: false });
          return this.send(ws, { type: 'marcha_state', unlimited: false, used: Number(used) || 0, limit: MARCHA_FREE_PER_DAY, resets_at: nextUtcMidnight() });
        }
        const r = await op.wait(() => this.store.marchaConsume(accountId, utcDay(), MARCHA_FREE_PER_DAY));
        if (r.not_configured) return this.send(ws, { type: 'marcha_denied', code: 'not_configured', message: 'Limite diário da Marcha Real ainda não configurado no servidor (migração 0008 pendente).' });
        if (!r.ok) return this.send(ws, { type: 'marcha_denied', code: 'daily_limit', used: r.used, limit: MARCHA_FREE_PER_DAY, resets_at: nextUtcMidnight(), message: 'Você já jogou suas partidas grátis de hoje.' });
        return this.send(ws, { type: 'marcha_granted', unlimited: false, used: r.used, limit: MARCHA_FREE_PER_DAY, resets_at: nextUtcMidnight() });
      }
      // ---------- DEV: simular direitos no servidor em memória (nunca no Supabase) ----------
      if (a === 'dev_set_entitlements') {
        if (this.kind !== 'dev' || !ws.profile) return this.fail(ws, 'Só no servidor de desenvolvimento.', { code: 'dev_only' });
        await op.wait(() => this.store.setEntitlements(accountId, { is_founder: !!m.is_founder, club_active: !!m.club_active, club_expires_at: m.club_expires_at || null }));
        return await this.state(ws);
      }
      // ---------- R31: identidade cosmética (avatar, ícone, título, moldura) — servidor revalida pelos direitos ----------
      if (a === 'acct_set_cosmetics') {
        if (!ws.profile) return this.fail(ws, 'Crie seu perfil primeiro.', { code: 'profile_missing' });
        const now = Date.now();
        if (ws.cosmeticsAt && now - ws.cosmeticsAt < 800) return this.send(ws, { type: 'acct_cosmetics_error', code: 'rate_limited', message: 'Aguarde um instante.' });
        ws.cosmeticsAt = now;
        const ent = await this.checked(ws, revision, this.store.getEntitlements(accountId));
        let defeated = null;
        if (m.avatar_id !== undefined && this.bots) { const b = await this.checked(ws, revision, this.bots.summary(accountId)); defeated = b.available ? b.defeated : null; }
        const v = Cosmetics.validate(m, ent, defeated);
        if (v.error) return this.send(ws, { type: 'acct_cosmetics_error', code: v.code, field: v.field || '', message: v.error });
        const r = await op.wait(() => this.store.setCosmetics(accountId, v.values));
        if (r.error) return this.send(ws, { type: 'acct_cosmetics_error', code: r.code || 'profile_error', message: r.error });
        if (!(await this.checked(ws, revision, this.state(ws)))) return;
        this.presenceChanged(accountId);
        const look = Cosmetics.effective(r.profile, ent);
        return this.send(ws, { type: 'acct_cosmetics_saved', avatar_id: look.avatar_id, badge: look.badge, title: look.title, frame: look.frame, partial: !!r.partial });
      }
      // ---------- Nome público (0004) ----------
      if (a === 'acct_check_nickname') {
        const v = validateNickname(m.nickname);
        if (v.error) return this.send(ws, { type: 'acct_nickname_check', nickname: String(m.nickname || ''), available: false, error: v.error, code: 'nickname_invalid' });
        const free = await this.checked(ws, revision, this.store.nicknameAvailable(v.nickname, accountId));
        return this.send(ws, { type: 'acct_nickname_check', nickname: v.nickname, available: free, error: free ? '' : 'Esse nome já está sendo usado.', code: free ? '' : 'nickname_taken' });
      }
      if (a === 'acct_change_nickname') {
        if (!ws.profile) return this.fail(ws, 'Crie seu perfil primeiro.', { code: 'profile_missing' });
        const v = validateNickname(m.nickname);
        if (v.error) return this.fail(ws, v.error, { code: 'nickname_invalid' });
        const r = await op.wait(() => this.store.changeNickname(accountId, v.nickname));
        if (r.error) return this.fail(ws, r.error, { code: r.code || 'profile_error', next_change_at: r.next_change_at || null });
        if (!(await this.checked(ws, revision, this.state(ws)))) return;                       // atualiza ws.profile e a identidade pública (chat, amigos…)
        this.presenceChanged(accountId);
        return this.send(ws, { type: 'acct_nickname_changed', nickname: v.nickname, next_change_at: nextNickChange(r.profile) });
      }
      // ---------- Foto de perfil (0004): o cliente manda a imagem já recortada (512x512); o servidor revalida ----------
      if (a === 'acct_avatar_upload') {
        if (!ws.profile) return this.fail(ws, 'Crie seu perfil primeiro.', { code: 'profile_missing' });
        const v = validateAvatarUpload(m.data);
        if (v.error) return this.fail(ws, v.error, { code: 'avatar_invalid' });
        const r = await op.wait(() => this.store.saveAvatar(accountId, v.bytes, v.mime));
        if (r.error) return this.fail(ws, r.error, { code: r.code || 'avatar_error' });
        if (!(await this.checked(ws, revision, this.state(ws)))) return;
        return this.send(ws, { type: 'acct_avatar_saved', avatar_url: r.profile.avatar_url || null });
      }
      if (a === 'acct_avatar_clear') {
        if (!ws.profile) return this.fail(ws, 'Crie seu perfil primeiro.', { code: 'profile_missing' });
        const r = await op.wait(() => this.store.clearAvatar(accountId));
        if (r.error) return this.fail(ws, r.error, { code: r.code || 'avatar_error' });
        if (!(await this.checked(ws, revision, this.state(ws)))) return;
        return this.send(ws, { type: 'acct_avatar_saved', avatar_url: null });
      }
      return this.fail(ws, 'Ação de conta desconhecida.');
    } catch (e) {
      if (e === CANCELLED || !this.current(ws, revision)) return;
      if (a === 'acct_auth' && this.session(ws).authPending) return this.expireSession(ws);
      console.error('backend', a, e && e.message);
      return this.fail(ws, 'Erro temporário no servidor. Tente novamente.', { code: 'server_error' });
    }
  }
  onClose(ws) {
    this.invalidate(ws, { closed: true });
  }
}

module.exports = { Backend, createBackend };
