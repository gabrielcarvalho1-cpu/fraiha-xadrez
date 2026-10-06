'use strict';
// FRAIHA Admin · API HTTP (/admin/api/*) no MESMO processo do servidor do jogo, porque o estado ao vivo
// (online, filas, partidas) vive na memória dessa instância. Separada do protocolo WebSocket do jogo.
// Segurança: Bearer token do Supabase Auth (verificado no servidor) + allowlist de admins no ambiente do
// servidor (FRAIHA_ADMIN_USERS) + permissão por rota + rate limit + CORS por allowlist + audit log.
// Sem cookies → sem CSRF. Sem segredo no Admin. Sem a variável FRAIHA_ADMIN_USERS → API desligada (503).
const { AdminAccess } = require('./access');
const { AuditLog } = require('./audit');
const { Metrics } = require('./metrics');
const { ModeControls } = require('./controls');
const { liveSnapshot, whereIs, isGuest } = require('./live');
const Q = require('./queries');
const Ent = require('./entitlements');
const { UUID_RE } = require('../accounts/store');
const pkg = (() => { try { return require('../../package.json'); } catch { return {}; } })();

const real = (value, note = '') => ({ value, status: 'real', note });
const partial = (value, note) => ({ value, status: 'partial', note });
const none = (note) => ({ value: null, status: 'unavailable', note });
const ENVS = ['local', 'dev', 'staging', 'production'];

