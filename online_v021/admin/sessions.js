'use strict';
// R180 · SESSÕES (Admin → Sessões): para cada visita ao jogo, quanto tempo a pessoa ficou, por quais TELAS passou
// (o jogo manda só o nome da tela: ui_screen) e o que ela TENTOU FAZER (o servidor anota as ações que já recebe:
// entrar na fila, convidar, comprar, mandar mensagem no chat… e o que respondeu: partida encontrada, resultado,
// pagamento aprovado). Nada de conteúdo de mensagem, nada de posição de clique.
// Sessão = da 1ª conexão até a última aba fechar + GRACE_MS sem voltar (recarregar a página não abre outra).
// Banco: public.player_sessions (migração 0030), guardado 30 dias. Sem a tabela: só memória (as últimas 300).
const crypto = require('crypto');

const GRACE_MS = 90e3;
const MAX_EVENTS = 500;
const RECENT = 300;
const KEEP_DAYS = 30;
const FLUSH_MS = 60e3;
const missing = e => /42P01|42703|PGRST200|PGRST202|PGRST204|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));
const cleanTxt = (s, n) => String(s === undefined || s === null ? '' : s).replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, n);

const MODE = { ranked: 'Ranqueado', casual: 'Casual', xeque: 'Xeque', marcha: 'Marcha Real' };
const gameName = m => MODE[String(m && m.game || '')] || cleanTxt(m && m.game, 20) || '';
const OUTCOME = { win: 'VITÓRIA', loss: 'derrota', draw: 'empate' };

