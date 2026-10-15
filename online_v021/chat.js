'use strict';
// Chat da partida (Casual e Ranked). Efêmero: vive só enquanto a partida existe no servidor.
// Nunca altera relógio, PL, resultado ou estado da partida.
const MAX_LEN = 200;            // caracteres visíveis por mensagem
const MAX_RAW = 1000;           // payload bruto acima disso é rejeitado sem processar
const HISTORY = 60;             // mensagens guardadas por partida (para reconexão)
const MIN_INTERVAL_MS = 700;    // no máximo ~1 mensagem a cada 0,7 s
const BURST = 5;                // e no máximo 5 mensagens…
const BURST_WINDOW_MS = 10000;  // …a cada 10 s
const DUP_WINDOW_MS = 30000;    // mesma mensagem repetida em 30 s = spam
const EMOTE_GAP_MS = 2500;      // R119 · emotes: no máximo 1 a cada 2,5 s…
const EMOTE_MAX = 12;           // …e 12 por partida
const Shop = require('./economy/store_catalog');
// Controles, bidi e caracteres invisíveis que poderiam esconder texto.
const STRIP = /[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u2064\u2066-\u206f\ufeff\ufff9-\ufffb]/g;

function clean(raw) {
  if (typeof raw !== 'string') return { error: 'Mensagem inválida.', code: 'invalid' };
  if (raw.length > MAX_RAW) return { error: `Mensagem longa demais (máx. ${MAX_LEN} caracteres).`, code: 'too_long' };
  const text = raw.replace(STRIP, ' ').replace(/\s+/g, ' ').trim();
  if (!text) return { error: 'Mensagem vazia.', code: 'empty' };
  if ([...text].length > MAX_LEN) return { error: `Mensagem longa demais (máx. ${MAX_LEN} caracteres).`, code: 'too_long' };
  return { text };
}

