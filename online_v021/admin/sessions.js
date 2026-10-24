'use strict';
// R180 · SESSÕES (Admin → Sessões): para cada visita ao jogo, quanto tempo a pessoa ficou, por quais TELAS passou
// (o jogo manda só o nome da tela: ui_screen) e o que ela TENTOU FAZER (o servidor anota as ações que já recebe:
// entrar na fila, convidar, comprar, mandar mensagem no chat… e o que respondeu: partida encontrada, resultado,
// pagamento aprovado). Nada de conteúdo de mensagem, nada de posição de clique.
// Sessão = da 1ª conexão até a última aba fechar + GRACE_MS sem voltar (recarregar a página não abre outra).
// Banco: public.player_sessions (migração 0030), guardado 30 dias. Sem a tabela: só memória (as últimas 300).
const crypto = require('crypto');

const GRACE_MS = 90e3;
const VISIT_IDLE_MS = 4 * 60e3;     // R181 · visitante sem login: sem nenhum sinal por 4 min = saiu
const MAX_VISITS = 5000;            // visitas sem login abertas na memória (acima disso, a mais velha fecha)
const TEST_NICKS_RAW = (process.env.FRAIHA_TEST_NICKS || 'SextoSentro,DaSilva').split(',').map(s => s.trim()).filter(Boolean);   // apelidos de teste do dono
const TEST_NICKS = TEST_NICKS_RAW.map(s => s.toLowerCase());
const hexToUuid = h => `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
// dia em Brasília (UTC−3) de um instante → 'AAAA-MM-DD'
const dayBR = t => new Date(t - 3 * 3600e3).toISOString().slice(0, 10);
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
  next_challenge: m => 'Clicou no próximo desafio após vitória' + (m.bot ? ` (${botTxt(m)})` : ''),
  // R181 · login com Google dentro do Instagram/Facebook/TikTok
  google_inapp: m => 'Tentou entrar com Google dentro do ' + (cleanTxt(m.app, 20) || 'app') + ': mostrou "Abra no navegador"',
  google_inapp_force: m => 'Tentou Google dentro do ' + (cleanTxt(m.app, 20) || 'app') + ' mesmo assim',
  google_open_browser: m => 'Tocou em abrir no navegador' + (m.os ? ' (' + cleanTxt(m.os, 10) + ')' : ''),
  google_state_retry: () => 'Login Google voltou com erro de "state": tentando de novo sozinho',
  google_state_failed: m => 'Login Google falhou de novo (erro de "state")' + (m.app ? ' no ' + cleanTxt(m.app, 20) : ''),
  first_bot_shown: () => 'Viu o convite do 1º desafio (BOT MADEIRA)',
  first_bot_accept: () => 'Aceitou o 1º desafio (BOT MADEIRA)',
  first_bot_skip: () => 'Pulou o 1º desafio e foi para o menu',
  bot_result: m => ({ win: 'Venceu', loss: 'Perdeu para', draw: 'Empatou com' }[String(m.outcome)] || 'Terminou contra') + (m.bot ? ' ' + botTxt(m) : ' o bot'),
};

const aiFound = (k, m) => `Rival IA encontrado após ${Math.round((Number(m.ai_wait_ms) || 0) / 1000)}s (${k})` + (m.opponent && m.opponent.nickname ? ': ' + cleanTxt(m.opponent.nickname, 30) : '');
// respostas do SERVIDOR que contam a história (mensagens que saem)
const OUT = {
  // R181 · rival de IA: "Rival IA encontrado após 25s: Sir Gambito"
  ranked_found: m => m.vs_ai ? aiFound('Ranqueado', m) : 'Partida encontrada (Ranqueado)',
  casual_found: m => m.vs_ai ? aiFound('Casual', m) : 'Partida encontrada (Casual)',
  ranked_result: m => 'Fim de partida (Ranqueado' + (m.vs_ai ? ', rival IA' : '') + '): ' + (OUTCOME[m.outcome] || m.outcome || '?') + (m.pl_change ? ` (${m.pl_change > 0 ? '+' : ''}${m.pl_change} PL)` : ''),
  casual_result: m => 'Fim de partida (Casual' + (m.vs_ai ? ', rival IA' : '') + '): ' + (OUTCOME[m.outcome] || m.outcome || '?'),
  payment_update: m => m.charge && m.charge.status === 'approved' ? 'PAGAMENTO APROVADO' + (m.charge.product_id ? ' (' + cleanTxt(m.charge.product_id, 30) + ')' : '') : '',
  acct_suspended: () => 'Conta suspensa: entrada recusada',
};

class Sessions {
  constructor({ backend, now = () => Date.now(), timers = true }) {
    this.backend = backend; this.now = now;
    this.live = new Map();     // player id -> sessão aberta
    this.visits = new Map();   // R181 · sid -> sessão aberta que começou SEM login (rota /t); sai daqui ao terminar
    this.bySid = new Map();    // sid -> sessão (aberta ou recente)
    this.recent = [];          // sessões terminadas (memória), mais nova no fim
    this.db = null;            // null = ainda não sei; true/false depois da 1ª gravação
    if (timers) {
      this.flushTimer = setInterval(() => this.flush().catch(() => {}), FLUSH_MS); if (this.flushTimer.unref) this.flushTimer.unref();
      this.pruneTimer = setInterval(() => this.prune().catch(() => {}), 3600e3); if (this.pruneTimer.unref) this.pruneTimer.unref();
      this.visitTimer = setInterval(() => this.sweepVisits(), 20e3); if (this.visitTimer.unref) this.visitTimer.unref();
    }
  }
  get store() { return this.backend.store; }
  stop() { clearInterval(this.flushTimer); clearInterval(this.pruneTimer); clearInterval(this.visitTimer); for (const s of this.live.values()) clearTimeout(s.endTimer); }

  // ---------- ciclo da sessão ----------
  // a identidade ficou online (1ª aba). Volta dentro do GRACE = mesma sessão.
  online(identity, kind, ws = null) {
    const id = String(identity.id), t = this.now();
    let s = this.live.get(id);
    // R181 · a aba já vinha sendo registrada como VISITANTE (rota /t): a visita vira a sessão desta conta/convidado
    const v = ws && ws.trackSid ? this.bySid.get(ws.trackSid) : null;
    if (v && !v.ended && v !== s && (v.kind === 'visitor' || v.player === id)) {
      if (s) { this.mergeInto(v, s); }
      else {
        v.player = id; v.user_id = identity.guest ? null : id; v.nickname = cleanTxt(identity.nickname, 40); v.guest = !!identity.guest;
        v.kind = kind || (identity.guest ? 'guest' : 'account'); v.linked = true; v.justCreated = true; v.flags.passed = true;
        v.offlineAt = 0; v.exitAt = 0;
        this.visits.delete(v.sid); this.live.set(id, v);
        this.add(v, 'sys', { account: 'Entrou na conta', new_account: 'Entrou (CONTA NOVA)', guest: 'Entrou como convidado', guest_new: 'Entrou como NOVO convidado' }[v.kind] || 'Entrou no jogo', t);
        return v;
      }
    }
    if (s) {
      clearTimeout(s.endTimer); s.endTimer = null;
      s.justCreated = false;
      if (s.offlineAt) { s.offlineAt = 0; this.add(s, 'sys', 'Reconectou'); }
      if (identity.nickname) s.nickname = cleanTxt(identity.nickname, 40);
      return s;
    }
    s = { sid: crypto.randomUUID(), player: id, user_id: identity.guest ? null : id, nickname: cleanTxt(identity.nickname, 40), guest: !!identity.guest,
      kind: kind || (identity.guest ? 'guest' : 'account'), started: t, last: t, offlineAt: 0, ended: 0, screen: '', screenAt: t, device: {}, events: [], dirty: true, saved: false, justCreated: true,
      vid: null, utm: {}, flags: { passed: true } };
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
    const lastEv = s.events[s.events.length - 1];   // R181 · o site já avisou a saída (com tela e botão): não repete
    if (!lastEv || !/^Saiu/.test(lastEv.l)) this.add(s, 'sys', 'Saiu do jogo' + (s.screen ? ' (estava em: ' + s.screen + ')' : ''), s.offlineAt);
    this.live.delete(s.player);
    this.recent.push(s);
    while (this.recent.length > RECENT) { const old = this.recent.shift(); if (!this.live.has(old.player) || this.live.get(old.player) !== old) this.bySid.delete(old.sid); }
    this.save(s).catch(() => {});
  }
  // ---------- R181 · visitante sem login (rota HTTP /t) ----------
  hasVisit(sidHex) { return this.bySid.has(hexToUuid(sidHex)); }
  // abre (ou continua) a visita desta aba. start = ms desde que a página abriu, no momento do envio
  visit(sidHex, vid, { utm = {}, device = {}, start = null } = {}) {
    const sid = hexToUuid(sidHex), t = this.now();
    let s = this.bySid.get(sid);
    if (s && s.vid && s.vid !== vid) return null;   // sid de outro navegador: ignora
    if (!s) {
      if (this.visits.size >= MAX_VISITS) { const oldest = this.visits.values().next().value; if (oldest) this.finishVisit(oldest); }
      const st = start !== null ? t - start : t;
      s = { sid, player: 'visitor:' + vid, user_id: null, nickname: 'Visitante ' + vid.slice(0, 4).toUpperCase(), guest: true, kind: 'visitor',
        started: st, last: t, offlineAt: 0, ended: 0, exitAt: 0, screen: '', screenAt: st, lastButton: '', device: {}, events: [], dirty: true, saved: false,
        vid, utm: utm || {}, flags: {}, linked: false };
      this.visits.set(sid, s); this.bySid.set(sid, s);
      this.add(s, 'sys', 'Abriu o jogo' + (utm && utm.ad ? ' (veio do ANÚNCIO' + (utm.source ? ': ' + utm.source : '') + (utm.campaign ? ' · ' + utm.campaign : '') + ')' : ''), st);
    } else if (s.ended && !s.linked) {
      s.ended = 0; s.offlineAt = 0; s.exitAt = 0; this.visits.set(s.sid, s); this.add(s, 'sys', 'Voltou para o jogo', t);
    }
    if (!s.vid) s.vid = vid;
    if (utm && utm.ad && !(s.utm && s.utm.ad)) s.utm = utm;
    if (device && Object.keys(device).length) {
      const first = !s.device || !s.device.device;
      s.device = { ...(s.device || {}), ...device }; s.dirty = true;
      if (first) this.add(s, 'sys', [device.device, device.os, device.browser, device.w && device.h ? device.w + 'x' + device.h : '', device.version ? 'v' + device.version : ''].filter(Boolean).join(' · '), s.started);
    }
    s._base = start !== null ? t - start : t;   // horário do evento = _base + e.t
    s.last = Math.max(s.last, t);
    return s;
  }
  visitEvent(s, e) {
    const t = Math.max(s.started, Math.min(this.now(), (s._base || this.now()) + e.t));
    if (e.k === 'hb') { s.last = Math.max(s.last, t); return; }
    if (e.k === 'screen') {
      if (e.screen === s.screen) return;
      s.screen = e.screen; s.screenAt = t; this.add(s, 'screen', e.screen, t); return;
    }
    if (e.k === 'click') {
      s.lastButton = e.button;
      this.add(s, 'click', e.button + ' — ' + (e.screen || s.screen || '?'), t); return;
    }
    if (e.loaded) s.flags.loaded = true;
    if (e.passed) s.flags.passed = true;
    if (e.played) s.flags.played = true;
    if (e.exit) { s.exitAt = t; }
    if (e.k === 'back') s.exitAt = 0;
    if (e.label) this.add(s, e.k === 'login' || e.k === 'match' ? 'act' : 'sys', e.label, t);
    s.dirty = true;
  }
  // duas sessões da mesma pessoa (abriu outra aba / recarregou): a visita entra na sessão que já estava aberta
  mergeInto(v, s) {
    const off = v.started - s.started;
    for (const e of v.events) s.events.push({ ...e, t: Math.max(0, e.t + off) });
    s.events.sort((a, b) => a.t - b.t);
    if (s.events.length > MAX_EVENTS) s.events.length = MAX_EVENTS;
    s.flags = { ...(v.flags || {}), ...(s.flags || {}), passed: true };
    if (!s.vid) s.vid = v.vid;
    if (v.utm && v.utm.ad && !(s.utm && s.utm.ad)) s.utm = v.utm;
    if (v.device && v.device.device && !(s.device && s.device.device)) s.device = v.device;
    s.dirty = true;
    this.visits.delete(v.sid); this.bySid.set(v.sid, s);   // eventos HTTP desta aba continuam caindo na sessão da pessoa
    v.ended = this.now(); v.mergedInto = s.sid;
  }
  // ws mandou ui_link depois de já ter identidade
  linkLate(ws) {
    const id = ws && ws.identity && String(ws.identity.id); if (!id) return;
    const s = this.live.get(id), v = this.bySid.get(ws.trackSid);
    if (s && v && v !== s && !v.ended && v.kind === 'visitor') this.mergeInto(v, s);
  }
  finishVisit(s) {
    if (s.ended || s.linked) return;
    const end = s.exitAt || s.last;
    s.ended = end; s.offlineAt = end;
    const lastEv = s.events[s.events.length - 1];
    if (!lastEv || !/^Saiu/.test(lastEv.l)) this.add(s, 'sys', 'Saiu do jogo' + (s.screen ? ' (estava em: ' + s.screen + ')' : '') + (s.lastButton ? ' · último botão: ' + s.lastButton : ''), end);
    this.visits.delete(s.sid);
    this.recent.push(s);
    while (this.recent.length > RECENT) { const old = this.recent.shift(); if (!this.live.has(old.player) || this.live.get(old.player) !== old) this.bySid.delete(old.sid); }
    this.save(s).catch(() => {});
  }
  sweepVisits() {
    const t = this.now();
    for (const s of [...this.visits.values()]) {
      if (s.linked) { this.visits.delete(s.sid); continue; }
      if ((s.exitAt && t - s.exitAt > GRACE_MS) || t - s.last > VISIT_IDLE_MS) this.finishVisit(s);
    }
  }
  add(s, k, l, t = this.now()) {
    if (!l) return;
    const last = s.events[s.events.length - 1];
    if (last && last.k === k && last.l === l && t - (s.started + last.t) < 3000) return;   // repetido em seguida: uma vez só
    if (s.events.length >= MAX_EVENTS) { if (s.events.length === MAX_EVENTS) s.events.push({ t: t - s.started, k: 'sys', l: '(limite de eventos desta sessão atingido)' }); return; }
    const ev = { t: Math.max(0, t - s.started), k, l: cleanTxt(l, 120) };
    // R181 · eventos chegam por dois caminhos (site /t e conexão do jogo): mantém a ordem pelo horário
    let i = s.events.length;
    while (i > 0 && s.events[i - 1].t > ev.t) i--;
    s.events.splice(i, 0, ev);
    s.last = Math.max(s.last, t); s.dirty = true;
  }
  of(ws) { const id = ws && ws.identity && ws.identity.id; return id ? this.live.get(String(id)) || null : null; }

  // ---------- mensagens ----------
  incoming(ws, a, m) {
    if (a === 'ui_link') {   // R181 · esta conexão é da aba que já está sendo registrada como visitante (rota /t)
      const sid = String(m && m.sid || '');
      if (/^[0-9a-f]{32}$/.test(sid)) { ws.trackSid = hexToUuid(sid); if (ws.identity) this.linkLate(ws); }
      return true;
    }
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
      state: s.ended ? 'ended' : (s.offlineAt || s.exitAt) ? 'away' : 'online', duration_ms: Math.max(0, end - s.started),
      screen: s.screen, screens_count: Object.keys(screens).length, actions_count: s.events.filter(e => e.k === 'act').length,
      clicks_count: s.events.filter(e => e.k === 'click').length, device: s.device, vid: s.vid || null, utm: s.utm || {}, flags: s.flags || {} };
    if (full) { out.events = s.events; out.time_by_screen = Object.entries(screens).sort((a, b) => b[1] - a[1]).map(([l, ms]) => ({ screen: l, ms })); }
    return out;
  }
  // linha do banco → mesmo formato da memória
  fromRow(r) {
    const started = Date.parse(r.started_at), ended = r.ended_at ? Date.parse(r.ended_at) : 0;
    return { sid: r.session_id, player: r.player, user_id: r.user_id || null, nickname: r.nickname || '', guest: String(r.player || '').startsWith('guest:'), kind: r.kind || 'account',
      started, last: Date.parse(r.last_seen_at) || started, offlineAt: ended || Date.parse(r.last_seen_at) || started, ended: ended || Date.parse(r.last_seen_at) || started,
      screen: r.last_screen || '', device: r.device || {}, events: Array.isArray(r.events) ? r.events : [],
      vid: r.vid || null, utm: r.utm || {}, flags: r.flags || {} };
  }
  async list({ q = '', limit = 100, ads = false, hideTest = false } = {}) {
    const lim = Math.max(1, Math.min(300, Number(limit) || 100));
    const needle = cleanTxt(q, 40).toLowerCase();
    const testVids = hideTest ? this.testVids() : new Set();
    const match = s => (!needle || s.nickname.toLowerCase().includes(needle) || String(s.player).toLowerCase() === needle)
      && (!ads || (s.utm && s.utm.ad)) && (!hideTest || (!TEST_NICKS.includes(String(s.nickname || '').toLowerCase()) && !(s.vid && testVids.has(s.vid))));
    const seen = new Set(), items = [];
    const push = s => { if (seen.has(s.sid) || !match(s)) return; seen.add(s.sid); items.push(this.view(s)); };
    for (const s of this.live.values()) push(s);
    for (const s of this.visits.values()) push(s);
    for (let i = this.recent.length - 1; i >= 0; i--) push(this.recent[i]);
    let stored = this.db !== false && !!(this.store && this.store.listSessions);
    if (stored) {
      try { for (const r of await this.store.listSessions({ limit: lim, q: needle })) push(this.fromRow(r)); this.db = true; }
      catch (e) { if (missing(e)) this.db = false; else console.error('[sessoes] lista', e && e.message); stored = this.db !== false; }
    }
    items.sort((a, b) => (a.state === 'ended') - (b.state === 'ended') || Date.parse(b.started_at) - Date.parse(a.started_at));
    const today = new Date(this.now()); today.setUTCHours(3, 0, 0, 0); if (today.getTime() > this.now()) today.setUTCDate(today.getUTCDate() - 1);   // meia-noite de Brasília
    const todays = items.filter(i => Date.parse(i.started_at) >= today.getTime());
    return { items: items.slice(0, lim), online: [...this.live.values()].filter(s => !s.offlineAt).length + [...this.visits.values()].filter(s => !s.exitAt).length, persistent: stored, keep_days: KEEP_DAYS, test_nicks: TEST_NICKS_RAW,
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
      duration_s: Math.round(Math.max(0, end - s.started) / 1000), last_screen: s.screen, device: s.device, events: s.events,
      vid: s.vid || null, utm: s.utm || {}, flags: s.flags || {} };
  }
  async save(s) {
    if (this.db === false || !this.store || !this.store.saveSession) return;
    s.dirty = false;
    try { await this.store.saveSession(this.row(s)); this.db = true; s.saved = true; }
    catch (e) { s.dirty = true; if (missing(e)) { if (this.db !== false) console.log('[sessoes] banco sem a migração 0030: sessões só na memória'); this.db = false; } else console.error('[sessoes] gravar', e && e.message); }
  }
  async flush() { for (const s of [...this.live.values(), ...this.visits.values()]) if (s.dirty) await this.save(s); }
  // vids de quem já usou um apelido de teste (SextoSentro, DaSilva…): some do painel com "esconder testes"
  testVids(rows = []) {
    const out = new Set();
    const all = [...this.live.values(), ...this.visits.values(), ...this.recent, ...rows];
    for (const s of all) if (s.vid && TEST_NICKS.includes(String(s.nickname || '').toLowerCase())) out.add(s.vid);
    return out;
  }

  // ---------- R181 · FUNIL POR DIA ----------
  // abriu o jogo → carregou → passou da tela de entrada → jogou 1 partida → voltou outro dia (pessoas = navegadores, vid)
  async funnel({ days = 14, ads = false, hideTest = true } = {}) {
    const D = Math.max(1, Math.min(30, Number(days) || 14)), t = this.now();
    const since = new Date(t - D * 86400e3).toISOString();
    let rows = [], stored = false;
    if (this.db !== false && this.store && this.store.sessionsSince) {
      try { rows = await this.store.sessionsSince(since); stored = true; } catch (e) { if (missing(e)) this.db = false; else console.error('[sessoes] funil', e && e.message); }
    }
    const bySid = new Map(rows.map(r => [r.session_id, { sid: r.session_id, vid: r.vid || null, player: r.player, nickname: r.nickname || '', kind: r.kind,
      started: Date.parse(r.started_at), utm: r.utm || {}, flags: r.flags || {} }]));
    for (const s of [...this.live.values(), ...this.visits.values(), ...this.recent]) if (s.started >= Date.parse(since)) bySid.set(s.sid, s);
    const list = [...bySid.values()];
    const testVids = hideTest ? this.testVids(list) : new Set();
    const keyOf = s => s.vid || ('p:' + s.player);
    const isTest = s => hideTest && (TEST_NICKS.includes(String(s.nickname || '').toLowerCase()) || (s.vid && testVids.has(s.vid)));
    const adKeys = new Set(list.filter(s => s.utm && s.utm.ad).map(keyOf));
    const perDay = new Map();   // dia -> Map(key -> {loaded, passed, played})
    const daysOf = new Map();   // key -> Set(dias)
    for (const s of list) {
      if (isTest(s)) continue;
      const k = keyOf(s);
      if (ads && !adKeys.has(k)) continue;
      const d = dayBR(s.started);
      if (!perDay.has(d)) perDay.set(d, new Map());
      const m = perDay.get(d), cur = m.get(k) || { loaded: false, passed: false, played: false };
      const f = s.flags || {}, old = s.kind !== 'visitor' && !s.vid;   // sessão de antes da R181 (sem rota /t): já tinha passado da entrada
      cur.loaded = cur.loaded || !!f.loaded || s.kind !== 'visitor';
      cur.passed = cur.passed || !!f.passed || old;
      cur.played = cur.played || !!f.played;
      m.set(k, cur);
      if (!daysOf.has(k)) daysOf.set(k, new Set());
      daysOf.get(k).add(d);
    }
    const out = [...perDay.entries()].sort((a, b) => b[0].localeCompare(a[0])).map(([d, m]) => {
      let opened = 0, loaded = 0, passed = 0, played = 0, returned = 0;
      for (const [k, c] of m) {
        opened++; if (c.loaded) loaded++; if (c.passed) passed++; if (c.played) played++;
        if ([...daysOf.get(k)].some(x => x > d)) returned++;
      }
      return { day: d, opened, loaded, passed, played, returned };
    });
    return { days: out, persistent: stored, ads: !!ads, hide_test: !!hideTest, test_nicks: TEST_NICKS_RAW, window_days: D };
  }
  async prune() {
    if (this.db === false || !this.store || !this.store.pruneSessions) return;
    try { await this.store.pruneSessions(new Date(this.now() - KEEP_DAYS * 86400e3).toISOString()); } catch (e) { if (missing(e)) this.db = false; }
  }
}
module.exports = { Sessions, IN, OUT, UI_EVENTS, GRACE_MS, KEEP_DAYS };