// ações que o JOGO pede (mensagens que chegam). Função → texto, ou '' para ignorar.
const IN = {
  acct_create_profile: () => 'Criou a conta (escolheu o apelido)',
  acct_change_nickname: () => 'Trocou o apelido',
  acct_set_cosmetics: () => 'Trocou o visual (avatar / título / moldura)',
  acct_avatar_upload: () => 'Enviou foto de perfil',
  acct_avatar_clear: () => 'Tirou a foto de perfil',
  acct_set_status: () => 'Mudou o status',
  acct_logout: () => 'Saiu da conta (logout)',
  acct_delete: () => 'Pediu para EXCLUIR a conta',
  ranked_queue: m => 'Entrou na fila do Ranqueado' + (m.mode ? ' (' + cleanTxt(m.mode, 20) + ')' : ''),
  ranked_cancel: () => 'Saiu da fila do Ranqueado',
  casual_queue: m => 'Entrou na fila do Casual' + (m.mode ? ' (' + cleanTxt(m.mode, 20) + ')' : ''),
  casual_cancel: () => 'Saiu da fila do Casual',
  party_queue: m => 'Procurou mesa online' + (gameName(m) ? ' de ' + gameName(m) : ''),
  party_queue_cancel: () => 'Desistiu de procurar mesa',
  party_start: m => 'Começou partida na mesa' + (gameName(m) ? ' (' + gameName(m) + ')' : ''),
  party_leave: () => 'Saiu da mesa',
  marcha_start: () => 'Começou Marcha Real',
  chat_send: () => 'Mandou mensagem no chat da partida',
  chat_emote: () => 'Mandou emote',
  party_chat: () => 'Mandou mensagem no chat da mesa',
  party_emote: () => 'Mandou emote',
  gchat_join: () => 'Entrou no chat global',
  gchat_send: () => 'Mandou mensagem no chat global',
  dm_send: () => 'Mandou mensagem privada',
  dchat_send: () => 'Respondeu no Chat Exclusivo',
  social_search: () => 'Procurou um jogador',
  social_request: () => 'Pediu amizade',
  social_accept: () => 'Aceitou amizade',
  social_report: () => 'Denunciou um jogador', chat_report: () => 'Denunciou mensagem', gchat_report: () => 'Denunciou mensagem',
  invite_send: () => 'Convidou alguém para jogar',
  invite_accept: () => 'Aceitou convite para jogar',
  invite_decline: () => 'Recusou convite',
  payment_founders: () => 'Viu o Pacote Fundador',
  payment_create: m => 'Iniciou pagamento' + (m.product_id ? ' (' + cleanTxt(m.product_id, 30) + ')' : ''),
  payment_charge: m => 'Gerou cobrança' + (m.product_id ? ' (' + cleanTxt(m.product_id, 30) + ')' : '') + (m.method ? ' · ' + cleanTxt(m.method, 12) : ''),
  payment_card_pay: () => 'Tentou pagar com cartão',
  payment_cancel: () => 'Cancelou o pagamento',
  store_buy: m => 'Comprou na Loja de Coroas' + (m.item_id || m.id ? ' (' + cleanTxt(m.item_id || m.id, 30) + ')' : ''),
  crowns_reward: () => 'Resgatou Coroas',
  ticket_send: () => 'Mandou mensagem ao SUPORTE',
  tev_join: () => 'Inscreveu-se em torneio',
  creator_set: () => 'Escolheu um criador para apoiar',
  analysis_request: () => 'Pediu análise de partida',
  train_request: () => 'Pediu treino',
  bot_victory: m => 'Venceu um bot' + (m.bot_id ? ' (' + cleanTxt(m.bot_id, 20) + ')' : ''),
  voice_join: () => 'Entrou no chat de voz',
};
// R181 · eventos de PRODUTO que o jogo manda (ui_event): só os da lista entram na linha do tempo
const secsTxt = m => { const v = Math.round(Number(m.secs)); return Number.isFinite(v) && v >= 0 && v < 36000 ? v + 's' : '?'; };
const botTxt = m => cleanTxt(m.bot, 24).toUpperCase();
const UI_EVENTS = {
  queue_bot_offer: m => `Ofereceu bot na fila (${secsTxt(m)}${m.mode ? ' · ' + cleanTxt(m.mode, 30) : ''})`,
  queue_bot_accept: m => 'Aceitou bot na fila' + (m.bot ? ` (${botTxt(m)})` : ''),
  queue_bot_decline: m => 'Recusou e continuou esperando' + (m.secs !== undefined ? ` (${secsTxt(m)})` : ''),
  next_challenge: m => 'Clicou no próximo desafio após vitória' + (m.bot ? ` (${botTxt(m)})` : ''),
  first_bot_shown: () => 'Viu o convite do 1º desafio (BOT MADEIRA)',
  first_bot_accept: () => 'Aceitou o 1º desafio (BOT MADEIRA)',
  first_bot_skip: () => 'Pulou o 1º desafio e foi para o menu',
  bot_result: m => ({ win: 'Venceu', loss: 'Perdeu para', draw: 'Empatou com' }[String(m.outcome)] || 'Terminou contra') + (m.bot ? ' ' + botTxt(m) : ' o bot'),
};

// respostas do SERVIDOR que contam a história (mensagens que saem)
const OUT = {
  ranked_found: () => 'Partida encontrada (Ranqueado)',
  casual_found: () => 'Partida encontrada (Casual)',
  ranked_result: m => 'Fim de partida (Ranqueado): ' + (OUTCOME[m.outcome] || m.outcome || '?') + (m.pl_change ? ` (${m.pl_change > 0 ? '+' : ''}${m.pl_change} PL)` : ''),
  casual_result: m => 'Fim de partida (Casual): ' + (OUTCOME[m.outcome] || m.outcome || '?'),
  payment_update: m => m.charge && m.charge.status === 'approved' ? 'PAGAMENTO APROVADO' + (m.charge.product_id ? ' (' + cleanTxt(m.charge.product_id, 30) + ')' : '') : '',
  acct_suspended: () => 'Conta suspensa: entrada recusada',
};

