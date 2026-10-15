'use strict';
// R121 · APOIE UM CRIADOR (código de criador). Parceiros de divulgação cadastrados no FRAIHA Admin.
//   • o jogador digita o código (ou abre o link ?criador=CODIGO): passa a apoiar aquele criador por 30 dias
//     (digitar de novo renova; trocar de criador vale na hora);
//   • na PRIMEIRA vez que a conta apoia alguém, ganha um presente em Coroas (padrão 200, ajustável por criador);
//   • cada compra PAGA (Fundador / Club) feita enquanto apoia gera a comissão do criador (padrão 10% do valor
//     pago) — registrada em creator_sales; o dono paga por fora (PIX) e marca como paga no Admin;
//   • compra reembolsada: a comissão ainda não paga é cancelada sozinha.
//   creator_get → creator_state · creator_set { code } → creator_state | creator_error
const LINK_DAYS = 30;
const CODE_RE = /^[A-Z0-9]{3,20}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const missing = e => /42P01|42703|42883|PGRST200|PGRST202|PGRST204|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));
const clean = c => { const s = String(c || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, ''); return CODE_RE.test(s) ? s : ''; };

class Creators {
  constructor({ backend, send, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.backend = backend; this.send = send; this.now = now; this.log = log; this.offUntil = 0; this.tries = new Map();
  }
  get store() { return this.backend.store; }
  ok() { return !!(this.store && this.store.getCreator) && this.offUntil <= this.now(); }
  off(e, where) { if (missing(e)) { this.offUntil = this.now() + 600e3; return; } console.error('[criador] ' + where, e && e.message); }

  async state(uid) {
    const link = await this.store.getCreatorLink(uid);
    const active = link && Date.parse(link.expires_at) > this.now();
    const c = active ? await this.store.getCreator(link.code) : null;
    return { type: 'creator_state', available: true, link_days: LINK_DAYS,
      linked: c && c.active ? { code: c.code, name: c.name, expires_at: link.expires_at } : null };
  }

  async handle(ws, m) {
    const uid = ws.user && ws.profile ? ws.user.id : null;
    const t = String(m.type);
    if (!uid) return this.send(ws, { type: 'creator_state', available: false, message: 'Entre na sua conta para apoiar um criador.' });
    if (!this.ok()) return this.send(ws, { type: 'creator_state', available: false });
    try {
      if (t === 'creator_get') return this.send(ws, await this.state(uid));
      if (t !== 'creator_set') return;
      // limite: 10 tentativas por hora (evita "adivinhar" códigos)
      const now = this.now(), tr = (this.tries.get(uid) || []).filter(x => now - x < 3600e3);
      if (tr.length >= 10) return this.send(ws, { type: 'creator_error', code: 'rate_limited', message: 'Muitas tentativas. Tente de novo mais tarde.' });
      tr.push(now); this.tries.set(uid, tr);
      const r = await this.link(uid, m.code);
      if (r.error) return this.send(ws, { type: 'creator_error', code: r.error, message: r.message });
      this.send(ws, { ...(await this.state(uid)), just_linked: r.creator.name, gift: r.gift || 0 });
    } catch (e) { this.off(e, 'pedido'); this.send(ws, { type: 'creator_state', available: false }); }
  }

  // liga a conta ao criador (também usado pelo link ?criador= na criação da conta)
  async link(uid, raw) {
    const code = clean(raw);
    const c = code ? await this.store.getCreator(code) : null;
    if (!c || !c.active) return { error: 'not_found', message: 'Código de criador não encontrado. Confira com quem te passou.' };
    const expires = new Date(this.now() + LINK_DAYS * 86400e3).toISOString();
    await this.store.setCreatorLink(uid, c.code, expires);
    let gift = 0;
    if (c.gift_crowns > 0 && this.store.crownAward) {
      try {
        if (await this.store.crownAward(uid, c.gift_crowns, 'creator_gift', '') !== null) {
          gift = c.gift_crowns;
          if (this.backend.crowns) await this.backend.crowns.notify(uid, gift, [`Presente por apoiar ${c.name} +${gift}`]);
        }
      } catch (e) { if (!missing(e)) console.error('[criador] presente', e && e.message); }
    }
    this.log('[criador] ' + JSON.stringify({ user: uid, code: c.code, gift }));
    return { creator: c, gift };
  }
  async onProfileCreated(uid, raw) {
    if (!this.ok() || !clean(raw)) return null;
    try { return await this.link(uid, raw); } catch (e) { this.off(e, 'conta nova'); return null; }
  }

  // compra paga: comissão do criador que a conta apoia AGORA (link dentro dos 30 dias)
  async onPurchase({ ref, user_id, product_id, amount_cents }) {
    if (!this.ok() || !ref || !UUID.test(String(user_id || ''))) return null;
    try {
      const link = await this.store.getCreatorLink(user_id);
      if (!link || Date.parse(link.expires_at) <= this.now()) return null;
      const c = await this.store.getCreator(link.code);
      if (!c || !c.active || !c.pct) return null;
      const amount = Math.max(0, Number(amount_cents) || 0);
      const row = { payment_ref: String(ref), code: c.code, user_id, product_id: String(product_id || ''), amount_cents: amount,
        commission_cents: Math.round(amount * c.pct / 100) };
      const saved = await this.store.addCreatorSale(row);
      if (saved) this.log('[criador] venda ' + JSON.stringify(row));
      return saved;
    } catch (e) { this.off(e, 'venda'); return null; }
  }
  async onRefund(ref) {
    if (!this.ok() || !ref) return null;
    try { return await this.store.refundCreatorSale(String(ref)); } catch (e) { this.off(e, 'reembolso'); return null; }
  }
}

module.exports = { Creators, clean, CODE_RE, LINK_DAYS };
