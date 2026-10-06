'use strict';
// FRAIHA Admin · AUDIT LOG (server-side). Toda ação administrativa REAL passa por aqui ANTES de
// responder ao Admin. V1: memória (últimos N) + linha estruturada no log do servidor ("[admin-audit] {json}"),
// que fica no histórico de logs do Render. Persistência em banco = migration proposta
// (docs/admin/proposals/0011_admin_audit_and_roles.sql) — NÃO aplicada. Sem segredos/tokens no registro.
const crypto = require('crypto');

class AuditLog {
  constructor({ now = () => Date.now(), max = 2000, log = line => console.log(line) } = {}) {
    this.now = now; this.max = max; this.log = log; this.items = [];
  }
  get persistent() { return false; }
  record({ actor, action, target = null, before = null, after = null, result = 'ok', reason = '', meta = null }) {
    const entry = {
      id: crypto.randomUUID(), at: new Date(this.now()).toISOString(),
      actor: actor ? { id: String(actor.id || ''), name: String(actor.name || '') , role: String(actor.role || '') } : null,
      action: String(action), target, before, after, result: String(result), reason: String(reason || '').slice(0, 300), meta,
    };
    this.items.push(entry);
    if (this.items.length > this.max) this.items.splice(0, this.items.length - this.max);
    try { this.log('[admin-audit] ' + JSON.stringify(entry)); } catch { /* log nunca derruba a ação */ }
    return entry;
  }
  list({ limit = 100, action = '' } = {}) {
    const n = Math.max(1, Math.min(500, Number(limit) || 100));
    const src = action ? this.items.filter(e => e.action === action) : this.items;
    return src.slice(-n).reverse();
  }
}
module.exports = { AuditLog };
