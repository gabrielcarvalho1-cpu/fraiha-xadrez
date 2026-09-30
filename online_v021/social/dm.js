'use strict';
// Mensagens privadas (DM) persistentes entre AMIGOS. O servidor é a autoridade:
// valida amizade, bloqueio (nos dois sentidos), tamanho e conteúdo; o cliente só pede.
// Mensagens: dm_open, dm_send, dm_read (cliente) -> dm_history, dm_msg, dm_unread, dm_read_ok, dm_error.
const { STRIP } = require('../chat');
const { UUID_RE } = require('../accounts/store');

const MAX_LEN = 500;            // caracteres visíveis
const MAX_RAW = 2000;           // payload bruto acima disso é rejeitado sem processar
const HISTORY = 50;             // mensagens por carga (a mais recente primeiro no banco; enviadas em ordem crescente)
const MIN_INTERVAL_MS = 400;
const BURST = Number(process.env.FRAIHA_TEST_DM_BURST || 10), BURST_WINDOW_MS = 10000; // env só para testes

function cleanBody(raw) {
  if (typeof raw !== 'string') return { error: 'Mensagem inválida.', code: 'invalid' };
  if (raw.length > MAX_RAW) return { error: `Mensagem longa demais (máx. ${MAX_LEN} caracteres).`, code: 'too_long' };
  const text = raw.replace(STRIP, ' ').replace(/\s+/g, ' ').trim();
  if (!text) return { error: 'Mensagem vazia.', code: 'empty' };
  if ([...text].length > MAX_LEN || text.length > MAX_LEN) return { error: `Mensagem longa demais (máx. ${MAX_LEN} caracteres).`, code: 'too_long' };
  return { text };
}

class DirectMessages {
  constructor({ send, backend, now = () => Date.now() }) {
    this.send = send; this.backend = backend; this.now = now;
    this.rate = new Map(); // uid -> { last, times }
  }
  store() { return this.backend.store; }
  fail(ws, message, code, user_id = '') { this.send(ws, { type: 'dm_error', message, code, user_id }); }
  sockets(uid) { return this.backend.socketsOf ? this.backend.socketsOf(uid) : []; }
  async unreadCounts(uid) { return this.store().unreadCounts(uid); }
  async pushUnread(uid) {
    const socks = this.sockets(uid);
    if (!socks.length) return;
    const counts = await this.store().unreadCounts(uid);
    for (const ws of socks) this.send(ws, { type: 'dm_unread', counts });
  }
  allow(uid) {
    const now = this.now(), r = this.rate.get(uid) || { last: 0, times: [] };
    this.rate.set(uid, r);
    if (now - r.last < MIN_INTERVAL_MS) return false;
    r.times = r.times.filter(t => now - t < BURST_WINDOW_MS);
    if (r.times.length >= BURST) return false;
    r.last = now; r.times.push(now);
    return true;
  }
  // Abrir/ler conversas: até 40 a cada 10 s por conta (protege o banco).
  busy(uid) {
    const now = this.now(), k = 'r:' + uid, t = (this.rate.get(k) || []).filter(x => now - x < 10000);
    t.push(now); this.rate.set(k, t);
    return t.length > 40;
  }
  // Pode enviar agora? Amizade válida e nenhum bloqueio em qualquer sentido.
  static sendable(rel, other) {
    if (rel.blocked.includes(other)) return { ok: false, code: 'blocked', message: 'Você bloqueou este jogador. Desbloqueie para conversar.' };
    if (rel.blockedBy.includes(other)) return { ok: false, code: 'unavailable', message: 'Não é possível enviar mensagens para este jogador.' };
    if (!rel.friends.includes(other)) return { ok: false, code: 'not_friends', message: 'Só é possível conversar com amigos.' };
    return { ok: true };
  }
  async handle(ws, m) {
    const a = String(m.type || ''), me = ws.user.id, st = this.store();
    if (a !== 'dm_send' && this.busy(me)) return this.fail(ws, 'Muitas ações seguidas. Aguarde alguns segundos.', 'rate_limited', String(m.user_id || ''));
    const other = String(m.user_id || '');
    if (!UUID_RE.test(other)) return this.fail(ws, 'Jogador inválido.', 'bad_user');
    if (other === me) return this.fail(ws, 'Você não pode mandar mensagem para si mesmo.', 'self', other);
    const [peer] = await st.getProfilesByIds([other]);
    if (!peer) return this.fail(ws, 'Jogador não encontrado.', 'not_found', other);
    const rel = await st.getRelations(me);
    const can = DirectMessages.sendable(rel, other);
    if (a === 'dm_open') {
      // Histórico continua visível mesmo sem amizade/bloqueado (só as mensagens da própria conversa).
      const before = Math.max(0, Number(m.before_id) || 0);
      const rows = await st.getConversation(me, other, HISTORY + 1, before);
      const has_more = rows.length > HISTORY;
      const messages = has_more ? rows.slice(1) : rows;
      return this.send(ws, { type: 'dm_history', user_id: other, peer: { user_id: peer.user_id, nickname: peer.nickname, avatar_id: peer.avatar_id },
        messages, has_more, before_id: before, can_send: can.ok, reason: can.ok ? '' : can.message, reason_code: can.ok ? '' : can.code });
    }
    if (a === 'dm_send') {
      if (!can.ok) return this.fail(ws, can.message, can.code, other);
      const c = cleanBody(m.text);
      if (c.error) return this.fail(ws, c.error, c.code, other);
      if (!this.allow(me)) return this.fail(ws, 'Calma! Espere um instante para mandar outra mensagem.', 'rate_limited', other);
      const row = await st.addDirectMessage(me, other, c.text);
      const out = { type: 'dm_msg', message: row, client_ref: String(m.client_ref || '').slice(0, 40) };
      for (const s of this.sockets(me)) this.send(s, { ...out, user_id: other });
      const from = { user_id: me, nickname: ws.profile.nickname, avatar_id: ws.profile.avatar_id };
      for (const s of this.sockets(other)) this.send(s, { type: 'dm_msg', message: row, user_id: me, from });
      await this.pushUnread(other);
      return;
    }
    if (a === 'dm_read') {
      const n = await st.markDirectRead(me, other);
      this.send(ws, { type: 'dm_read_ok', user_id: other, marked: n });
      await this.pushUnread(me);
      return;
    }
    return this.fail(ws, 'Ação de mensagem desconhecida.', 'invalid', other);
  }
}
module.exports = { DirectMessages, cleanBody, MAX_LEN, HISTORY };
