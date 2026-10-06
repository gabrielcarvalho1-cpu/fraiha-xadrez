'use strict';
// FRAIHA Admin · QUEM é administrador e O QUE pode fazer. Decidido SÓ no servidor.
// V1: allowlist em variável de ambiente do servidor  FRAIHA_ADMIN_USERS="<uuid>=owner,<uuid>=viewer"
// (UUID da conta FRAIHA/Supabase; nada de e-mail no cliente). Sem a variável o Admin fica DESLIGADO.
// Papéis → permissões (RBAC simples, pronto para crescer; tabela admin_roles = migration proposta).
const ROLES = {
  // entitlements.write (Clube/Fundador): SÓ owner. operator/viewer não recebem (política mais segura).
  owner: ['dashboard.read', 'live.read', 'queues.read', 'queues.write', 'matches.read', 'players.read', 'audit.read', 'system.read', 'entitlements.write'],
  operator: ['dashboard.read', 'live.read', 'queues.read', 'queues.write', 'matches.read', 'players.read', 'audit.read', 'system.read'],
  viewer: ['dashboard.read', 'live.read', 'queues.read', 'matches.read', 'players.read', 'system.read'],
};
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function parseAdmins(raw) {
  const out = new Map();
  for (const part of String(raw || '').split(',').map(s => s.trim()).filter(Boolean)) {
    const [id, role = 'viewer'] = part.split('=').map(s => s.trim());
    if (UUID_RE.test(id) && ROLES[role]) out.set(id.toLowerCase(), role);
  }
  return out;
}

class AdminAccess {
  constructor({ backend, env = process.env }) {
    this.backend = backend;
    this.admins = parseAdmins(env.FRAIHA_ADMIN_USERS);
  }
  get enabled() { return this.admins.size > 0 && !!(this.backend && this.backend.auth); }
  // → { ok:true, admin } | { ok:false, status, code }
  async authenticate(req) {
    if (!this.enabled) return { ok: false, status: 503, code: 'admin_disabled' };
    const h = String(req.headers['authorization'] || '');
    const m = /^Bearer ([A-Za-z0-9._:\-]{8,4096})$/.exec(h);
    if (!m) return { ok: false, status: 401, code: 'auth_required' };
    const user = await this.backend.verifyToken(m[1]).catch(() => null);
    if (!user || !UUID_RE.test(String(user.id))) return { ok: false, status: 401, code: 'invalid_session' };
    const role = this.admins.get(String(user.id).toLowerCase());
    if (!role) return { ok: false, status: 403, code: 'not_admin' };
    let name = '';
    try { const p = this.backend.store && await this.backend.store.getProfile(user.id); name = p ? String(p.nickname || '') : ''; } catch { /* nome é só exibição */ }
    return { ok: true, admin: { id: user.id, name: name || 'admin', role, perms: ROLES[role].slice() } };
  }
  static can(admin, perm) { return !!(admin && admin.perms && admin.perms.includes(perm)); }
}
module.exports = { AdminAccess, ROLES, parseAdmins };
