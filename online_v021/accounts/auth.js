'use strict';
// Identidade: o servidor NUNCA confia no cliente. Todo token é validado no
// Supabase Auth (GET /auth/v1/user). Nenhuma senha passa pelo Node.
const crypto = require('crypto');

class SupabaseAuth {
  constructor({ url, apiKey, fetchImpl = fetch, cacheMs = 60e3 }) {
    this.url = url.replace(/\/+$/, ''); this.apiKey = apiKey; this.fetch = fetchImpl; this.cacheMs = cacheMs;
    this.cache = new Map();
  }
  async verify(accessToken) {
    const token = String(accessToken || '');
    if (token.length < 20 || token.length > 4096) return null;
    const hit = this.cache.get(token);
    if (hit && hit.until > Date.now()) return hit.user;
    let res;
    try {
      res = await this.fetch(this.url + '/auth/v1/user', { headers: { apikey: this.apiKey, Authorization: 'Bearer ' + token } });
    } catch { return null; }
    if (!res.ok) return null;
    const u = await res.json().catch(() => null);
    if (!u || typeof u.id !== 'string') return null;
    const user = { id: u.id, email: u.email || '', provider: (u.app_metadata && u.app_metadata.provider) || 'email' };
    if (this.cache.size > 2000) this.cache.clear();
    this.cache.set(token, { user, until: Date.now() + this.cacheMs });
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
