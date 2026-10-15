'use strict';
// R116 · LOJA DE COROAS. O servidor decide: preço (store_catalog.js), saldo e posse (0017, numa transação).
//   store_get           → store_state { available, balance, owned[], items[] }
//   store_buy { item }  → store_bought { item, balance } | store_error { code, message }
// Comprar não equipa: o jogador escolhe usar (acct_set_cosmetics) — a loja oferece o botão USAR.
const { ITEMS, BY_ID } = require('./store_catalog');

const missing = e => /42P01|42703|42883|PGRST200|PGRST202|PGRST204|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));
const MSG = {
  saldo_insuficiente: 'Coroas insuficientes para este item.',
  ja_tem: 'Você já tem este item.',
  item_desconhecido: 'Item não encontrado na loja.',
  indisponivel: 'A Loja de Coroas ainda não está ligada neste servidor.',
  auth_required: 'Entre na sua conta para usar a Loja de Coroas.',
  rate_limited: 'Aguarde um instante.',
};

class Store {
  constructor({ backend, send }) { this.backend = backend; this.send = send; this.busy = new Set(); }
  get store() { return this.backend.store; }
  ok() { return !!(this.store && this.store.crownBuy && this.store.crownItems); }

  async owned(uid) {
    if (!this.ok() || !uid) return [];
    try { return await this.store.crownItems(uid); } catch (e) { if (!missing(e)) console.error('[loja] itens', e && e.message); return []; }
  }

  async handle(ws, m) {
    const uid = ws.user && ws.user.id;
    const t = String(m.type);
    const fail = code => this.send(ws, { type: 'store_error', code, message: MSG[code] || 'Não foi possível concluir.', item: String(m.item || '') });
    if (!uid || !ws.profile) return fail('auth_required');
    if (t === 'store_get') return this.sendState(ws, uid);
    if (t !== 'store_buy') return;
    const item = BY_ID[String(m.item || '')];
    if (!item) return fail('item_desconhecido');
    if (!this.ok()) return fail('indisponivel');
    if (this.busy.has(uid)) return fail('rate_limited');
    this.busy.add(uid);
    try {
      const r = await this.store.crownBuy(uid, item.id, item.price);
      if (r !== 'ok') return fail(r === 'ja_tem' || r === 'saldo_insuficiente' ? r : 'indisponivel');
      console.log('[loja] ' + JSON.stringify({ user: uid, item: item.id, price: item.price }));
      const w = await this.store.crownWallet(uid).catch(() => null);
      this.send(ws, { type: 'store_bought', item: item.id, kind: item.kind, name: item.name, price: item.price, balance: w ? w.balance : undefined });
      await this.sendState(ws, uid);
      if (this.backend.crowns) await this.backend.crowns.sendState(ws, uid);
    } catch (e) {
      if (!missing(e)) console.error('[loja] compra', e && e.message);
      fail('indisponivel');
    } finally { this.busy.delete(uid); }
  }

  async sendState(ws, uid) {
    if (!this.ok()) return this.send(ws, { type: 'store_state', available: false, items: ITEMS, owned: [] });
    try {
      const [owned, w] = await Promise.all([this.store.crownItems(uid), this.store.crownWallet(uid)]);
      this.send(ws, { type: 'store_state', available: true, items: ITEMS, owned, balance: w ? w.balance : 0 });
    } catch (e) {
      if (!missing(e)) console.error('[loja] estado', e && e.message);
      this.send(ws, { type: 'store_state', available: false, items: ITEMS, owned: [] });
    }
  }
}

module.exports = { Store, MSG };
