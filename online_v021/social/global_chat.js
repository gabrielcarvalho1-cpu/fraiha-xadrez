'use strict';
// R96 · CHAT GLOBAL (botão ao lado do troféu na Home): uma sala para o servidor inteiro.
// Efêmero: as últimas HISTORY mensagens ficam na memória do servidor (somem num reinício/deploy).
// Ler: qualquer um conectado (conta ou convidado). Escrever: só conta com perfil (responsável pelo que escreve).
// Mesmas regras do chat da partida (texto limpo, 200 caracteres, sem spam/rajada) + intervalo mínimo próprio.
// DENUNCIAR: registra no log do servidor (quem, qual mensagem) para moderação; SILENCIAR é só no aparelho.
const { clean } = require('../chat');
const { look } = require('../accounts/cosmetics');
const HISTORY = 80;          // por canal
// R168 · CANAIS (abas): GERAL, PROCURANDO PARCEIROS (achar gente para jogar) e DÚVIDAS E AJUDA.
const CHANNELS = ['geral', 'parceiros', 'ajuda'];
const MIN_GAP_MS = 2500;        // no global, no máximo 1 mensagem a cada 2,5 s por conta
// R171 · SEC-010: denúncia igual (mesma pessoa + mesma mensagem) vale 1 vez por 24 h; teto 10 por pessoa e 30 por IP a cada 10 min
const REPORT_DUP_MS = 24 * 3600e3, REPORT_WINDOW_MS = 10 * 60e3, REPORT_MAX = 10, REPORT_MAX_PER_IP = 30;
const MAX_MEMBERS_PUSH = 5000;  // proteção: não percorre mais que isso por mensagem

class GlobalChat {
  constructor({ send, backend, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.send = send; this.backend = backend; this.now = now; this.log = log;
    this.members = new Set();
    this.messages = [];
    this.seq = 0;
    this.lastAt = new Map();    // uid -> última mensagem aceita
    // R171 · SEC-010: denúncia repetida (mesma pessoa + mesma mensagem) não gera novo registro; teto por pessoa e por IP
    this.reportSeen = new Map();   // `${reporter}|${msgId}|global_chat` -> quando
    this.reportRate = new Map();   // reporter ou ip -> [instantes]
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
      return this.send(ws, { type: 'gchat_history', messages: this.messages, channels: CHANNELS, can_send: this.canSend(ws), online: this.count() });
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
      if (this.lastAt.size > 5000) for (const [k, v] of this.lastAt) if (now - v > MIN_GAP_MS) this.lastAt.delete(k);   // R170 · SEC-003: mapa auxiliar com teto
      this.lastAt.set(uid, now);
      this.members.add(ws);
      const p = ws.profile;
      const channel = CHANNELS.includes(String(m.channel || '')) ? String(m.channel) : 'geral';
      const lk = look(p);   // R169 · título (e selo) aparecem ao lado do nome no chat global
      const entry = { id: ++this.seq, channel, user_id: uid, nickname: String(p.nickname || 'Jogador'), avatar_id: String(p.avatar_id || ''), title: lk.title, badge: lk.badge,
        text: c.text, ts: new Date(now).toISOString() };
      this.messages.push(entry);
      // guarda as últimas HISTORY de CADA canal (um canal movimentado não apaga os outros)
      if (this.messages.filter(x => x.channel === channel).length > HISTORY) this.messages.splice(this.messages.findIndex(x => x.channel === channel), 1);
      return this.broadcast({ type: 'gchat_msg', ...entry });
    }
    if (a === 'gchat_report') {
      const id = Number(m.id) || 0, e = this.messages.find(x => x.id === id);
      if (!e) return fail('Mensagem não encontrada.', 'not_found');
      const who = ws.user ? ws.user.id : (ws.identity && ws.identity.id) || '?';
      // R171 · SEC-010: deduplica ANTES de registrar (inclusive convidado) e limita o volume por pessoa e por IP
      const now = this.now(), key = who + '|' + e.id + '|global_chat';
      if (this.reportSeen.size > 20000) for (const [k, t] of this.reportSeen) if (now - t > REPORT_DUP_MS) this.reportSeen.delete(k);
      const seen = this.reportSeen.get(key);
      if (seen && now - seen < REPORT_DUP_MS) return this.send(ws, { type: 'gchat_reported', id, duplicate: true });
      const limited = [who, 'ip:' + (ws.ip || 'local')].some(k => {
        const max = k.startsWith('ip:') ? REPORT_MAX_PER_IP : REPORT_MAX;
        const list = (this.reportRate.get(k) || []).filter(t => now - t < REPORT_WINDOW_MS);
        this.reportRate.set(k, list);
        return list.length >= max;
      });
      if (limited) return fail('Você fez muitas denúncias seguidas. Aguarde alguns minutos.', 'rate_limited');
      for (const k of [who, 'ip:' + (ws.ip || 'local')]) this.reportRate.get(k).push(now);
      if (this.reportRate.size > 20000) this.reportRate.clear();
      this.reportSeen.set(key, now);
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

module.exports = { GlobalChat, HISTORY, MIN_GAP_MS, CHANNELS };