class Sessions {
  constructor({ backend, now = () => Date.now(), timers = true }) {
    this.backend = backend; this.now = now;
    this.live = new Map();     // player id -> sessão aberta
    this.bySid = new Map();    // sid -> sessão (aberta ou recente)
    this.recent = [];          // sessões terminadas (memória), mais nova no fim
    this.db = null;            // null = ainda não sei; true/false depois da 1ª gravação
    if (timers) {
      this.flushTimer = setInterval(() => this.flush().catch(() => {}), FLUSH_MS); if (this.flushTimer.unref) this.flushTimer.unref();
      this.pruneTimer = setInterval(() => this.prune().catch(() => {}), 3600e3); if (this.pruneTimer.unref) this.pruneTimer.unref();
    }
  }
  get store() { return this.backend.store; }
  stop() { clearInterval(this.flushTimer); clearInterval(this.pruneTimer); for (const s of this.live.values()) clearTimeout(s.endTimer); }

  // ---------- ciclo da sessão ----------
  // a identidade ficou online (1ª aba). Volta dentro do GRACE = mesma sessão.
  online(identity, kind) {
    const id = String(identity.id), t = this.now();
    let s = this.live.get(id);
    if (s) {
      clearTimeout(s.endTimer); s.endTimer = null;
      s.justCreated = false;
      if (s.offlineAt) { s.offlineAt = 0; this.add(s, 'sys', 'Reconectou'); }
      if (identity.nickname) s.nickname = cleanTxt(identity.nickname, 40);
      return s;
    }
    s = { sid: crypto.randomUUID(), player: id, user_id: identity.guest ? null : id, nickname: cleanTxt(identity.nickname, 40), guest: !!identity.guest,
      kind: kind || (identity.guest ? 'guest' : 'account'), started: t, last: t, offlineAt: 0, ended: 0, screen: '', screenAt: t, device: {}, events: [], dirty: true, saved: false, justCreated: true };
    this.live.set(id, s); this.bySid.set(s.sid, s);
    this.add(s, 'sys', { account: 'Entrou no jogo', new_account: 'Entrou (CONTA NOVA)', guest: 'Entrou como convidado', guest_new: 'Entrou como NOVO convidado' }[s.kind] || 'Entrou no jogo');
    return s;
  }
  // a última aba dessa identidade fechou
  offline(id) {
    const s = this.live.get(String(id)); if (!s || s.offlineAt) return;
    s.offlineAt = this.now();
    s.endTimer = setTimeout(() => this.finish(s), GRACE_MS); if (s.endTimer.unref) s.endTimer.unref();
  }
  finish(s) {
    if (s.ended || this.live.get(s.player) !== s || !s.offlineAt) return;
    s.ended = s.offlineAt; s.last = s.offlineAt;
    this.add(s, 'sys', 'Saiu do jogo' + (s.screen ? ' (estava em: ' + s.screen + ')' : ''), s.offlineAt);
    this.live.delete(s.player);
    this.recent.push(s);
    while (this.recent.length > RECENT) { const old = this.recent.shift(); if (!this.live.has(old.player) || this.live.get(old.player) !== old) this.bySid.delete(old.sid); }
    this.save(s).catch(() => {});
  }
  add(s, k, l, t = this.now()) {
    if (!l) return;
    const last = s.events[s.events.length - 1];
    if (last && last.k === k && last.l === l && t - (s.started + last.t) < 3000) return;   // repetido em seguida: uma vez só
    if (s.events.length >= MAX_EVENTS) { if (s.events.length === MAX_EVENTS) s.events.push({ t: t - s.started, k: 'sys', l: '(limite de eventos desta sessão atingido)' }); return; }
    s.events.push({ t: Math.max(0, t - s.started), k, l: cleanTxt(l, 120) });
    s.last = Math.max(s.last, t); s.dirty = true;
  }
  of(ws) { const id = ws && ws.identity && ws.identity.id; return id ? this.live.get(String(id)) || null : null; }

