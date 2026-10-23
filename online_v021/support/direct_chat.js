'use strict';
// R177 · CHAT EXCLUSIVO (canal direto com o administrador). O dono escolhe um jogador ONLINE no Admin e abre um chat:
// a janela "CHAT EXCLUSIVO" aparece na tela do jogador na hora; o dono escreve pelo Admin e o jogador responde no jogo.
// Pelo mesmo chat o dono manda PRESENTES: Coroas (extrato 'admin') ou um item da Loja de Coroas (moldura, título,
// avatar, emote — fica com o jogador para sempre, como se tivesse comprado, sem descontar Coroas).
// Sem banco novo: a conversa fica na memória do servidor (some quando ele reinicia) e cada mensagem vai para o log.
//
// Jogo → servidor:   dchat_send { text } · dchat_hide (fechou a janela; o chat continua aberto no Admin)
// Servidor → jogo:   dchat_open { chat } · dchat_msg { msg } · dchat_closed { } · dchat_error { code, message }
const { ITEMS, BY_ID } = require('../economy/store_catalog');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_MSGS = 200, MAX_TEXT = 1000, MAX_CHATS = 500;
const clean = (s, n) => String(s === undefined || s === null ? '' : s).replace(/\r\n/g, '\n').replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, '').trim().slice(0, n);
const KIND_LABEL = { avatar: 'Avatar', frame: 'Moldura', title: 'Título', emote: 'Emote', badge: 'Selo' };

