'use strict';
// FRAIHA Admin · AUDIT LOG (server-side). Toda ação administrativa REAL passa por aqui ANTES de
// responder ao Admin: memória (últimos N) + linha estruturada no log do servidor ("[admin-audit] {json}").
// R110 · com a migração 0015 (tabela admin_audit) cada registro também vai para o banco e, ao subir, o servidor
// recarrega os últimos 500 — o Admin Log não some mais quando o servidor reinicia. Sem segredos/tokens no registro.
const crypto = require('crypto');

class AuditLog {
  constructor({ now = () => Date.now(), max = 2000, log = line => console.log(line), store = null } = {}) {
    this.now = now; this.max = max; this.log = log; this.items = [];
    this.store = store && store.insertAudit && store.listAudit ? store : null;
    this.saved = false;   // true depois que o banco respondeu (tabela existe)
    this.ready = this.store ? this.load() : Promise.resolve();
  }
  get persistent() { return this.saved; }
  async load() {
    try {
      const rows = await this.store.listAudit(500);
      const known = new Set(this.items.map(e => e.id));
      const old = rows.filter(r => !known.has(r.id)).reverse();
      this.items = old.concat(this.items);
      if (this.items.length > this.max) this.items.splice(0, this.items.length - this.max);
      this.saved = true;
    } catch (e) {
      if (!/42P01|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message))) console.error('[admin-audit] carregar', e && e.message);
      this.saved = false;
    }
  }
  record({ actor, action, target = null, before = null, after = null, result = 'ok', reason = '', meta = null }) {
    const entry = {
      id: crypto.randomUUID(), at: new Date(this.now()).toISOString(),
      actor: actor ? { id: String(actor.id || ''), name: String(actor.name || '') , role: String(actor.role || '') } : null,
      action: String(action), target, before, after, result: String(result), reason: String(reason || '').slice(0, 300), meta,
    };
    this.items.push(entry);
    if (this.items.length > this.max) this.items.splice(0, this.items.length - this.max);
    try { this.log('[admin-audit] ' + JSON.stringify(entry)); } catch { /* log nunca derruba a ação */ }
    if (this.store) this.store.insertAudit(entry).then(() => { this.saved = true; }).catch(e => {
      this.saved = false;
      if (!/42P01|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message))) console.error('[admin-audit] gravar', e && e.message);
    });
    return entry;
  }
  list({ limit = 100, action = '' } = {}) {
    const n = Math.max(1, Math.min(500, Number(limit) || 100));
    const src = action ? this.items.filter(e => e.action === action) : this.items;
    return src.slice(-n).reverse();
  }
}
module.exports = { AuditLog };
