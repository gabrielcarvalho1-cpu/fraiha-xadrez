'use strict';
// FRAIHA Admin · consultas SOMENTE-LEITURA ao armazenamento de contas (Supabase via service role no
// SERVIDOR, ou MemoryStore em DEV). Nada aqui escreve. Dados pessoais mínimos: e-mail NÃO é lido.
const { UUID_RE } = require('../accounts/store');
const PROFILE_COLS = 'user_id,nickname,avatar_id,account_status,created_at,last_login_at,profile_badge,profile_title,profile_frame';
const ENT_COLS = 'user_id,is_founder,founder_since,club_active,club_expires_at,club_source,updated_at';
const startOfUtcDay = (t = Date.now()) => { const d = new Date(t); d.setUTCHours(0, 0, 0, 0); return d.toISOString(); };
const isSupabase = st => !!(st && st.req && st.fetch && st.url && st.headers);
const unavailable = (note) => ({ value: null, status: 'unavailable', note });
const QUERY_TIMEOUT_MS = 5000;
const cfg = { timeoutMs: QUERY_TIMEOUT_MS };   // testes podem encurtar (cfg.timeoutMs)
// Consulta com prazo: nunca fica pendurada; erro/timeout NUNCA vira "não tem" (fail-closed para leitura).
function withTimeout(p, ms = cfg.timeoutMs) {
  let t;
  return Promise.race([Promise.resolve(p), new Promise((_, rej) => { t = setTimeout(() => { const e = new Error('query_timeout'); e.code = 'timeout'; rej(e); }, ms); })])
    .finally(() => clearTimeout(t));
}
const errCode = e => (e && e.code === 'timeout') ? 'timeout' : 'query_error';

async function supaCount(st, path) {
  const res = await st.fetch(st.url + path, { method: 'HEAD', headers: { ...st.headers, Prefer: 'count=exact', Range: '0-0' } });
  if (!res.ok && res.status !== 206) throw new Error('HTTP ' + res.status);
  const cr = res.headers.get('content-range') || '';
  const n = Number(cr.split('/')[1]);
  if (!Number.isFinite(n)) throw new Error('count_unavailable');
  return n;
}

async function accountCounts(st, now = Date.now()) {
  if (!st) return { registered: unavailable('servidor sem armazenamento de contas'), new_today: unavailable('servidor sem armazenamento de contas') };
  const today = startOfUtcDay(now);
  try {
    if (isSupabase(st)) {
      const [all, fresh] = await Promise.all([supaCount(st, '/profiles?select=user_id'), supaCount(st, '/profiles?select=user_id&created_at=gte.' + encodeURIComponent(today))]);
      return { registered: { value: all, status: 'real', note: 'perfis criados (Supabase)' }, new_today: { value: fresh, status: 'real', note: 'perfis criados desde 00:00 UTC' } };
    }
    if (st.profiles instanceof Map) {
      const ps = [...st.profiles.values()];
      return { registered: { value: ps.length, status: 'real', note: 'armazenamento DEV em memória' },
        new_today: { value: ps.filter(p => String(p.created_at || '') >= today).length, status: 'real', note: 'armazenamento DEV em memória · desde 00:00 UTC' } };
    }
  } catch (e) { return { registered: unavailable('falha ao consultar: ' + String(e.message).slice(0, 80)), new_today: unavailable('falha ao consultar') }; }
  return { registered: unavailable('armazenamento não suportado'), new_today: unavailable('armazenamento não suportado') };
}

// Busca por nickname (parcial) ou UUID exato. Limite pequeno; sem e-mail (privacidade + exige Auth Admin).
async function searchPlayers(st, q, limit = 50) {
  q = String(q || '').trim().slice(0, 40);
  limit = Math.max(1, Math.min(100, Number(limit) || 50));
  if (!st) return [];
  if (isSupabase(st)) {
    let filter;
    if (UUID_RE.test(q)) filter = 'user_id=eq.' + encodeURIComponent(q);
    else if (q) filter = 'nickname=ilike.' + encodeURIComponent('*' + q.replace(/[*,()]/g, '') + '*');
    else filter = 'order=last_login_at.desc.nullslast';
    const rows = await st.req('/profiles?select=' + PROFILE_COLS + '&' + filter + '&limit=' + limit);
    return rows || [];
  }
  const ps = [...(st.profiles || new Map()).values()];
  const hit = UUID_RE.test(q) ? ps.filter(p => p.user_id === q) : q ? ps.filter(p => String(p.nickname).toLowerCase().includes(q.toLowerCase())) : ps;
  return hit.sort((a, b) => String(b.last_login_at || '').localeCompare(String(a.last_login_at || ''))).slice(0, limit);
}

// → { ok:true, map } (linha ausente = jogador SEM benefício, legítimo) | { ok:false, error:'timeout'|'query_error' }
// Falha de leitura NUNCA é convertida em "Clube inativo"/"Founder não".
async function entitlementsOf(st, ids, ms) {
  const map = new Map();
  if (!st || !ids.length) return { ok: true, map };
  try {
    if (isSupabase(st)) {
      const ok = ids.filter(i => UUID_RE.test(i));
      if (!ok.length) return { ok: true, map };
      const rows = await withTimeout(st.req('/entitlements?select=' + ENT_COLS + '&user_id=in.(' + ok.join(',') + ')'), ms);
      for (const r of rows || []) map.set(r.user_id, r);
      return { ok: true, map };
    }
    if (st.adminEntitlementsFault) await withTimeout(st.adminEntitlementsFault(), ms);   // só testes (MemoryStore)
    for (const id of ids) { const e = st.entitlements && st.entitlements.get(id); if (e) map.set(id, { user_id: id, ...e }); }
    return { ok: true, map };
  } catch (e) {
    console.error('[admin] entitlements read failed', errCode(e));
    return { ok: false, error: errCode(e) };
  }
}
// Leitura de UM bloco do perfil: { ok:true, value } | { ok:false, error }
async function section(fn, ms) { try { return { ok: true, value: await withTimeout(fn(), ms) }; } catch (e) { return { ok: false, error: errCode(e) }; } }

async function playerDetail(st, uid) {
  if (!UUID_RE.test(String(uid || ''))) return null;
  const p = await st.getProfile(uid);
  if (!p) return null;
  const [ranked, modes, ents] = await Promise.all([
    section(() => st.getRankedStats(uid)),
    st.getModeStats ? section(() => st.getModeStats(uid)) : { ok: false, error: 'query_error' },
    entitlementsOf(st, [uid]),
  ]);
  const pick = {}; for (const k of PROFILE_COLS.split(',')) pick[k] = p[k] === undefined ? null : p[k];
  return { profile: pick, ranked, modes, entitlements: ents.ok ? { ok: true, value: ents.map.get(uid) || null } : { ok: false, error: ents.error } };
}

// e === undefined → desconhecido (erro de leitura). null → sem linha (legítimo: nunca teve).
function clubStatus(e, now = Date.now()) {
  if (e === undefined) return 'INDISPONÍVEL';
  if (!e) return 'INATIVO';
  if (e.club_active && (!e.club_expires_at || new Date(e.club_expires_at).getTime() > now)) return 'ATIVO';
  if (e.club_expires_at && new Date(e.club_expires_at).getTime() <= now) return 'EXPIRADO';
  return 'INATIVO';
}
module.exports = { cfg, withTimeout, QUERY_TIMEOUT_MS, accountCounts, searchPlayers, entitlementsOf, playerDetail, clubStatus, isSupabase, startOfUtcDay };
