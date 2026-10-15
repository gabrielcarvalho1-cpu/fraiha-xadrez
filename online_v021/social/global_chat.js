'use strict';
// R96 · CHAT GLOBAL (botão ao lado do troféu na Home): uma sala para o servidor inteiro.
// Efêmero: as últimas HISTORY mensagens ficam na memória do servidor (somem num reinício/deploy).
// Ler: qualquer um conectado (conta ou convidado). Escrever: só conta com perfil (responsável pelo que escreve).
// Mesmas regras do chat da partida (texto limpo, 200 caracteres, sem spam/rajada) + intervalo mínimo próprio.
// DENUNCIAR: registra no log do servidor (quem, qual mensagem) para moderação; SILENCIAR é só no aparelho.
const { clean } = require('../chat');
const HISTORY = 80;
const MIN_GAP_MS = 2500;        // no global, no máximo 1 mensagem a cada 2,5 s por conta
const MAX_MEMBERS_PUSH = 5000;  // proteção: não percorre mais que isso por mensagem

class GlobalChat {
  constructor({ send, backend, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.send = send; this.backend = backend; this.now = now; this.log = log;
    this.members = new Set();
    this.messages = [];
    this.seq = 0;
    this.lastAt = new Map();    // uid -> última mensagem aceita
  }
  alive(ws) { return !ws.dead && (ws.readyState === undefined || ws.readyState === 1); }
  canSend(ws) { return !!(ws.user && ws.profile); }
  count() { let n = 0; for (const ws of this.members) if (this.alive(ws)) n++; return n; }
  onClose(ws) { this.members.delete(ws); }
  broadcast(msg) {
    let i = 0;
    for (const ws of this.members) {
      if (!this.alive(ws)) { this.members.delete(ws); continue; }
      if (++i > MAX_MEMBERS_PUSH) break;
      this.send(ws, msg);
    }
  }
  handle(ws, m) {
    const a = String(m.type || '');
    const fail = (message, code) => this.send(ws, { type: 'gchat_error', message, code });
    if (a === 'gchat_join') {
      this.members.add(ws);
      return this.send(ws, { type: 'gchat_history', messages: this.messages, can_send: this.canSend(ws), online: this.count() });
    }
    if (a === 'gchat_leave') { this.members.delete(ws); return; }
    if (a === 'gchat_send') {
      if (!this.canSend(ws)) return fail('Entre na sua conta para escrever no chat global.', 'auth_required');
      const c = clean(m.text);
      if (c.error) return fail(c.error, c.code);
      const uid = ws.user.id, now = this.now();
      if (now - (this.lastAt.get(uid) || 0) < MIN_GAP_MS) return fail('Calma! Espere um instante para mandar outra mensagem.', 'rate_limited');
      const hub = this.backend && this.backend.chat;
      const ok = hub ? hub.allow('global:' + uid, c.text, now) : { ok: true };
      if (ok.error) return fail(ok.error, ok.code);
      this.lastAt.set(uid, now);
      this.members.add(ws);
      const p = ws.profile;
      const entry = { id: ++this.seq, user_id: uid, nickname: String(p.nickname || 'Jogador'), avatar_id: String(p.avatar_id || ''),
        text: c.text, ts: new Date(now).toISOString() };
      this.messages.push(entry); if (this.messages.length > HISTORY) this.messages.shift();
      return this.broadcast({ type: 'gchat_msg', ...entry });
    }
    if (a === 'gchat_report') {
      const id = Number(m.id) || 0, e = this.messages.find(x => x.id === id);
      if (!e) return fail('Mensagem não encontrada.', 'not_found');
      const who = ws.user ? ws.user.id : (ws.identity && ws.identity.id) || '?';
      this.log('[gchat-report]', JSON.stringify({ by: who, msg_id: e.id, user_id: e.user_id, nickname: e.nickname, text: e.text, ts: e.ts }));
      // R104 · contas: também vai para a fila de denúncias do Admin (convidado não tem id fixo para denunciar)
      const R = this.backend && this.backend.reports;
      if (R && ws.user && e.user_id && !String(e.user_id).startsWith('guest')) {
        const mine = this.messages.filter(x => x.user_id === e.user_id).slice(-10).map(x => x.text);
        return R.file({ reporter: ws.user.id, reported: e.user_id, kind: 'global_chat', ref: String(e.id),
          context: { reported_nickname: e.nickname, reporter_nickname: ws.profile && ws.profile.nickname, messages: mine } })
          .then(() => this.send(ws, { type: 'gchat_reported', id })).catch(() => this.send(ws, { type: 'gchat_reported', id }));
      }
      return this.send(ws, { type: 'gchat_reported', id });
    }
    return fail('Ação inválida.', 'invalid');
  }
}

module.exports = { GlobalChat, HISTORY, MIN_GAP_MS };
