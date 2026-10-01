'use strict';
// Camada do servidor: contas (acct_*), convidados (guest_auth), Ranked (ranked_*) e Casual (casual_*).
// As salas antigas por código continuam no server.js (uso interno), sem alterações.
const crypto = require('crypto');
const { SupabaseAuth, DevAuth } = require('./accounts/auth');
const { MemoryStore, SupabaseStore, validateNickname, nextNickChange } = require('./accounts/store');
const { validateAvatarUpload } = require('./accounts/avatar');
const { ChatHub } = require('./chat');
const { Social } = require('./social/service');
const { DirectMessages } = require('./social/dm');
const { Invites } = require('./social/invites');
const { Presence } = require('./social/presence');

const GUEST_TTL_MS = 24 * 3600e3;

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
    this.send = opts.send;
    this.ranked = null; // conectado em attachRanked()
    this.casual = null; // conectado em attachCasual()
    this.guests = new Map(); // token -> { id, nickname, seen }
    this.chat = new ChatHub({ send: (ws, o) => this.send(ws, o) });
    this.online = new Map(); // uid -> Set(ws) (contas e convidados identificados)
    this.social = new Social({ send: (ws, o) => this.send(ws, o), backend: this });
    this.dm = new DirectMessages({ send: (ws, o) => this.send(ws, o), backend: this });
    this.invites = new Invites({ send: (ws, o) => this.send(ws, o), backend: this });
    this.presence = new Presence({ send: (ws, o) => this.send(ws, o), backend: this });
    this.sweeper = setInterval(() => this.sweepGuests(), 600e3); this.sweeper.unref && this.sweeper.unref();
  }
  attachRanked(ranked) { this.ranked = ranked; ranked.backend = this; }
  attachCasual(casual) { this.casual = casual; casual.backend = this; }
  games() { return [this.ranked, this.casual].filter(Boolean); }
  fail(ws, message, extra = {}) { this.send(ws, { type: 'acct_error', message, ...extra }); }
  // Usuário já está numa partida ativa ou fila de OUTRO serviço? (nunca duas partidas ao mesmo tempo)
  busyElsewhere(uid, service) {
    if (this.invites && this.invites.reserved(uid)) return true; // convite sendo aceito: partida prestes a começar
    for (const g of this.games()) if (g !== service && (g.activeMatchOf(uid) || g.mm.has(uid))) return true;
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
  inMatch(uid) { return this.games().some(g => !!g.activeMatchOf(uid)); }
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
  async state(ws) {
    const u = ws.user;
    const profile = await this.store.getProfile(u.id);
    const ranked = profile ? await this.store.getRankedStats(u.id) : null;
    ws.profile = profile;
    if (profile) { ws.guest = null; this.setIdentity(ws, { id: u.id, nickname: profile.nickname, avatar: profile.avatar_id, guest: false }); }
    // nickname_next_change_at: calculado pelo SERVIDOR (cooldown de 30 dias); o cliente só exibe.
    const pubProfile = profile ? { ...profile, nickname_next_change_at: nextNickChange(profile) } : null;
    this.send(ws, { type: 'acct_state', user_id: u.id, email: u.email, provider: u.provider, profile: pubProfile,
      needs_nickname: !profile, ranked, persistent: !!this.store.persistent, backend: this.kind });
  }
  // Convidado: identidade só em memória, recuperável pelo token (reconexão ao Casual).
  guestAuth(ws, m) {
    if (ws.user && ws.profile) return this.send(ws, { type: 'guest_state', account: true, nickname: ws.profile.nickname });
    const now = Date.now();
    if (ws.guestAuthAt && now - ws.guestAuthAt < 2000) return this.send(ws, { type: 'guest_error', message: 'Aguarde um instante.' });
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
    const a = String(m.type || '');
    try {
      if (a === 'guest_auth') return this.guestAuth(ws, m);
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
          console.error('invite', a, e && e.message);
          return this.send(ws, { type: 'invite_error', message: 'Erro temporário no servidor. Tente novamente.', code: 'server_error' });
        }
      }
      if (a.startsWith('dm_')) {
        if (!ws.user || !ws.profile) return this.send(ws, { type: 'dm_error', message: 'Entre ou crie uma conta para conversar com amigos.', code: 'auth_required' });
        try { return await this.dm.handle(ws, m); }
        catch (e) {
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
          if (e && /42P01|PGRST205|does not exist|Could not find the table/.test(String(e.code) + ' ' + String(e.message))) return this.send(ws, { type: 'social_error', message: 'Amigos ainda não configurado no servidor (migração 0002 pendente).', code: 'not_configured' });
          console.error('social', a, e && e.message);
          return this.send(ws, { type: 'social_error', message: 'Erro temporário no servidor. Tente novamente.', code: 'server_error' });
        }
      }
      if (a === 'acct_auth') {
        const user = await this.auth.verify(m.access_token);
        if (!user) { ws.user = null; ws.profile = null; return this.fail(ws, 'Sessão inválida ou expirada. Entre novamente.', { code: 'invalid_token' }); }
        if (ws.user && ws.user.id !== user.id) this.setIdentity(ws, null);
        ws.user = user;
        const existing = await this.store.getProfile(user.id);
        if (existing) await this.store.touchLogin(user.id);
        await this.state(ws);
        if (existing) for (const g of this.games()) g.onAuthenticated(ws);
        if (existing) this.invites.onAuthenticated(ws);
        if (existing) await this.presence.snapshot(ws);
        return;
      }
      if (!ws.user) return this.fail(ws, 'Entre na sua conta primeiro.', { code: 'auth_required' });
      if (a === 'acct_create_profile') {
        const v = validateNickname(m.nickname);
        if (v.error) return this.fail(ws, v.error, { code: 'nickname_invalid' });
        const r = await this.store.createProfile(ws.user.id, v.nickname, String(m.avatar_id || 'warrior'));
        if (r.error) return this.fail(ws, r.error, { code: r.code || 'profile_error' });
        await this.state(ws);
        return this.presence.snapshot(ws);
      }
      if (a === 'acct_refresh') return this.state(ws);
      // ---------- Nome público (0004) ----------
      if (a === 'acct_check_nickname') {
        const v = validateNickname(m.nickname);
        if (v.error) return this.send(ws, { type: 'acct_nickname_check', nickname: String(m.nickname || ''), available: false, error: v.error, code: 'nickname_invalid' });
        const free = await this.store.nicknameAvailable(v.nickname, ws.user.id);
        return this.send(ws, { type: 'acct_nickname_check', nickname: v.nickname, available: free, error: free ? '' : 'Esse nome já está sendo usado.', code: free ? '' : 'nickname_taken' });
      }
      if (a === 'acct_change_nickname') {
        if (!ws.profile) return this.fail(ws, 'Crie seu perfil primeiro.', { code: 'profile_missing' });
        const v = validateNickname(m.nickname);
        if (v.error) return this.fail(ws, v.error, { code: 'nickname_invalid' });
        const r = await this.store.changeNickname(ws.user.id, v.nickname);
        if (r.error) return this.fail(ws, r.error, { code: r.code || 'profile_error', next_change_at: r.next_change_at || null });
        await this.state(ws);                       // atualiza ws.profile e a identidade pública (chat, amigos…)
        this.presenceChanged(ws.user.id);
        return this.send(ws, { type: 'acct_nickname_changed', nickname: v.nickname, next_change_at: nextNickChange(r.profile) });
      }
      // ---------- Foto de perfil (0004): o cliente manda a imagem já recortada (512x512); o servidor revalida ----------
      if (a === 'acct_avatar_upload') {
        if (!ws.profile) return this.fail(ws, 'Crie seu perfil primeiro.', { code: 'profile_missing' });
        const v = validateAvatarUpload(m.data);
        if (v.error) return this.fail(ws, v.error, { code: 'avatar_invalid' });
        const r = await this.store.saveAvatar(ws.user.id, v.bytes, v.mime);
        if (r.error) return this.fail(ws, r.error, { code: r.code || 'avatar_error' });
        await this.state(ws);
        return this.send(ws, { type: 'acct_avatar_saved', avatar_url: r.profile.avatar_url || null });
      }
      if (a === 'acct_avatar_clear') {
        if (!ws.profile) return this.fail(ws, 'Crie seu perfil primeiro.', { code: 'profile_missing' });
        const r = await this.store.clearAvatar(ws.user.id);
        if (r.error) return this.fail(ws, r.error, { code: r.code || 'avatar_error' });
        await this.state(ws);
        return this.send(ws, { type: 'acct_avatar_saved', avatar_url: null });
      }
      if (a === 'acct_logout') {
        this.setIdentity(ws, null);
        ws.user = null; ws.profile = null; ws.guest = null;
        return this.send(ws, { type: 'acct_logged_out' });
      }
      return this.fail(ws, 'Ação de conta desconhecida.');
    } catch (e) {
      console.error('backend', a, e && e.message);
      return this.fail(ws, 'Erro temporário no servidor. Tente novamente.', { code: 'server_error' });
    }
  }
  onClose(ws) {
    for (const g of this.games()) g.onClose(ws);
    if (ws.identity) this.unlink(ws, ws.identity.id);
  }
}

module.exports = { Backend, createBackend };
