'use strict';
// FRAIHA Admin · CLUBE FRAIHA e FUNDADOR — escrita administrativa SERVER-SIDE na tabela que já existe
// (public.entitlements, migração 0005). Nenhuma migration nova.
//
// Modelo real (0005):
//   is_founder bool · founder_since timestamptz          → Fundador: PERMANENTE (sem validade)
//   club_active bool · club_expires_at timestamptz|null · club_source text  → Clube (null = sem expiração)
//   updated_at timestamptz                               → versão da linha (concorrência otimista)
// O jogo lê pelo acct_state (store.getEntitlements: ativo = club_active && (sem data || data futura)).
//
// Clube e Fundador são INDEPENDENTES aqui: conceder/revogar Fundador NÃO mexe no Clube (o bônus de 30 dias
// de Clube é regra da COMPRA do pacote — função 0007 — e continua só nos pagamentos, que não são tocados).
// Origem administrativa do Clube: 'manual' (valor já previsto na 0005).
//
// Segurança: só ações explícitas (grant/change/revoke), payload estrito (chave desconhecida = 400), motivo
// obrigatório, confirmação = UUID alvo, versão esperada (UI desatualizada / clique duplo não aplica 2×),
// alvo precisa ter perfil (FK), datas validadas. A permissão é verificada ANTES (service.js).
const { UUID_RE } = require('../accounts/store');
const Q = require('./queries');

const DAY = 86400e3;
const DURATION_DAYS = { 7: 7, 30: 30, 90: 90, 365: 365 };
const DURATIONS = ['7', '30', '90', '365', 'none', 'custom'];
const MAX_CUSTOM_MS = 10 * 365 * DAY;
const MIN_AHEAD_MS = 60e3;
const ACTIONS = { club: ['grant', 'change', 'revoke'], founder: ['grant', 'revoke'] };
const KEYS = { club: ['action', 'duration', 'expires_at', 'reason', 'confirm', 'expect_version'], founder: ['action', 'reason', 'confirm', 'expect_version'] };
const AUDIT = { club: { grant: 'clube_grant', change: 'clube_change', revoke: 'clube_revoke' }, founder: { grant: 'founder_grant', revoke: 'founder_revoke' } };

const fail = (status, error, detail) => ({ status, error, detail });
const version = e => (e ? String(e.updated_at || '') : null);

// Estado público (o mesmo para lista online, perfil e resposta das ações). e: linha | null | undefined(erro)
function view(e, now = Date.now()) {
  if (e === undefined) return null;
  const status = Q.clubStatus(e, now);
  return {
    version: version(e),
    club: { status, active: status === 'ATIVO', expires_at: e && e.club_expires_at || null, source: e && e.club_source || null },
    founder: { value: !!(e && e.is_founder), since: e && e.founder_since || null },
  };
}
const auditState = v => v && { club: v.club.status, club_expires_at: v.club.expires_at, club_source: v.club.source, founder: v.founder.value, founder_since: v.founder.since };

// Valida o corpo. → { ok:true, action, reason, expires } | fail(...)
function validate(kind, uid, body, now = Date.now()) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return fail(400, 'bad_request', 'corpo JSON obrigatório');
  const extra = Object.keys(body).filter(k => !KEYS[kind].includes(k));
  if (extra.length) return fail(400, 'bad_request', 'campos não permitidos: ' + extra.slice(0, 5).join(', '));
  if (!ACTIONS[kind].includes(body.action)) return fail(400, 'invalid_action', 'ação: ' + ACTIONS[kind].join(' | '));
  if (typeof body.reason !== 'string' || body.reason.trim().length < 3) return fail(400, 'reason_required');
  if (body.reason.length > 300) return fail(400, 'bad_request', 'motivo até 300 caracteres');
  if (body.confirm !== uid) return fail(400, 'confirmation_required', 'confirm deve ser o UUID do jogador');
  if (!('expect_version' in body) || !(body.expect_version === null || typeof body.expect_version === 'string')) return fail(400, 'bad_request', 'expect_version (texto ou null) obrigatório');
  const out = { ok: true, action: body.action, reason: body.reason.trim(), expires: undefined };
  const needsTerm = kind === 'club' && (body.action === 'grant' || body.action === 'change');
  if (!needsTerm) {
    if (body.duration !== undefined || body.expires_at !== undefined) return fail(400, 'bad_request', 'esta ação não aceita validade');
    return out;
  }
  if (!DURATIONS.includes(body.duration)) return fail(400, 'invalid_duration', 'validade: ' + DURATIONS.join(' | '));
  if (body.duration === 'custom') {
    if (typeof body.expires_at !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$/.test(body.expires_at)) return fail(400, 'invalid_date', 'data ISO com fuso obrigatória');
    const t = Date.parse(body.expires_at);
    if (!Number.isFinite(t)) return fail(400, 'invalid_date');
    if (t < now + MIN_AHEAD_MS) return fail(400, 'invalid_date', 'a data precisa ser no futuro');
    if (t > now + MAX_CUSTOM_MS) return fail(400, 'invalid_date', 'no máximo 10 anos');
    out.expires = new Date(t).toISOString();
  } else {
    if (body.expires_at !== undefined) return fail(400, 'bad_request', 'expires_at só com duration=custom');
    out.expires = body.duration === 'none' ? null : new Date(now + DURATION_DAYS[body.duration] * DAY).toISOString();
  }
  return out;
}

