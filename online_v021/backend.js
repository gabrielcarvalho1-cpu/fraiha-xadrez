'use strict';
// Camada adicional do servidor: contas (acct_*) e Ranked (ranked_*).
// Online Casual (salas por código) continua no server.js sem alterações.
const { SupabaseAuth, DevAuth } = require('./accounts/auth');
const { MemoryStore, SupabaseStore, validateNickname } = require('./accounts/store');

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
  }
  attachRanked(ranked) { this.ranked = ranked; ranked.backend = this; }
  fail(ws, message, extra = {}) { this.send(ws, { type: 'acct_error', message, ...extra }); }
  async state(ws) {
    const u = ws.user;
    const profile = await this.store.getProfile(u.id);
    const ranked = profile ? await this.store.getRankedStats(u.id) : null;
    ws.profile = profile;
    this.send(ws, { type: 'acct_state', user_id: u.id, email: u.email, provider: u.provider, profile,
      needs_nickname: !profile, ranked, persistent: !!this.store.persistent, backend: this.kind });
  }
  async handle(ws, m) {
    const a = String(m.type || '');
    try {
      if (a.startsWith('ranked_')) {
        if (!ws.user || !ws.profile) return this.fail(ws, 'Crie uma conta ou entre para jogar partidas ranqueadas.', { code: 'auth_required' });
        return this.ranked ? this.ranked.handle(ws, m) : this.fail(ws, 'Ranked indisponível.');
      }
      if (this.kind === 'disabled') return this.fail(ws, 'Contas ainda não configuradas no servidor.', { code: 'accounts_disabled' });
      if (a === 'acct_auth') {
        const user = await this.auth.verify(m.access_token);
        if (!user) { ws.user = null; ws.profile = null; return this.fail(ws, 'Sessão inválida ou expirada. Entre novamente.', { code: 'invalid_token' }); }
        if (ws.user && ws.user.id !== user.id && this.ranked) this.ranked.onClose(ws);
        ws.user = user;
        const existing = await this.store.getProfile(user.id);
        if (existing) await this.store.touchLogin(user.id);
        await this.state(ws);
        if (existing && this.ranked) this.ranked.onAuthenticated(ws);
        return;
      }
      if (!ws.user) return this.fail(ws, 'Entre na sua conta primeiro.', { code: 'auth_required' });
      if (a === 'acct_create_profile') {
        const v = validateNickname(m.nickname);
        if (v.error) return this.fail(ws, v.error, { code: 'nickname_invalid' });
        const r = await this.store.createProfile(ws.user.id, v.nickname, String(m.avatar_id || 'warrior'));
        if (r.error) return this.fail(ws, r.error, { code: r.code || 'profile_error' });
        return this.state(ws);
      }
      if (a === 'acct_refresh') return this.state(ws);
      if (a === 'acct_logout') {
        if (this.ranked) this.ranked.onClose(ws);
        ws.user = null; ws.profile = null;
        return this.send(ws, { type: 'acct_logged_out' });
      }
      return this.fail(ws, 'Ação de conta desconhecida.');
    } catch (e) {
      console.error('backend', a, e && e.message);
      return this.fail(ws, 'Erro temporário no servidor. Tente novamente.', { code: 'server_error' });
    }
  }
  onClose(ws) { if (this.ranked) this.ranked.onClose(ws); }
}

module.exports = { Backend, createBackend };