class ChatHub {
  constructor({ send, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.send = send; this.now = now; this.log = log;
    this.rate = new Map(); // uid -> { last, times: [], lastText, lastTextAt }
  }
  allow(uid, text, now) {
    const r = this.rate.get(uid) || { last: 0, times: [], lastText: '', lastTextAt: 0 };
    this.rate.set(uid, r);
    if (now - r.last < MIN_INTERVAL_MS) return { error: 'Calma! Espere um instante para mandar outra mensagem.', code: 'rate_limited' };
    r.times = r.times.filter(t => now - t < BURST_WINDOW_MS);
    if (r.times.length >= BURST) return { error: 'Muitas mensagens seguidas. Aguarde alguns segundos.', code: 'rate_limited' };
    if (text.toLowerCase() === r.lastText && now - r.lastTextAt < DUP_WINDOW_MS) return { error: 'Mensagem repetida.', code: 'spam' };
    r.last = now; r.times.push(now); r.lastText = text.toLowerCase(); r.lastTextAt = now;
    return { ok: true };
  }
  // R119 · emote: de graça ou comprado na Loja de Coroas (ownedEmotes vem do backend). Vai pelo mesmo canal do chat
  // (chat_msg com `emote`), então o SILENCIAR do adversário esconde também os emotes.
  async emote(ws, uid, m, entryBase, sendTo) {
    const fail = (message, code) => this.send(ws, { type: m.type === 'party_emote' ? 'party_chat_error' : 'chat_error', message, code, room_id: m.room_id });
    const id = String(m.id || '');
    const text = Shop.emoteText(id);
    if (!text) return fail('Emote desconhecido.', 'invalid');
    if (!Shop.isFreeEmote(id)) {
      const owned = this.ownedEmotes ? await this.ownedEmotes(uid).catch(() => []) : [];
      if (!owned.includes(id)) return fail('Compre este emote na Loja de Coroas.', 'emote_locked');
    }
    const now = this.now();
    const r = this.rate.get('emote:' + uid) || { last: 0, count: new Map() };
    this.rate.set('emote:' + uid, r);
    if (now - r.last < EMOTE_GAP_MS) return fail('Calma! Um emote de cada vez.', 'rate_limited');
    const key = entryBase.scope;
    if ((r.count.get(key) || 0) >= EMOTE_MAX) return fail('Limite de emotes desta partida.', 'rate_limited');
    r.last = now; r.count.set(key, (r.count.get(key) || 0) + 1);
    if (r.count.size > 20) r.count.delete(r.count.keys().next().value);
    return sendTo({ ...entryBase.entry, text, emote: id, ts: new Date(now).toISOString() });
  }
  history(match) { return { type: 'chat_history', match_id: match.id, messages: match.chat || [] }; }
  // service: MatchService dono da partida; entrega para os dois jogadores conectados.
  broadcast(service, match, msg) {
    for (const c of ['w', 'b']) {
      const p = match.players[c], ws = service.sockets.get(p.userId);
      if (ws && p.connected) this.send(ws, msg);
    }
  }
  handle(ws, m, uid, match, service) {
    const a = String(m.type || '');
    const fail = (message, code) => this.send(ws, { type: 'chat_error', message, code });
    if (!match || (m.match_id !== undefined && String(m.match_id) !== match.id)) return fail('Nenhuma partida ativa para conversar.', 'no_match');
    const color = match.colorOf(uid);
    if (!color) return fail('Você não está nesta partida.', 'no_match');
    if (a === 'chat_sync') return this.send(ws, this.history(match));
    if (a === 'chat_send') {
      const c = clean(m.text);
      if (c.error) return fail(c.error, c.code);
      const now = this.now(), ok = this.allow(uid, c.text, now);
      if (ok.error) return fail(ok.error, ok.code);
      match.chat = match.chat || []; match.chatSeq = (match.chatSeq || 0) + 1;
      const entry = { id: match.chatSeq, from_color: color, nickname: match.players[color].nickname, text: c.text, ts: new Date(now).toISOString() };
      match.chat.push(entry); if (match.chat.length > HISTORY) match.chat.shift();
      return this.broadcast(service, match, { type: 'chat_msg', match_id: match.id, ...entry });
    }
    if (a === 'chat_emote') {
      return this.emote(ws, uid, m, { scope: match.id, entry: { from_color: color, nickname: match.players[color].nickname } }, entry => {
        match.chat = match.chat || []; match.chatSeq = (match.chatSeq || 0) + 1;
        const e = { id: match.chatSeq, ...entry };
        match.chat.push(e); if (match.chat.length > HISTORY) match.chat.shift();
        this.broadcast(service, match, { type: 'chat_msg', match_id: match.id, ...e });
      });
    }
    if (a === 'chat_report') {
      // V1: registro no log do servidor (Render). Tabela de denúncias fica para uma fase futura.
      match.reports = match.reports || new Set();
      if (match.reports.has(uid)) return this.send(ws, { type: 'chat_report_ok', match_id: match.id, duplicate: true });
      match.reports.add(uid);
      const other = color === 'w' ? 'b' : 'w';
      const msgs = (match.chat || []).filter(e => e.from_color === other).slice(-20).map(e => e.text);
      // R104 · vai para a fila de denúncias do Admin (tabela reports); vale para o chat E a voz da partida
      const row = { reporter: uid, reported: match.players[other].userId, kind: 'match', ref: match.id,
        context: { reporter_nickname: match.players[color].nickname, reported_nickname: match.players[other].nickname, mode: service.kind, messages: msgs } };
      if (!this.reports) {
        this.log('chat_report ' + JSON.stringify({ match_id: match.id, kind: service.kind, reporter: uid, reported: row.reported, reported_nickname: row.context.reported_nickname, messages: msgs, at: new Date(this.now()).toISOString() }));
        return this.send(ws, { type: 'chat_report_ok', match_id: match.id });
      }
      return this.reports.file(row).then(() => this.send(ws, { type: 'chat_report_ok', match_id: match.id }))
        .catch(e => { console.error('chat_report', e && e.message); this.send(ws, { type: 'chat_report_ok', match_id: match.id }); });
    }
    return fail('Ação de chat desconhecida.', 'invalid');
  }
}
module.exports = { ChatHub, clean, MAX_LEN, STRIP };