  // ---------- mensagens ----------
  incoming(ws, a, m) {
    if (a === 'ui_screen' || a === 'ui_hello' || a === 'ui_event') { this.uiMessage(ws, a, m); return true; }
    const s = this.of(ws); if (!s) return false;
    const f = IN[a]; if (f) { try { this.add(s, 'act', f(m || {})); } catch { /* só registro */ } }
    return false;
  }
  outgoing(ws, msg) {
    const f = msg && OUT[msg.type]; if (!f) return;
    const s = this.of(ws); if (!s) return;
    try { this.add(s, 'res', f(msg)); } catch { /* só registro */ }
  }
  uiMessage(ws, a, m) {
    const s = this.of(ws); if (!s) return;
    const t = this.now();
    ws.uiCount = ws.uiCount && t - ws.uiAt < 60e3 ? ws.uiCount + 1 : 1; if (ws.uiCount === 1) ws.uiAt = t;
    if (ws.uiCount > 120) return;   // no máximo 120 trocas de tela por minuto por aba
    if (a === 'ui_event') {   // R181 · só eventos conhecidos; desconhecido é ignorado
      const f = UI_EVENTS[String(m && m.name || '')];
      if (f) { try { this.add(s, 'act', f(m || {}), t); } catch { /* só registro */ } }
      return;
    }
    if (a === 'ui_hello') {
      const d = {};
      for (const k of ['platform', 'device', 'browser', 'version', 'lang']) if (m[k] !== undefined) d[k] = cleanTxt(m[k], 40);
      if (m.mobile !== undefined) d.mobile = !!m.mobile;
      for (const k of ['w', 'h']) { const v = Number(m[k]); if (Number.isFinite(v) && v > 0 && v < 20000) d[k] = Math.round(v); }
      const first = !Object.keys(s.device).length;
      s.device = d; s.dirty = true;
      if (first) this.add(s, 'sys', [d.device, d.browser, d.mobile ? 'celular' : 'computador', d.w && d.h ? d.w + 'x' + d.h : '', d.version ? 'v' + d.version : ''].filter(Boolean).join(' · '));
      return;
    }
    const name = cleanTxt(m.name, 60); if (!name || name === s.screen) return;
    s.screen = name; s.screenAt = t;
    this.add(s, 'screen', name, t);
  }

