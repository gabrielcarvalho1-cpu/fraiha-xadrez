'use strict';
// Identidade: o servidor NUNCA confia no cliente. Todo token é validado no
// Supabase Auth (GET /auth/v1/user). Nenhuma senha passa pelo Node.
const crypto = require('crypto');

class SupabaseAuth {
  constructor({ url, apiKey, fetchImpl = fetch, cacheMs = 60e3, now = () => Date.now() }) {
    this.url = url.replace(/\/+$/, ''); this.apiKey = apiKey; this.fetch = fetchImpl; this.cacheMs = cacheMs;
    this.cache = new Map();
    this.now = now;
  }
  async verify(accessToken, { force = false } = {}) {
    const token = String(accessToken || '');
    if (token.length < 20 || token.length > 4096) return null;
    const hit = this.cache.get(token);
    if (!force && hit && hit.until > this.now()) return hit.user;
    this.cache.delete(token);
    // exp só limita validade; a identidade continua vindo exclusivamente de Auth.
    let expiresAt = null;
    try {
      const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
      if (Number.isFinite(payload.exp)) expiresAt = payload.exp * 1000;
    } catch { /* tokens opacos: backend aplica duração máxima e revalidação */ }
    if (expiresAt !== null && expiresAt <= this.now()) return null;
    let res;
    try {
      res = await this.fetch(this.url + '/auth/v1/user', { headers: { apikey: this.apiKey, Authorization: 'Bearer ' + token } });
    } catch { return null; }
    if (!res.ok) return null;
    const u = await res.json().catch(() => null);
    if (!u || typeof u.id !== 'string') return null;
    if (expiresAt !== null && expiresAt <= this.now()) return null;
    const user = { id: u.id, email: u.email || '', provider: (u.app_metadata && u.app_metadata.provider) || 'email' };
    if (expiresAt !== null) user.expires_at = expiresAt;
    if (this.cache.size > 2000) this.cache.clear();
    this.cache.set(token, { user, until: Math.min(this.now() + this.cacheMs, expiresAt === null ? Infinity : expiresAt) });
    return user;
  }
}

// SOMENTE desenvolvimento/testes (FRAIHA_DEV_AUTH=1). Token "dev:<nome>" vira
// um UUID determinístico. Nunca habilitar em produção.
class DevAuth {
  async verify(accessToken) {
    const t = String(accessToken || '');
    if (!/^dev:[A-Za-z0-9_.-]{1,32}$/.test(t)) return null;
    const h = crypto.createHash('sha256').update(t).digest('hex');
    const id = `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`;
    return { id, email: t.slice(4) + '@dev.local', provider: 'dev' };
  }
}

module.exports = { SupabaseAuth, DevAuth };