// O que muda. → { patch } | { noop:true } | fail(...)
function plan(kind, v, action, expires, nowIso) {
  if (kind === 'club') {
    if (action === 'grant') return v.club.active ? fail(409, 'already_active', 'Clube já ATIVO: use ALTERAR') : { patch: { club_active: true, club_expires_at: expires, club_source: 'manual' } };
    if (action === 'change') return v.club.active ? { patch: { club_active: true, club_expires_at: expires, club_source: 'manual' } } : fail(409, 'not_active', 'Clube não está ATIVO: use CONCEDER');
    if (action === 'revoke') return v.club.active ? { patch: { club_active: false, club_expires_at: null } } : { noop: true };
  }
  if (kind === 'founder') {
    if (action === 'grant') return v.founder.value ? { noop: true } : { patch: { is_founder: true, founder_since: nowIso } };
    if (action === 'revoke') return v.founder.value ? { patch: { is_founder: false, founder_since: null } } : { noop: true };
  }
  return fail(400, 'invalid_action');
}

// ---------------------------------------------------------------- armazenamento (Supabase ou memória DEV)
async function readRow(st, uid) {
  const r = await Q.entitlementsOf(st, [uid]);
  if (!r.ok) { const e = new Error('entitlements_read'); e.code = r.error; throw e; }
  return r.map.get(uid) || null;
}
// Grava SÓ se a linha ainda estiver na versão lida (senão → null = conflito). Devolve a linha nova.
async function writeRow(st, uid, before, patch, nowIso) {
  if (Q.isSupabase(st)) {
    if (!before) {
      const rows = await Q.withTimeout(st.req('/entitlements', { method: 'POST', headers: { Prefer: 'resolution=ignore-duplicates,return=representation' },
        body: JSON.stringify({ user_id: uid, ...patch, updated_at: nowIso }) }));
      return Array.isArray(rows) && rows[0] ? rows[0] : null;
    }
    const rows = await Q.withTimeout(st.req('/entitlements?user_id=eq.' + encodeURIComponent(uid) + '&updated_at=eq.' + encodeURIComponent(before.updated_at),
      { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ ...patch, updated_at: nowIso }) }));
    return Array.isArray(rows) && rows[0] ? rows[0] : null;
  }
  st.entitlements = st.entitlements || new Map();
  const cur = st.entitlements.get(uid) || null;
  if (version(cur) !== version(before)) return null;
  const row = { ...(cur || { is_founder: false, founder_since: null, club_active: false, club_expires_at: null, club_source: null }), ...patch, updated_at: nowIso };
  st.entitlements.set(uid, row);
  return { user_id: uid, ...row };
}

// Fluxo completo de uma ação. Devolve { status, body } para o handler HTTP.
async function apply({ backend, audit, admin, kind, uid, body, now = Date.now() }) {
  const st = backend.store;
  if (!st) return { status: 503, body: { error: 'accounts_unavailable' } };
  if (!UUID_RE.test(uid)) return { status: 404, body: { error: 'not_found' } };
  const v0 = validate(kind, uid, body, now);
  if (!v0.ok) return { status: v0.status, body: { error: v0.error, detail: v0.detail } };
  let profile;
  try { profile = await Q.withTimeout(st.getProfile(uid)); } catch { return { status: 503, body: { error: 'entitlements_unavailable', detail: 'falha ao ler o jogador' } }; }
  if (!profile) return { status: 404, body: { error: 'player_not_found' } };
  let before;
  try { before = await readRow(st, uid); } catch { return { status: 503, body: { error: 'entitlements_unavailable', detail: 'falha ao ler o estado atual (nada foi alterado)' } }; }
  const vb = view(before, now);
  if (body.expect_version !== vb.version) return { status: 409, body: { error: 'stale_state', detail: 'o estado mudou desde que a tela foi carregada', state: vb } };
  const nowIso = new Date(now).toISOString();
  const p = plan(kind, vb, v0.action, v0.expires, nowIso);
  const target = { user_id: uid, nickname: profile.nickname || null };
  const actor = admin;
  if (p.error) return { status: p.status, body: { error: p.error, detail: p.detail, state: vb } };
  if (p.noop) {
    const a = audit.record({ actor, action: AUDIT[kind][v0.action], target, before: auditState(vb), after: auditState(vb), result: 'noop', reason: v0.reason });
    return { status: 200, body: { changed: false, state: vb, audit_id: a.id } };
  }
  let row;
  try { row = await writeRow(st, uid, before, p.patch, nowIso); }
  catch (e) {
    console.error('[admin] entitlements write failed', e && (e.code || e.message));
    audit.record({ actor, action: AUDIT[kind][v0.action], target, before: auditState(vb), after: null, result: 'error', reason: v0.reason, meta: { error: 'write_failed' } });
    return { status: 502, body: { error: 'write_failed', detail: 'o banco recusou a gravação (nada foi alterado)' } };
  }
  if (!row) return { status: 409, body: { error: 'stale_state', detail: 'outra alteração aconteceu ao mesmo tempo; recarregue', state: view(await readRow(st, uid).catch(() => undefined), now) } };
  const va = view(row, now);
  const a = audit.record({ actor, action: AUDIT[kind][v0.action], target, before: auditState(vb), after: auditState(va), result: 'ok', reason: v0.reason,
    meta: kind === 'club' && v0.action !== 'revoke' ? { duration: body.duration } : null });
  // Jogador online recebe o estado novo pelo caminho oficial (acct_state), como no webhook de pagamento.
  for (const ws of backend.socketsOf ? backend.socketsOf(uid) : []) { try { await backend.state(ws); } catch { /* próxima leitura normal corrige */ } }
  return { status: 200, body: { changed: true, state: va, audit_id: a.id } };
}

module.exports = { apply, view, validate, plan, DURATIONS, AUDIT };