class AdminService {
  constructor({ backend, env = process.env, now = () => Date.now(), metrics = null, autostart = true }) {
    this.backend = backend; this.env = env; this.now = now;
    this.access = new AdminAccess({ backend, env });
    this.audit = new AuditLog({ now });
    this.controls = backend.modeControls || (backend.modeControls = new ModeControls({ now }));
    this.metrics = metrics || new Metrics({ backend, now, autostart });
    backend.adminMetrics = this.metrics;
    this.origins = String(env.FRAIHA_ADMIN_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean);
    const e = String(env.FRAIHA_ENV || '').toLowerCase();
    this.envName = ENVS.includes(e) ? e : (backend.kind === 'dev' ? 'dev' : 'unknown');
    this.hits = new Map();   // rate limit: ip -> {sec window}
    this.startedAt = now();
  }
  // ---------------------------------------------------------------- HTTP
  owns(req) { return String(req.url || '').startsWith('/admin/api/') || req.url === '/admin/api'; }
  ip(req) { return String((req.socket && req.socket.remoteAddress) || 'x'); }
  limited(key, max, windowMs = 60e3) {
    const t = this.now(); let h = this.hits.get(key);
    if (!h || t - h.start > windowMs) { h = { start: t, n: 0 }; this.hits.set(key, h); }
    if (this.hits.size > 5000) this.hits.clear();
    return ++h.n > max;
  }
  cors(req, headers) {
    const o = String(req.headers.origin || '');
    if (!o) return true;
    const devLocal = (this.envName === 'local' || this.envName === 'dev') && /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(o);
    if (!devLocal && !this.origins.includes(o)) return false;
    headers['Access-Control-Allow-Origin'] = o; headers['Vary'] = 'Origin';
    headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type';
    headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS';
    headers['Access-Control-Max-Age'] = '600';
    return true;
  }
  async handle(req, res) {
    const headers = { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' };
    const out = (status, body) => { res.writeHead(status, headers); res.end(JSON.stringify(body)); };
    try {
      if (!this.cors(req, headers)) return out(403, { error: 'origin_not_allowed' });
      if (req.method === 'OPTIONS') { res.writeHead(204, headers); return res.end(); }
      if (this.limited('ip:' + this.ip(req), 240)) return out(429, { error: 'rate_limited' });
      const auth = await this.access.authenticate(req);
      if (!auth.ok) return out(auth.status, { error: auth.code });
      const admin = auth.admin;
      const url = new URL(req.url, 'http://x');
      const path = url.pathname.replace(/\/+$/, '');
      const need = perm => { if (!AdminAccess.can(admin, perm)) { out(403, { error: 'forbidden', need: perm }); return false; } return true; };
      if (req.method === 'GET') {
        if (path === '/admin/api/session') return out(200, { admin: { id: admin.id, name: admin.name, role: admin.role, perms: admin.perms }, env: this.envName });
        if (path === '/admin/api/overview') return need('dashboard.read') && out(200, await this.overview());
        if (path === '/admin/api/live') return need('live.read') && out(200, this.live(url.searchParams.get('range')));
        if (path === '/admin/api/queues') return need('queues.read') && out(200, this.queues());
        if (path === '/admin/api/matches') return need('matches.read') && out(200, this.matches());
        if (path === '/admin/api/players') return need('players.read') && out(200, await this.players(url.searchParams.get('q'), url.searchParams.get('limit')));
        if (path === '/admin/api/online') return need('players.read') && out(200, await this.onlinePlayers());
        const pm = /^\/admin\/api\/players\/([0-9a-fA-F-]{36})$/.exec(path);
        if (pm) { if (!need('players.read')) return; const d = await this.player(pm[1].toLowerCase()); return d ? out(200, d) : out(404, { error: 'not_found' }); }
        if (path === '/admin/api/audit') return need('audit.read') && out(200, { persistent: this.audit.persistent, items: this.audit.list({ limit: url.searchParams.get('limit'), action: url.searchParams.get('action') || '' }) });
        if (path === '/admin/api/system') return need('system.read') && out(200, this.system());
        return out(404, { error: 'not_found' });
      }
      if (req.method === 'POST') {
        const rm = /^\/admin\/api\/queues\/ranked\/([a-z0-9_]+)$/.exec(path);
        if (rm) {
          if (!need('queues.write')) return;
          if (this.limited('write:' + admin.id, 20)) return out(429, { error: 'rate_limited' });
          let body;
          try { body = await readJson(req, 4096); }
          catch (e) { headers['Connection'] = 'close'; return out(e.code === 'too_large' ? 413 : 400, { error: e.code === 'too_large' ? 'body_too_large' : 'bad_json' }); }
          return this.setRankedMode(admin, rm[1], body, out);
        }
        const qm = /^\/admin\/api\/queues\/([a-z]+)$/.exec(path);
        if (qm) {
          if (!need('queues.write')) return;
          if (this.limited('write:' + admin.id, 20)) return out(429, { error: 'rate_limited' });
          let body;
          try { body = await readJson(req, 4096); }
          catch (e) { headers['Connection'] = 'close'; return out(e.code === 'too_large' ? 413 : 400, { error: e.code === 'too_large' ? 'body_too_large' : 'bad_json' }); }
          return this.setQueue(admin, qm[1], body, out);
        }
        const em = /^\/admin\/api\/players\/([0-9a-fA-F-]{36})\/(club|founder)$/.exec(path);
        if (em) {
          if (!need('entitlements.write')) return;
          if (this.limited('write:' + admin.id, 20)) return out(429, { error: 'rate_limited' });
          let body;
          try { body = await readJson(req, 4096); }
          catch (e) { headers['Connection'] = 'close'; return out(e.code === 'too_large' ? 413 : 400, { error: e.code === 'too_large' ? 'body_too_large' : 'bad_json' }); }
          const r = await Ent.apply({ backend: this.backend, audit: this.audit, admin, kind: em[2], uid: em[1].toLowerCase(), body, now: this.now() });
          return out(r.status, r.body);
        }
        return out(404, { error: 'not_found' });
      }
      return out(405, { error: 'method_not_allowed' });
    } catch (e) {
      console.error('[admin] api error', e && e.message);
      return out(500, { error: 'server_error' });
    }
  }
  // ---------------------------------------------------------------- dados
  async overview() {
    const now = this.now(), s = liveSnapshot(this.backend, now);
    const since = new Date(this.metrics.startedAt).toISOString();
    const acc = await Q.accountCounts(this.backend.store, now);
    const w1h = this.metrics.avgWait(null, 3600e3);
    const started = this.metrics.today('started'), finished = this.metrics.today('finished');
    const byFam = { ranked: 0, casual: 0, xeque: 0, marcha: 0 }; for (const m of s.matches) byFam[m.family]++;
    return {
      at: new Date(now).toISOString(), env: this.envName, tracking_since: since,
      cards: {
        online_now: real(s.online.length, `${s.accounts} contas + ${s.guests} convidados conectados`),
        in_match: real(s.inMatch.size, 'jogadores humanos em partida ativa (Ranked, Casual, XEQUE, MARCHA)'),
        lobby: real(s.lobby, 'conectados fora de fila e de partida (Home/menus)'),
        in_queue: real(s.inQueue.size, 'filas Ranked + Casual (XEQUE/MARCHA não têm fila: só convite)'),
        active_matches: real(s.matches.length, Object.entries(byFam).map(([k, v]) => `${k} ${v}`).join(' · ')),
        registered_users: acc.registered,
        new_users_today: acc.new_today,
        peak_online_today: partial(this.metrics.peak.today, `amostragem a cada ${Math.round(this.metrics.everyMs / 1000)} s · zera quando o servidor reinicia`),
        avg_queue_time: w1h.samples ? partial(w1h.avg_ms, `média de ${w1h.samples} pareamentos na última hora`) : none('nenhum pareamento registrado na última hora'),
        matches_started_today: partial(started.total, 'desde o último reinício do servidor'),
        matches_finished_today: partial(finished.total, 'desde o último reinício do servidor'),
        matches_abandoned_today: partial(finished.by_reason.abandon || 0, 'término por abandono · desde o último reinício do servidor'),
        voice_users: real(s.voice.size, 'jogadores com voz ativa agora'),
        unique_players_today: none('PRECISA INSTRUMENTAÇÃO: registro de sessões (migration proposta)'),
        returning_players: none('PRECISA INSTRUMENTAÇÃO: histórico de sessões'),
        platform: none('PRECISA INSTRUMENTAÇÃO: o cliente ainda não informa a plataforma (Web/Windows/Android/Steam)'),
        reconnects_errors: none('PRECISA INSTRUMENTAÇÃO: contadores de reconexão/erro'),
      },
    };
  }
  live(range) {
    const ms = { '1h': 3600e3, '6h': 6 * 3600e3, '24h': 86400e3 }[range] || 3600e3;
    const s = liveSnapshot(this.backend, this.now());
    const byFam = { ranked: { queue: 0, players: 0, matches: 0 }, casual: { queue: 0, players: 0, matches: 0 }, xeque: { queue: null, players: 0, matches: 0 }, marcha: { queue: null, players: 0, matches: 0 } };
    for (const f of ['ranked', 'casual']) byFam[f].queue = s.queue[f].length;
    for (const m of s.matches) { byFam[m.family].matches++; byFam[m.family].players += m.players.filter(p => p.uid).length; }
    const longest = Math.max(0, ...[...s.queue.ranked, ...s.queue.casual].map(e => e.wait_ms));
    return { at: new Date(this.now()).toISOString(), tracking_since: new Date(this.metrics.startedAt).toISOString(), sample_every_ms: this.metrics.everyMs,
      now: { online: s.online.length, lobby: s.lobby, in_queue: s.inQueue.size, in_match: s.inMatch.size, matches: s.matches.length, voice: s.voice.size, longest_wait_ms: s.inQueue.size ? longest : null },
      by_family: byFam, peak: this.metrics.peak, series: this.metrics.history(ms),
      alerts: this.alerts(s, longest) };
  }
  alerts(s, longest) {
    const a = [];
    for (const f of ModeControls.families()) if (!this.controls.isOpen(f)) a.push({ level: 'warn', text: `${ModeControls.label(f)} DESATIVADO` });
    if (s.inQueue.size && longest > 120e3) a.push({ level: 'warn', text: `espera na fila acima de ${Math.round(longest / 60e3)} min` });
    if (this.backend.kind === 'disabled') a.push({ level: 'error', text: 'servidor sem contas (Supabase não configurado)' });
    return a;
  }
  queues() {
    const s = liveSnapshot(this.backend, this.now()), ctl = this.controls.snapshot(), out = [];
    for (const f of ModeControls.families()) {
      const q = s.queue[f] || null, ms = s.matches.filter(m => m.family === f);
      const w = this.metrics.avgWait(f, 3600e3);
      out.push({ ...ctl[f], has_queue: !!q, ...(f === 'ranked' ? { modes: this.controls.rankedModesSnapshot().map(m => ({ ...m, waiting: (q || []).filter(e => e.mode === m.mode).length })), boot_default: this.env.FRAIHA_RANKED_MODES_OPEN ? 'FRAIHA_RANKED_MODES_OPEN' : 'todos abertos' } : {}),
        waiting: q ? real(q.length, '') : none('sem fila pública: partidas começam por convite'),
        longest_wait_ms: q ? (q.length ? real(Math.max(...q.map(e => e.wait_ms))) : real(null, 'fila vazia')) : none('sem fila'),
        avg_wait_ms: q ? (w.samples ? partial(w.avg_ms, `${w.samples} pareamentos na última hora`) : none('sem pareamentos na última hora')) : none('sem fila'),
        active_matches: real(ms.length), active_players: real(ms.reduce((n, m) => n + m.players.filter(p => p.uid).length, 0)),
        by_mode: q ? Object.entries(q.reduce((o, e) => (o[e.mode] = (o[e.mode] || 0) + 1, o), {})).map(([mode, n]) => ({ mode, waiting: n })) : [] });
    }
    return { at: new Date(this.now()).toISOString(), rule: 'Desativar impede novas entradas e novos pareamentos; quem estava na fila sai com aviso; partidas em andamento continuam.', persistent: false, queues: out };
  }
  matches() {
    const now = this.now(), s = liveSnapshot(this.backend, now);
    return { at: new Date(now).toISOString(), recent_finished: none('PRECISA BACKEND/MIGRATION: só o Ranked grava partidas (tabela matches); Casual/XEQUE/MARCHA não têm histórico'),
      active: s.matches.map(m => ({ ...m, duration_ms: m.started_at ? Math.max(0, now - m.started_at) : null,
        players: m.players.map(p => ({ ...p, voice: p.uid ? s.voice.has(p.uid) : false, platform: null })) })) };
  }
  async players(q, limit) {
    const st = this.backend.store;
    if (!st) return { items: [], source: none('servidor sem armazenamento de contas') };
    const rows = await Q.searchPlayers(st, q, limit);
    const ids = rows.map(r => r.user_id), ents = await Q.entitlementsOf(st, ids), s = liveSnapshot(this.backend, this.now());
    return { query: String(q || ''), email_search: none('PRECISA BACKEND: busca por e-mail exige Supabase Auth Admin (dado pessoal; proposta para V2)'),
      entitlements_read: ents.ok ? 'ok' : ents.error,
      items: rows.map(r => {
        // ents.ok=false → undefined (DESCONHECIDO); linha ausente → null (legítimo: sem benefício)
        const e = ents.ok ? (ents.map.get(r.user_id) || null) : undefined;
        return { user_id: r.user_id, nickname: r.nickname, avatar_id: r.avatar_id, account_status: r.account_status || null,
          created_at: r.created_at || null, last_login_at: r.last_login_at || null, where: whereIs(this.backend, r.user_id, s),
          club: Q.clubStatus(e, this.now()), founder: e === undefined ? null : !!(e && e.is_founder), platform: null };
      }) };
  }
  // Jogadores ONLINE agora (presença real do servidor) + estado real de Clube/Fundador.
  async onlinePlayers() {
    const now = this.now(), s = liveSnapshot(this.backend, now), st = this.backend.store;
    const ids = s.online.filter(u => !isGuest(u) && UUID_RE.test(u)).slice(0, 200);
    const base = { at: new Date(now).toISOString(), online_total: s.online.length, guests: s.guests, truncated: s.accounts > ids.length };
    if (!st) return { ...base, items: [], entitlements_read: 'unavailable' };
    let profiles = new Map(), profiles_read = 'ok';
    try { for (const p of await Q.withTimeout(st.getProfilesByIds(ids))) profiles.set(p.user_id, p); } catch { profiles_read = 'query_error'; }
    const ents = await Q.entitlementsOf(st, ids);
    const items = ids.map(uid => {
      const p = profiles.get(uid) || null;
      const e = ents.ok ? (ents.map.get(uid) || null) : undefined;
      return { user_id: uid, nickname: p ? p.nickname : null, has_profile: !!p || profiles_read !== 'ok', avatar_url: p && typeof p.avatar_url === 'string' && /^https:\/\/[a-z0-9-]+\.supabase\.co\//.test(p.avatar_url) ? p.avatar_url : null,
        avatar_id: p ? p.avatar_id || null : null, where: whereIs(this.backend, uid, s), ent: Ent.view(e, now) };
    }).sort((a, b) => String(a.nickname || '~').localeCompare(String(b.nickname || '~')));
    return { ...base, profiles_read, entitlements_read: ents.ok ? 'ok' : ents.error, items };
  }
  async player(uid) {
    const st = this.backend.store; if (!st) return null;
    const d = await Q.playerDetail(st, uid); if (!d) return null;
    const ok = d.entitlements.ok, e = ok ? d.entitlements.value : undefined;
    const why = ok ? '' : (d.entitlements.error === 'timeout' ? 'ERRO DE CONSULTA: tempo esgotado' : 'ERRO DE CONSULTA');
    const unk = () => ({ value: null, status: 'unavailable', note: why });
    return { profile: d.profile, ranked: d.ranked, modes: d.modes, entitlements_read: ok ? 'ok' : d.entitlements.error,
      where: whereIs(this.backend, uid), platform: none('PRECISA INSTRUMENTAÇÃO'),
      club: { status: Q.clubStatus(e, this.now()), read_error: ok ? null : why, plan: none('planos ainda não definidos'),
        source: !ok ? unk() : e && e.club_source ? real(e.club_source) : none('sem registro'),
        started: none('PRECISA MIGRATION: início da assinatura não é registrado'),
        expires_at: !ok ? unk() : e && e.club_expires_at ? real(e.club_expires_at) : none('sem data'),
        renewal: none('PRECISA BACKEND'), note: none('PRECISA MIGRATION: observação administrativa') },
      founder: { ...(ok ? real(!!(e && e.is_founder), e ? '' : 'sem registro de benefício') : unk()), since: ok && e && e.founder_since ? e.founder_since : null, edition: none('ainda não definido') },
      ent: Ent.view(e, this.now()) };
  }
  system() {
    return { env: this.envName, backend_kind: this.backend.kind, server_version: pkg.version || null,
      commit: this.env.RENDER_GIT_COMMIT ? String(this.env.RENDER_GIT_COMMIT).slice(0, 12) : null,
      uptime_ms: this.now() - this.startedAt, tracking_since: new Date(this.metrics.startedAt).toISOString(),
      voice_configured: !!(this.backend.voice && this.backend.voice.configured && this.backend.voice.configured()),
      audit_persistent: this.audit.persistent, controls_persistent: false, admins: this.access.admins.size };
  }
  // ---------------------------------------------------------------- ação real
  // Ritmo do Ranked (3/5/10/20 min): o jogo deixa de MOSTRAR o ritmo fechado; quem esperava nele sai da fila.
  setRankedMode(admin, mode, body, out) {
    if (!ModeControls.rankedModeIds().includes(mode)) return out(404, { error: 'unknown_queue' });
    if (!body || typeof body !== 'object' || Array.isArray(body)) return out(400, { error: 'bad_request', detail: 'corpo JSON obrigatório' });
    const extra = Object.keys(body).filter(k => !['enabled', 'reason', 'confirm'].includes(k));
    if (extra.length) return out(400, { error: 'bad_request', detail: 'campos não permitidos: ' + extra.slice(0, 5).join(', ') });
    if (typeof body.enabled !== 'boolean') return out(400, { error: 'bad_request', detail: 'enabled (boolean) obrigatório' });
    const reason = typeof body.reason === 'string' ? body.reason.trim() : '';
    if (reason.length < 3) return out(400, { error: 'reason_required' });
    if (String(body.confirm || '') !== mode) return out(400, { error: 'confirmation_required', detail: `confirm deve ser "${mode}"` });
    const snap = () => this.controls.rankedModesSnapshot().find(m => m.mode === mode);
    const cur = snap();
    const action = body.enabled ? 'queue.mode_enable' : 'queue.mode_disable';
    if (cur.enabled === body.enabled) {
      const a = this.audit.record({ actor: admin, action, target: { family: 'ranked', mode }, before: { enabled: cur.enabled }, after: { enabled: cur.enabled }, result: 'noop', reason });
      return out(200, { mode: cur, open_modes: this.backend.rankedModesOpen(), changed: false, audit_id: a.id });
    }
    this.backend.lastPurged = 0;
    const { before, after } = this.controls.setRankedMode(mode, body.enabled, { id: admin.id, name: admin.name }, reason);
    const a = this.audit.record({ actor: admin, action, target: { family: 'ranked', mode }, before: { enabled: before.enabled }, after: { enabled: after.enabled }, result: 'ok', reason,
      meta: body.enabled ? { open_modes: this.backend.rankedModesOpen() } : { removed_from_queue: this.backend.lastPurged || 0, open_modes: this.backend.rankedModesOpen() } });
    return out(200, { mode: snap(), open_modes: this.backend.rankedModesOpen(), changed: true, audit_id: a.id });
  }
  setQueue(admin, family, body, out) {
    if (!ModeControls.families().includes(family)) return out(404, { error: 'unknown_queue' });
    if (!body || typeof body.enabled !== 'boolean') return out(400, { error: 'bad_request', detail: 'enabled (boolean) obrigatório' });
    const reason = String(body.reason || '').trim();
    if (reason.length < 3) return out(400, { error: 'reason_required' });
    if (String(body.confirm || '') !== family) return out(400, { error: 'confirmation_required', detail: `confirm deve ser "${family}"` });
    const cur = this.controls.get(family);
    if (cur.enabled === body.enabled) {
      const a = this.audit.record({ actor: admin, action: body.enabled ? 'queue.enable' : 'queue.disable', target: { family }, before: { enabled: cur.enabled }, after: { enabled: cur.enabled }, result: 'noop', reason });
      return out(200, { control: this.controls.snapshot()[family], changed: false, audit_id: a.id });
    }
    const { before, after } = this.controls.set(family, body.enabled, { id: admin.id, name: admin.name }, reason);
    const a = this.audit.record({ actor: admin, action: body.enabled ? 'queue.enable' : 'queue.disable', target: { family },
      before: { enabled: before.enabled }, after: { enabled: after.enabled }, result: 'ok', reason, meta: body.enabled ? {} : { removed_from_queue: this.backend.lastPurged || 0 } });
    return out(200, { control: this.controls.snapshot()[family], changed: true, audit_id: a.id });
  }
}

function readJson(req, max) {
  return new Promise((resolve, reject) => {
    let raw = '';
    let over = false;
    req.on('data', d => { if (over) return; raw += d; if (raw.length > max) { over = true; raw = ''; const e = new Error('too_large'); e.code = 'too_large'; reject(e); } });
    req.on('end', () => { try { resolve(JSON.parse(raw || 'null')); } catch (e) { reject(e); } });
    req.on('error', reject);
  });
}
module.exports = { AdminService };
