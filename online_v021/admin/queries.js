'use strict';
// FRAIHA Admin · consultas SOMENTE-LEITURA ao armazenamento de contas (Supabase via service role no
// SERVIDOR, ou MemoryStore em DEV). Nada aqui escreve. Dados pessoais mínimos: e-mail NÃO é lido.
const { UUID_RE } = require('../accounts/store');
const PROFILE_COLS = 'user_id,nickname,avatar_id,account_status,created_at,last_login_at,profile_badge,profile_title,profile_frame';
const ENT_COLS = 'user_id,is_founder,founder_since,club_active,club_expires_at,club_source,updated_at';
const startOfUtcDay = (t = Date.now()) => { const d = new Date(t); d.setUTCHours(0, 0, 0, 0); return d.toISOString(); };
const isSupabase = st => !!(st && st.req && st.fetch && st.url && st.headers);
const unavailable = (note) => ({ value: null, status: 'unavailable', note });

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

async function entitlementsOf(st, ids) {
  const out = new Map();
  if (!st || !ids.length) return out;
  if (isSupabase(st)) {
    try {
      const rows = await st.req('/entitlements?select=' + ENT_COLS + '&user_id=in.(' + ids.filter(i => UUID_RE.test(i)).join(',') + ')');
      for (const r of rows || []) out.set(r.user_id, r);
    } catch { /* tabela ausente: fica vazio (status unavailable no consumidor) */ }
    return out;
  }
  for (const id of ids) { const e = st.entitlements && st.entitlements.get(id); if (e) out.set(id, { user_id: id, ...e }); }
  return out;
}

async function playerDetail(st, uid) {
  if (!UUID_RE.test(String(uid || ''))) return null;
  const p = await st.getProfile(uid);
  if (!p) return null;
  const [ranked, modes, ent] = await Promise.all([
    st.getRankedStats(uid).catch(() => null),
    st.getModeStats ? st.getModeStats(uid).catch(() => null) : null,
    entitlementsOf(st, [uid]).then(m => m.get(uid) || null),
  ]);
  const pick = {}; for (const k of PROFILE_COLS.split(',')) pick[k] = p[k] === undefined ? null : p[k];
  return { profile: pick, ranked, modes, entitlements: ent };
}

function clubStatus(e, now = Date.now()) {
  if (!e) return 'INATIVO';
  if (e.club_active && (!e.club_expires_at || new Date(e.club_expires_at).getTime() > now)) return 'ATIVO';
  if (e.club_expires_at && new Date(e.club_expires_at).getTime() <= now) return 'EXPIRADO';
  return 'INATIVO';
}
module.exports = { accountCounts, searchPlayers, entitlementsOf, playerDetail, clubStatus, isSupabase, startOfUtcDay };
