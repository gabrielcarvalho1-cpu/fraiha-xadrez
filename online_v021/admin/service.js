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
    this.audit = new AuditLog({ now, store: backend.store && backend.store.persistent ? backend.store : null });   // R110 · grava no banco (0015)
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
        if (path === '/admin/api/payments') return need('payments.read') && out(200, await this.payments(url.searchParams.get('status') || ''));
        if (path === '/admin/api/reports') return need('reports.read') && out(200, await this.reportsList(url.searchParams.get('status') || 'open'));
        if (path === '/admin/api/creators') return need('payments.read') && out(200, await this.creatorsList());   // R121
        return out(404, { error: 'not_found' });
      }
      if (req.method === 'POST') {
        const rm = /^\/admin\/api\/queues\/(ranked|casual)\/([a-z0-9_]+)$/.exec(path);
        if (rm) {
          if (!need('queues.write')) return;
          if (this.limited('write:' + admin.id, 20)) return out(429, { error: 'rate_limited' });
          let body;
          try { body = await readJson(req, 4096); }
          catch (e) { headers['Connection'] = 'close'; return out(e.code === 'too_large' ? 413 : 400, { error: e.code === 'too_large' ? 'body_too_large' : 'bad_json' }); }
          return this.setFamilyMode(admin, rm[1], rm[2], body, out);
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
        if (path === '/admin/api/payments/reconcile') {   // R103 · entrega pagamentos "pagos sem vantagem"
          if (!need('payments.write')) return;
          if (this.limited('write:' + admin.id, 20)) return out(429, { error: 'rate_limited' });
          const r = this.backend.payments ? await this.backend.payments.reconcile() : null;
          this.audit.record({ actor: admin, action: 'payments_reconcile', target: null, before: null, after: r, result: r && !r.missing ? 'ok' : 'unavailable', reason: '' });
          return out(200, { result: r || { missing: true } });
        }
        // R121 · criadores: cadastrar/editar e marcar comissão como paga
        const cp = /^\/admin\/api\/creators(?:\/([A-Z0-9]{3,20})\/pay)?$/.exec(path);
        if (cp) {
          if (!need('payments.write')) return;
          if (this.limited('write:' + admin.id, 20)) return out(429, { error: 'rate_limited' });
          let body;
          try { body = await readJson(req, 4096); }
          catch (e) { headers['Connection'] = 'close'; return out(e.code === 'too_large' ? 413 : 400, { error: e.code === 'too_large' ? 'body_too_large' : 'bad_json' }); }
          return cp[1] ? this.creatorPay(admin, cp[1], body || {}, out) : this.creatorSave(admin, body || {}, out);
        }
        // R104 · moderação: arquivar/resolver denúncia, suspender e tirar suspensão
        const rp = /^\/admin\/api\/reports\/([0-9a-fA-F-]{36})$/.exec(path);
        const sp = /^\/admin\/api\/players\/([0-9a-fA-F-]{36})\/(suspend|unsuspend)$/.exec(path);
        if (rp || sp) {
          if (!need('moderation.write')) return;
          if (this.limited('write:' + admin.id, 30)) return out(429, { error: 'rate_limited' });
          let body;
          try { body = await readJson(req, 4096); }
          catch (e) { headers['Connection'] = 'close'; return out(e.code === 'too_large' ? 413 : 400, { error: e.code === 'too_large' ? 'body_too_large' : 'bad_json' }); }
          return rp ? this.reportUpdate(admin, rp[1].toLowerCase(), body || {}, out) : this.suspendPlayer(admin, sp[1].toLowerCase(), sp[2], body || {}, out);
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
  // ---------------------------------------------------------------- R121 · CRIADORES
  async creatorsList() {
    const st = this.backend.store;
    if (!st || !st.listCreators) return { available: false };
    try {
      const [cs, links, sales] = await Promise.all([st.listCreators(), st.listCreatorLinks(), st.listCreatorSales('')]);
      const now = this.now();
      const items = cs.map(c => {
        const l = links.filter(x => x.code === c.code), s = sales.filter(x => x.code === c.code);
        const sum = (st2, k) => s.filter(x => st2.includes(x.status)).reduce((a, x) => a + (x[k] || 0), 0);
        return { ...c, players: l.length, active_players: l.filter(x => Date.parse(x.expires_at) > now).length,
          sales: s.filter(x => x.status !== 'cancelled').length, sold_cents: sum(['due', 'paid', 'refunded_after_paid'], 'amount_cents'),
          due_cents: sum(['due'], 'commission_cents'), paid_cents: sum(['paid', 'refunded_after_paid'], 'commission_cents'),
          clawback_cents: sum(['refunded_after_paid'], 'commission_cents'),
          recent: s.slice(0, 20).map(x => ({ created_at: x.created_at, product_id: x.product_id, amount_cents: x.amount_cents, commission_cents: x.commission_cents, status: x.status })) };
      });
      return { available: true, items };
    } catch (e) {
      if (/42P01|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message))) return { available: false, error: 'migration_0019_missing' };
      throw e;
    }
  }
  async creatorSave(admin, b, out) {
    const st = this.backend.store;
    if (!st || !st.upsertCreator) return out(503, { error: 'unavailable' });
    const code = String(b.code || '').trim().toUpperCase();
    if (!/^[A-Z0-9]{3,20}$/.test(code)) return out(400, { error: 'invalid_code' });
    const name = String(b.name || '').trim().slice(0, 60);
    if (!name) return out(400, { error: 'invalid_name' });
    const pct = Math.round(Number(b.pct)), gift = Math.round(Number(b.gift_crowns));
    if (!(pct >= 0 && pct <= 50) || !(gift >= 0 && gift <= 5000)) return out(400, { error: 'invalid_values' });
    const before = await st.getCreator(code).catch(() => null);
    const row = { code, name, pct, gift_crowns: gift, contact: String(b.contact || '').slice(0, 120), active: b.active !== false };
    const saved = await st.upsertCreator(row);
    this.audit.record({ actor: admin, action: before ? 'creator_update' : 'creator_create', target: { type: 'creator', id: code }, before, after: saved, result: 'ok', reason: String(b.reason || '') });
    return out(200, { creator: saved });
  }
  async creatorPay(admin, code, b, out) {
    const st = this.backend.store;
    if (!st || !st.payCreatorSales) return out(503, { error: 'unavailable' });
    const r = await st.payCreatorSales(code, String(b.reason || '').slice(0, 300));
    this.audit.record({ actor: admin, action: 'creator_pay', target: { type: 'creator', id: code }, before: null, after: r, result: 'ok', reason: String(b.reason || '') });
    return out(200, r);
  }
  // ---------------------------------------------------------------- R104 · DENÚNCIAS
  async reportsList(status) {
    const st = this.backend.store, { KIND_LABEL } = require('../moderation/reports');
    if (!['open', 'dismissed', 'actioned', ''].includes(status)) status = 'open';
    if (!st || !st.listReports) return { items: [], available: false };
    let rows;
    try { rows = await Q.withTimeout(st.listReports(status, 150)); }
    catch (e) { return { items: [], available: false, error: /42P01|PGRST205|does not exist|Could not find/.test(String(e.code) + ' ' + String(e.message)) ? 'migration_0013_missing' : 'query_error' }; }
    const ids = [...new Set(rows.flatMap(r => [r.reporter_id, r.reported_id]))];
    const prof = new Map();
    try { for (const p of await Q.withTimeout(st.getProfilesByIds(ids))) prof.set(p.user_id, p); } catch {}
    // situação da conta (suspensa?) vem do perfil completo — a lista pública não traz account_status
    const full = new Map();
    try { for (const id of [...new Set(rows.map(r => r.reported_id))].slice(0, 60)) { const p = await Q.withTimeout(st.getProfile(id)); if (p) full.set(id, p); } } catch {}
    const counts = new Map();
    for (const r of rows) counts.set(r.reported_id, (counts.get(r.reported_id) || 0) + 1);
    return { available: true, status, items: rows.map(r => {
      const rep = { ...(prof.get(r.reported_id) || {}), ...(full.get(r.reported_id) || {}) };
      return { report_id: r.report_id, kind: r.kind, kind_label: KIND_LABEL[r.kind] || r.kind, ref: r.ref, reason: r.reason, status: r.status, note: r.note || '',
        created_at: r.created_at, handled_by: r.handled_by || null, handled_at: r.handled_at || null,
        reporter: { user_id: r.reporter_id, nickname: (prof.get(r.reporter_id) || {}).nickname || (r.context && r.context.reporter_nickname) || '?' },
        reported: { user_id: r.reported_id, nickname: rep.nickname || (r.context && r.context.reported_nickname) || '?', account_status: rep.account_status || null, suspended_until: rep.suspended_until || null },
        reports_in_list: counts.get(r.reported_id) || 1,
        messages: (r.context && Array.isArray(r.context.messages)) ? r.context.messages : [] };
    }) };
  }
  async reportUpdate(admin, id, body, out) {
    const status = String(body.status || '');
    if (!['dismissed', 'actioned', 'open'].includes(status)) return out(400, { error: 'bad_status' });
    const st = this.backend.store;
    if (!st || !st.updateReport) return out(503, { error: 'unavailable' });
    const patch = { status, note: String(body.note || '').slice(0, 300), handled_by: admin.name || admin.id, handled_at: status === 'open' ? null : new Date(this.now()).toISOString() };
    let r;
    try { r = await Q.withTimeout(st.updateReport(id, patch)); } catch (e) { return out(500, { error: 'query_error' }); }
    if (!r) return out(404, { error: 'not_found' });
    this.audit.record({ actor: admin, action: 'report_' + status, target: { report_id: id, reported: r.reported_id }, before: null, after: patch, result: 'ok', reason: patch.note });
    return out(200, { report: r });
  }
  async suspendPlayer(admin, uid, action, body, out) {
    const R = this.backend.reports;
    if (!R) return out(503, { error: 'unavailable' });
    const reason = String(body.reason || '').trim().slice(0, 200);
    let r;
    if (action === 'suspend') {
      const days = body.days === null || body.days === 'indeterminado' ? null : Number(body.days);
      if (days !== null && !(Number.isInteger(days) && days >= 1 && days <= 3650)) return out(400, { error: 'bad_days' });
      if (!reason) return out(400, { error: 'reason_required' });
      r = await R.suspend(uid, days, reason);
    } else r = await R.unsuspend(uid);
    this.audit.record({ actor: admin, action: action === 'suspend' ? 'player_suspend' : 'player_unsuspend', target: { user_id: uid }, before: null,
      after: r.ok ? { until: r.until || null, days: body.days === undefined ? null : body.days } : null, result: r.ok ? 'ok' : r.error, reason });
    if (!r.ok) return out(r.error === 'not_found' ? 404 : (r.error === 'migration_0013_missing' ? 503 : 500), { error: r.error });
    if (r.ok && body.report_id && this.backend.store.updateReport) {
      try { await this.backend.store.updateReport(String(body.report_id), { status: 'actioned', note: reason, handled_by: admin.name || admin.id, handled_at: new Date(this.now()).toISOString() }); } catch {}
    }
    return out(200, { ok: true, until: r.until || null });
  }
  // ---------------------------------------------------------------- R103 · VENDAS
  async payments(status) {
    const st = this.backend.store, P = require('../payments/service');
    if (!st || !st.listPayments) return { items: [], available: false };
    let rows = [];
    try { rows = await Q.withTimeout(st.listPayments(null, 300)); } catch (e) { return { items: [], available: false, error: 'query_error' }; }
    if (status) rows = rows.filter(r => r.status === status);
    const names = new Map();
    try { for (const p of await Q.withTimeout(st.getProfilesByIds([...new Set(rows.map(r => r.user_id))]))) names.set(p.user_id, p.nickname); } catch {}
    const month = new Date(this.now()); month.setUTCDate(1); month.setUTCHours(3, 0, 0, 0);
    const sum = { paid_month_cents: 0, paid_month: 0, paid_total_cents: 0, paid_total: 0, refunded: 0, pending: 0, by_product: {} };
    for (const r of rows) {
      if (r.status === 'paid') {
        sum.paid_total++; sum.paid_total_cents += Number(r.amount_cents) || 0;
        if (r.paid_at && new Date(r.paid_at) >= month) { sum.paid_month++; sum.paid_month_cents += Number(r.amount_cents) || 0; }
        sum.by_product[r.product_id] = (sum.by_product[r.product_id] || 0) + 1;
      } else if (r.status === 'refunded') sum.refunded++;
      else if (r.status === 'pending') sum.pending++;
    }
    return { available: true, summary: sum, items: rows.map(r => ({ ...r, nickname: names.get(r.user_id) || null, title: (P.PRODUCTS[r.product_id] || {}).title || r.product_id })) };
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
      out.push({ ...ctl[f], has_queue: !!q, ...(ModeControls.hasModes(f) ? { modes: this.modeRows(f, q || [], ms), boot_default: this.env[ModeControls.bootEnv(f)] ? ModeControls.bootEnv(f) : 'todos abertos' } : {}),
        waiting: q ? real(q.length, '') : none('sem fila pública: partidas começam por convite'),
        longest_wait_ms: q ? (q.length ? real(Math.max(...q.map(e => e.wait_ms))) : real(null, 'fila vazia')) : none('sem fila'),
        avg_wait_ms: q ? (w.samples ? partial(w.avg_ms, `${w.samples} pareamentos na última hora`) : none('sem pareamentos na última hora')) : none('sem fila'),
        active_matches: real(ms.length), active_players: real(ms.reduce((n, m) => n + m.players.filter(p => p.uid).length, 0)),
        by_mode: q ? Object.entries(q.reduce((o, e) => (o[e.mode] = (o[e.mode] || 0) + 1, o), {})).map(([mode, n]) => ({ mode, waiting: n })) : [] });
    }
    return { at: new Date(this.now()).toISOString(), rule: 'Desativar impede novas entradas e novos pareamentos; quem estava na fila sai com aviso; partidas em andamento continuam.', persistent: false, queues: out };
  }
  // Por ritmo (filas reais do servidor): status, na fila, maior espera, tempo médio (1 h), partidas e jogadores ativos.
  modeRows(family, q, ms) {
    return this.controls.modesSnapshot(family).map(m => {
      const mq = q.filter(e => e.mode === m.mode), mm = ms.filter(x => x.mode === m.mode), w = this.metrics.avgWait(family, 3600e3, m.mode);
      return { ...m, waiting: mq.length, longest_wait_ms: mq.length ? Math.max(...mq.map(e => e.wait_ms)) : null,
        avg_wait_ms: w.samples ? w.avg_ms : null, avg_samples: w.samples,
        active_matches: mm.length, active_players: mm.reduce((n, x) => n + x.players.filter(p => p.uid).length, 0) };
    });
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
  // Ritmo do Ranked/Casual (3/5/10/20 min): o jogo deixa de MOSTRAR o ritmo fechado; quem esperava nele sai da fila.
  setFamilyMode(admin, family, mode, body, out) {
    if (!ModeControls.modeIds(family).includes(mode)) return out(404, { error: 'unknown_queue' });
    if (!body || typeof body !== 'object' || Array.isArray(body)) return out(400, { error: 'bad_request', detail: 'corpo JSON obrigatório' });
    const extra = Object.keys(body).filter(k => !['enabled', 'reason', 'confirm'].includes(k));
    if (extra.length) return out(400, { error: 'bad_request', detail: 'campos não permitidos: ' + extra.slice(0, 5).join(', ') });
    if (typeof body.enabled !== 'boolean') return out(400, { error: 'bad_request', detail: 'enabled (boolean) obrigatório' });
    const reason = typeof body.reason === 'string' ? body.reason.trim() : '';
    if (reason.length < 3) return out(400, { error: 'reason_required' });
    if (String(body.confirm || '') !== mode) return out(400, { error: 'confirmation_required', detail: `confirm deve ser "${mode}"` });
    const snap = () => this.controls.modesSnapshot(family).find(m => m.mode === mode);
    const open = () => this.controls.openModes(family);
    const cur = snap();
    const action = body.enabled ? 'queue.mode_enable' : 'queue.mode_disable';
    if (cur.enabled === body.enabled) {
      const a = this.audit.record({ actor: admin, action, target: { family, mode }, before: { enabled: cur.enabled }, after: { enabled: cur.enabled }, result: 'noop', reason });
      return out(200, { mode: cur, open_modes: open(), changed: false, audit_id: a.id });
    }
    this.backend.lastPurged = 0;
    const { before, after } = this.controls.setMode(family, mode, body.enabled, { id: admin.id, name: admin.name }, reason);
    const a = this.audit.record({ actor: admin, action, target: { family, mode }, before: { enabled: before.enabled }, after: { enabled: after.enabled }, result: 'ok', reason,
      meta: body.enabled ? { open_modes: open() } : { removed_from_queue: this.backend.lastPurged || 0, open_modes: open() } });
    return out(200, { mode: snap(), open_modes: open(), changed: true, audit_id: a.id });
  }
  setRankedMode(admin, mode, body, out) { return this.setFamilyMode(admin, 'ranked', mode, body, out); }
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