class DirectChat {
  constructor({ backend, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.backend = backend; this.now = now; this.log = log;
    this.chats = new Map();   // uid -> chat
    this.seq = 0;
    this.rate = new Map();    // uid -> [ts] (jogador: 20 mensagens por minuto)
  }
  get store() { return this.backend.store; }
  send(ws, m) { this.backend.send(ws, m); }
  sockets(uid) { return this.backend.socketsOf ? this.backend.socketsOf(uid) : []; }
  online(uid) { return this.sockets(uid).some(ws => ws.identity && ws.identity.id === uid); }
  push(uid, m) { for (const ws of this.sockets(uid)) if (ws.identity && ws.identity.id === uid) this.send(ws, m); }

  // o que o jogo recebe (sem ids de admin)
  view(c) { return { open: c.open, admin_name: c.admin_name, messages: c.msgs.map(x => this.msgView(x)) }; }
  msgView(x) { return { id: x.id, from: x.from, text: x.text, ts: x.ts, gift: x.gift || null, emote: x.emote || '' }; }
  // o que o Admin recebe
  adminView(c) {
    return { user_id: c.uid, nickname: c.nickname, open: c.open, hidden: c.hidden, online: this.online(c.uid), opened_at: c.opened_at,
      last_at: c.last_at, unread: c.unread, messages: c.msgs.map(x => ({ ...this.msgView(x), by: x.by || '' })) };
  }

  _nick(uid) {
    for (const ws of this.sockets(uid)) if (ws.identity && ws.identity.id === uid) return String(ws.identity.nickname || '');
    return '';
  }
  _add(c, from, text, extra = {}) {
    const msg = { id: ++this.seq, from, text, ts: new Date(this.now()).toISOString(), ...extra };
    c.msgs.push(msg);
    if (c.msgs.length > MAX_MSGS) c.msgs.splice(0, c.msgs.length - MAX_MSGS);
    c.last_at = msg.ts;
    this.log('[chat-exclusivo] ' + JSON.stringify({ user: c.uid, from, text: text.slice(0, 200), gift: extra.gift || undefined }));
    return msg;
  }

  // ---------- Admin ----------
  adminList() {
    const items = [...this.chats.values()].sort((a, b) => String(b.last_at).localeCompare(String(a.last_at)))
      .map(c => ({ user_id: c.uid, nickname: c.nickname, open: c.open, hidden: c.hidden, online: this.online(c.uid), last_at: c.last_at, unread: c.unread,
        last: c.msgs.length ? c.msgs[c.msgs.length - 1].text.slice(0, 80) : '' }));
    return { available: true, items, catalog: ITEMS.map(i => ({ id: i.id, kind: i.kind, kind_label: KIND_LABEL[i.kind] || i.kind, name: i.name, price: i.price })) };
  }
  adminGet(uid) {
    const c = this.chats.get(uid);
    if (!c) return { status: 200, body: { chat: null, online: this.online(uid), nickname: this._nick(uid) } };
    c.unread = 0;
    return { status: 200, body: { chat: this.adminView(c) } };
  }
  adminOpen(admin, uid) {
    if (!UUID.test(uid)) return { status: 400, body: { error: 'invalid_user' } };
    if (!this.online(uid)) return { status: 409, body: { error: 'offline' } };
    let c = this.chats.get(uid);
    if (!c) {
      if (this.chats.size >= MAX_CHATS) {   // descarta o chat fechado mais antigo
        const old = [...this.chats.values()].filter(x => !x.open).sort((a, b) => String(a.last_at).localeCompare(String(b.last_at)))[0];
        if (old) this.chats.delete(old.uid); else return { status: 429, body: { error: 'too_many_chats' } };
      }
      c = { uid, nickname: this._nick(uid), open: true, hidden: false, admin_name: 'Fraiha', opened_at: new Date(this.now()).toISOString(), last_at: new Date(this.now()).toISOString(), unread: 0, msgs: [] };
      this.chats.set(uid, c);
    }
    c.open = true; c.hidden = false;
    c.nickname = this._nick(uid) || c.nickname;
    this.push(uid, { type: 'dchat_open', chat: this.view(c) });
    return { status: 200, body: { chat: this.adminView(c) } };
  }
  adminSend(admin, uid, body) {
    const c = this.chats.get(uid);
    if (!c || !c.open) return { status: 409, body: { error: 'not_open' } };
    const text = clean(body && body.text, MAX_TEXT);
    if (!text) return { status: 400, body: { error: 'empty' } };
    const msg = this._add(c, 'admin', text, { by: String(admin && (admin.name || admin.id) || 'admin').slice(0, 60) });
    if (c.hidden) { c.hidden = false; this.push(uid, { type: 'dchat_open', chat: this.view(c) }); }   // mensagem nova reabre a janela
    else this.push(uid, { type: 'dchat_msg', msg: this.msgView(msg) });
    return { status: 200, body: { msg: this.msgView(msg), online: this.online(uid) } };
  }
  async adminGift(admin, uid, body) {
    const c = this.chats.get(uid);
    if (!c || !c.open) return { status: 409, body: { error: 'not_open' } };
    const st = this.store;
    const note = clean(body && body.text, 300);
    let gift;
    if (body && body.kind === 'crowns') {
      const amount = Number(body.amount);
      if (!Number.isInteger(amount) || amount < 1 || amount > 100000) return { status: 400, body: { error: 'invalid_amount' } };
      if (!st || !st.crownAward) return { status: 503, body: { error: 'unavailable' } };
      const ref = 'chat:' + this.now() + ':' + Math.random().toString(36).slice(2, 8);
      try { await st.crownAward(uid, amount, 'admin', ref); }
      catch (e) { return { status: 503, body: { error: /42P01|PGRST20|does not exist/.test(String(e && e.code) + ' ' + String(e && e.message)) ? 'migration_0016_missing' : 'crowns_error' } }; }
      gift = { kind: 'crowns', amount, name: amount + ' Coroas' };
    } else if (body && body.kind === 'item') {
      const item = BY_ID[String(body.item || '')];
      if (!item) return { status: 400, body: { error: 'unknown_item' } };
      if (!st || !st.crownBuy) return { status: 503, body: { error: 'unavailable' } };
      let r;
      try { r = await st.crownBuy(uid, item.id, 0); }
      catch (e) { return { status: 503, body: { error: /42P01|PGRST20|does not exist/.test(String(e && e.code) + ' ' + String(e && e.message)) ? 'migration_0017_missing' : 'store_error' } }; }
      if (r === 'ja_tem') return { status: 409, body: { error: 'already_owned' } };
      if (r !== 'ok') return { status: 503, body: { error: 'store_error' } };
      gift = { kind: 'item', item: item.id, item_kind: item.kind, name: item.name, kind_label: KIND_LABEL[item.kind] || 'Item' };
    } else return { status: 400, body: { error: 'invalid_gift' } };
    const text = note || (gift.kind === 'crowns' ? `Um presente para você: ${gift.amount} Coroas!` : `Um presente para você: ${gift.kind_label} ${gift.name}!`);
    const msg = this._add(c, 'admin', text, { gift, by: String(admin && (admin.name || admin.id) || 'admin').slice(0, 60) });
    if (c.hidden) { c.hidden = false; this.push(uid, { type: 'dchat_open', chat: this.view(c) }); }
    else this.push(uid, { type: 'dchat_msg', msg: this.msgView(msg) });
    // saldo e itens novos na hora
    for (const ws of this.sockets(uid)) {
      if (this.backend.crowns) this.backend.crowns.sendState(ws, uid).catch(() => {});
      if (gift.kind === 'item' && this.backend.crownStore) this.backend.crownStore.sendState(ws, uid).catch(() => {});
    }
    return { status: 200, body: { msg: this.msgView(msg), gift } };
  }
  adminClose(admin, uid) {
    const c = this.chats.get(uid);
    if (!c) return { status: 404, body: { error: 'not_found' } };
    c.open = false;
    this.push(uid, { type: 'dchat_closed' });
    return { status: 200, body: { chat: this.adminView(c) } };
  }

  // ---------- jogo ----------
  handle(ws, m) {
    const a = String(m.type || '');
    const uid = ws.identity && ws.identity.id;
    const c = uid ? this.chats.get(uid) : null;
    if (!c || !c.open) return this.send(ws, { type: 'dchat_error', code: 'not_open', message: 'O chat exclusivo foi encerrado.' });
    if (a === 'dchat_hide') { c.hidden = true; return; }
    if (a === 'dchat_get') { c.hidden = false; return this.send(ws, { type: 'dchat_open', chat: this.view(c) }); }
    if (a !== 'dchat_send') return;
    const emote = /^[a-z0-9_]{1,40}$/.test(String(m.emote || '')) ? String(m.emote) : '';
    const text = clean(m.text, emote ? 60 : MAX_TEXT);
    if (!text && !emote) return;
    const t = this.now(), list = (this.rate.get(uid) || []).filter(x => t - x < 60e3);
    if (list.length >= 20) return this.send(ws, { type: 'dchat_error', code: 'rate_limited', message: 'Calma! Espere um pouquinho antes de mandar outra mensagem.' });
    list.push(t); this.rate.set(uid, list);
    const msg = this._add(c, 'player', text || emote, emote ? { emote } : {});
    c.unread++;
    this.push(uid, { type: 'dchat_msg', msg: this.msgView(msg) });   // todas as abas do jogador
  }
  // reconexão: o chat aberto volta para a tela
  onAuthenticated(ws) {
    const uid = ws.identity && ws.identity.id;
    const c = uid ? this.chats.get(uid) : null;
    if (c && c.open && !c.hidden) this.send(ws, { type: 'dchat_open', chat: this.view(c) });
  }
}

module.exports = { DirectChat };