  // ---------- visão do Admin ----------
  view(s, full = false) {
    const t = this.now(), end = s.ended || (s.offlineAt || t);
    const screens = {};
    let prev = null;
    for (const e of s.events) {
      if (e.k !== 'screen') continue;
      if (prev) screens[prev.l] = (screens[prev.l] || 0) + (e.t - prev.t);
      prev = e;
    }
    if (prev) screens[prev.l] = (screens[prev.l] || 0) + Math.max(0, end - s.started - prev.t);
    const out = { sid: s.sid, player: s.player, user_id: s.user_id, nickname: s.nickname, guest: s.guest, kind: s.kind,
      started_at: new Date(s.started).toISOString(), ended_at: s.ended ? new Date(s.ended).toISOString() : null,
      state: s.ended ? 'ended' : s.offlineAt ? 'away' : 'online', duration_ms: Math.max(0, end - s.started),
      screen: s.screen, screens_count: Object.keys(screens).length, actions_count: s.events.filter(e => e.k === 'act').length, device: s.device };
    if (full) { out.events = s.events; out.time_by_screen = Object.entries(screens).sort((a, b) => b[1] - a[1]).map(([l, ms]) => ({ screen: l, ms })); }
    return out;
  }
  // linha do banco → mesmo formato da memória
  fromRow(r) {
    const started = Date.parse(r.started_at), ended = r.ended_at ? Date.parse(r.ended_at) : 0;
    return { sid: r.session_id, player: r.player, user_id: r.user_id || null, nickname: r.nickname || '', guest: String(r.player || '').startsWith('guest:'), kind: r.kind || 'account',
      started, last: Date.parse(r.last_seen_at) || started, offlineAt: ended || Date.parse(r.last_seen_at) || started, ended: ended || Date.parse(r.last_seen_at) || started,
      screen: r.last_screen || '', device: r.device || {}, events: Array.isArray(r.events) ? r.events : [] };
  }
  async list({ q = '', limit = 100 } = {}) {
    const lim = Math.max(1, Math.min(300, Number(limit) || 100));
    const needle = cleanTxt(q, 40).toLowerCase();
    const match = s => !needle || s.nickname.toLowerCase().includes(needle) || String(s.player).toLowerCase() === needle;
    const seen = new Set(), items = [];
    const push = s => { if (seen.has(s.sid) || !match(s)) return; seen.add(s.sid); items.push(this.view(s)); };
    for (const s of this.live.values()) push(s);
    for (let i = this.recent.length - 1; i >= 0; i--) push(this.recent[i]);
    let stored = this.db !== false && !!(this.store && this.store.listSessions);
    if (stored) {
      try { for (const r of await this.store.listSessions({ limit: lim, q: needle })) push(this.fromRow(r)); this.db = true; }
      catch (e) { if (missing(e)) this.db = false; else console.error('[sessoes] lista', e && e.message); stored = this.db !== false; }
    }
    items.sort((a, b) => (a.state === 'ended') - (b.state === 'ended') || Date.parse(b.started_at) - Date.parse(a.started_at));
    const today = new Date(this.now()); today.setUTCHours(3, 0, 0, 0); if (today.getTime() > this.now()) today.setUTCDate(today.getUTCDate() - 1);   // meia-noite de Brasília
    const todays = items.filter(i => Date.parse(i.started_at) >= today.getTime());
    return { items: items.slice(0, lim), online: [...this.live.values()].filter(s => !s.offlineAt).length, persistent: stored, keep_days: KEEP_DAYS,
      today: { sessions: todays.length, avg_ms: todays.length ? Math.round(todays.reduce((n, i) => n + i.duration_ms, 0) / todays.length) : 0 } };
  }
  async get(sid) {
    const s = this.bySid.get(sid); if (s) return this.view(s, true);
    if (this.db === false || !this.store || !this.store.getSession) return null;
    try { const r = await this.store.getSession(sid); return r ? this.view(this.fromRow(r), true) : null; }
    catch (e) { if (missing(e)) this.db = false; return null; }
  }

  // ---------- banco ----------
  row(s) {
    const t = this.now(), end = s.ended || s.offlineAt || t;
    return { session_id: s.sid, player: s.player, user_id: s.user_id, nickname: s.nickname, kind: s.kind,
      started_at: new Date(s.started).toISOString(), ended_at: s.ended ? new Date(s.ended).toISOString() : null, last_seen_at: new Date(Math.max(s.last, end)).toISOString(),
      duration_s: Math.round(Math.max(0, end - s.started) / 1000), last_screen: s.screen, device: s.device, events: s.events };
  }
  async save(s) {
    if (this.db === false || !this.store || !this.store.saveSession) return;
    s.dirty = false;
    try { await this.store.saveSession(this.row(s)); this.db = true; s.saved = true; }
    catch (e) { s.dirty = true; if (missing(e)) { if (this.db !== false) console.log('[sessoes] banco sem a migração 0030: sessões só na memória'); this.db = false; } else console.error('[sessoes] gravar', e && e.message); }
  }
  async flush() { for (const s of [...this.live.values()]) if (s.dirty) await this.save(s); }
  async prune() {
    if (this.db === false || !this.store || !this.store.pruneSessions) return;
    try { await this.store.pruneSessions(new Date(this.now() - KEEP_DAYS * 86400e3).toISOString()); } catch (e) { if (missing(e)) this.db = false; }
  }
}
module.exports = { Sessions, IN, OUT, UI_EVENTS, GRACE_MS, KEEP_DAYS };
