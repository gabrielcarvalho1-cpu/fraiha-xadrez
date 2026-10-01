'use strict';
// Armazenamento competitivo. A lógica Ranked (ranked/progression.js) não sabe
// onde os dados ficam; troca-se o store sem mexer nas regras.
const MODES = ['ranked_3min', 'ranked_5min', 'ranked_10min', 'ranked_20min'];
// Nome público: 3–20 caracteres, só letras, números e _ (nomes antigos com . - ou acento continuam
// válidos no banco; a regra estrita vale para nomes NOVOS ou trocados).
const NICK_RE = /^[A-Za-z0-9_]{3,20}$/;
const NICK_MIN = 3, NICK_MAX = 20;
const NICK_COOLDOWN_MS = 30 * 24 * 3600e3;   // troca de nome: 30 dias (relógio do servidor/banco)
const RESERVED = ['admin', 'fraiha', 'moderador', 'suporte', 'system', 'convidado', 'jogador', 'club', 'fundador'];
const AVATARS = ['warrior', 'archer', 'mage', 'paladin'];
// Remove espaços, caracteres invisíveis, de controle e bidi; normaliza (NFKC) antes de validar.
const INVISIBLE_RE = /[\u0000-\u001F\u007F-\u009F\u00AD\u034F\u061C\u115F\u1160\u17B4\u17B5\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\u3164\uFE00-\uFE0F\uFEFF\uFFA0\uFFF0-\uFFFF]/g;
function cleanNickname(value) {
  return String(value || '').normalize('NFKC').replace(INVISIBLE_RE, '').trim();
}
function validateNickname(value) {
  const nick = cleanNickname(value);
  if (!nick) return { error: 'Digite um nome.' };
  if (nick.length < NICK_MIN || nick.length > NICK_MAX) return { error: `O nome precisa ter entre ${NICK_MIN} e ${NICK_MAX} caracteres.` };
  if (!NICK_RE.test(nick)) return { error: 'Use apenas letras, números e _ (sem espaços nem acentos).' };
  if (RESERVED.includes(nick.toLowerCase())) return { error: 'Este nome é reservado. Escolha outro.' };
  return { nickname: nick };
}
const nextNickChange = p => {
  if (!p || !p.nickname_changed_at) return null;
  return new Date(new Date(p.nickname_changed_at).getTime() + NICK_COOLDOWN_MS).toISOString();
};
const emptyStats = () => ({ league: 0, pl: 0, matches: 0, wins: 0, losses: 0, draws: 0, highest_league: 0 });
const pub = p => ({ user_id: p.user_id, nickname: p.nickname, avatar_id: p.avatar_id, avatar_url: p.avatar_url || null });
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const fullStats = rows => { const out = {}; for (const m of MODES) out[m] = { ...emptyStats(), ...(rows[m] || {}) }; return out; };

class MemoryStore {
  constructor() { this.profiles = new Map(); this.stats = new Map(); this.matches = []; this.persistent = false; this.social = { requests: new Set(), friends: new Set(), blocks: new Set() }; this.dms = []; this.dmSeq = 0; }
  async getProfile(userId) { return this.profiles.get(userId) || null; }
  async createProfile(userId, nickname, avatarId) {
    if (this.profiles.has(userId)) return { error: 'Este perfil já existe.' };
    for (const p of this.profiles.values()) if (p.nickname.toLowerCase() === nickname.toLowerCase()) return { error: 'Este nome já está em uso.', code: 'nickname_taken' };
    const now = new Date().toISOString();
    const profile = { user_id: userId, nickname, avatar_id: AVATARS.includes(avatarId) ? avatarId : 'warrior', profile_frame: 'madeira', account_status: 'active', created_at: now, updated_at: now, last_login_at: now };
    this.profiles.set(userId, profile);
    // FRAIHA_DEV_START_PL: somente testes com armazenamento em memória.
    const startPl = Number(process.env.FRAIHA_DEV_START_PL || 0);
    const s = {}; for (const m of MODES) s[m] = { ...emptyStats(), pl: startPl }; this.stats.set(userId, s);
    return { profile };
  }
  async touchLogin(userId) { const p = this.profiles.get(userId); if (p) p.last_login_at = new Date().toISOString(); }
  // ---------- Nome público (0004) ----------
  async nicknameAvailable(nick, exceptUserId = null) {
    for (const p of this.profiles.values()) if (p.user_id !== exceptUserId && p.nickname.toLowerCase() === nick.toLowerCase()) return false;
    return true;
  }
  // Cooldown decidido AQUI (relógio do servidor), nunca pelo cliente.
  async changeNickname(userId, nick) {
    const p = this.profiles.get(userId);
    if (!p) return { error: 'Perfil não encontrado.', code: 'profile_missing' };
    if (p.nickname === nick) return { profile: p };
    const next = nextNickChange(p);
    if (next && Date.now() < new Date(next).getTime()) return { error: 'Você só pode trocar o nome de novo em 30 dias.', code: 'nickname_cooldown', next_change_at: next };
    if (!(await this.nicknameAvailable(nick, userId))) return { error: 'Este nome já está em uso.', code: 'nickname_taken' };
    p.nickname = nick; p.nickname_changed_at = new Date().toISOString(); p.updated_at = p.nickname_changed_at;
    return { profile: p };
  }
  // ---------- Foto de perfil (0004): em memória só para desenvolvimento ----------
  async saveAvatar(userId, bytes, mime) {
    const p = this.profiles.get(userId);
    if (!p) return { error: 'Perfil não encontrado.', code: 'profile_missing' };
    this.avatars = this.avatars || new Map();
    this.avatars.set(userId, { bytes, mime });
    p.avatar_url = 'memory://avatars/' + userId + '.webp?v=' + Date.now();
    p.avatar_updated_at = new Date().toISOString();
    return { profile: p };
  }
  async clearAvatar(userId) {
    const p = this.profiles.get(userId);
    if (!p) return { error: 'Perfil não encontrado.', code: 'profile_missing' };
    if (this.avatars) this.avatars.delete(userId);
    p.avatar_url = null; p.avatar_updated_at = new Date().toISOString();
    return { profile: p };
  }
  async getRankedStats(userId) { return fullStats(this.stats.get(userId) || {}); }
  async recordRankedMatch(r) {
    const w = this.stats.get(r.white_user_id)[r.mode], b = this.stats.get(r.black_user_id)[r.mode];
    if (w.pl !== r.white_pl_before || w.league !== r.white_league_before || b.pl !== r.black_pl_before || b.league !== r.black_league_before) throw new Error('estado Ranked mudou durante a partida');
    const apply = (s, side) => {
      const out = r.result === 'draw' ? 'draws' : (r.result === side ? 'wins' : 'losses');
      s.league = r[side + '_league_after']; s.pl = r[side + '_pl_after']; s.matches++; s[out]++;
      s.highest_league = Math.max(s.highest_league, s.league);
    };
    apply(w, 'white'); apply(b, 'black');
    this.matches.push({ ...r });
    return r.match_id;
  }

  // ---------- Amigos (0002_fraiha_social) ----------
  async searchProfiles(query, limit = 20) {
    const q = query.toLowerCase(), out = [];
    for (const p of this.profiles.values()) if (p.nickname.toLowerCase().includes(q)) out.push(pub(p));
    return out.sort((a, b) => a.nickname.localeCompare(b.nickname)).slice(0, limit);
  }
  async getProfilesByIds(ids) { return ids.map(id => this.profiles.get(id)).filter(Boolean).map(pub); }
  async getRelations(uid) {
    const s = this.social, r = { friends: [], sent: [], received: [], blocked: [], blockedBy: [] };
    for (const k of s.requests) { const [f, t] = k.split('|'); if (f === uid) r.sent.push(t); if (t === uid) r.received.push(f); }
    for (const k of s.friends) { const [a, b] = k.split('|'); if (a === uid) r.friends.push(b); if (b === uid) r.friends.push(a); }
    for (const k of s.blocks) { const [a, b] = k.split('|'); if (a === uid) r.blocked.push(b); if (b === uid) r.blockedBy.push(a); }
    return r;
  }
  async addRequest(from, to) { this.social.requests.add(from + '|' + to); }
  async removeRequest(from, to) { this.social.requests.delete(from + '|' + to); }
  async addFriendship(a, b) { const [x, y] = [a, b].sort(); this.social.friends.add(x + '|' + y); }
  async removeFriendship(a, b) { const [x, y] = [a, b].sort(); this.social.friends.delete(x + '|' + y); }
  async addBlock(a, b) { this.social.blocks.add(a + '|' + b); }
  async removeBlock(a, b) { this.social.blocks.delete(a + '|' + b); }

  // ---------- Mensagens privadas (0003_fraiha_dm) ----------
  async addDirectMessage(from, to, body) {
    const m = { id: ++this.dmSeq, sender_id: from, recipient_id: to, body, created_at: new Date().toISOString(), read_at: null };
    this.dms.push(m); return { ...m };
  }
  // Últimas `limit` mensagens do par (opcional: anteriores a beforeId), em ordem crescente.
  async getConversation(a, b, limit = 50, beforeId = 0) {
    const pair = this.dms.filter(m => ((m.sender_id === a && m.recipient_id === b) || (m.sender_id === b && m.recipient_id === a)) && (!beforeId || m.id < beforeId));
    return pair.slice(-limit).map(m => ({ ...m }));
  }
  async markDirectRead(recipient, sender) {
    const now = new Date().toISOString(); let n = 0;
    for (const m of this.dms) if (m.recipient_id === recipient && m.sender_id === sender && !m.read_at) { m.read_at = now; n++; }
    return n;
  }
  async unreadCounts(uid) {
    const out = {};
    for (const m of this.dms) if (m.recipient_id === uid && !m.read_at) out[m.sender_id] = (out[m.sender_id] || 0) + 1;
    return out;
  }
}

class SupabaseStore {
  constructor({ url, serviceKey, fetchImpl = fetch }) {
    this.url = url.replace(/\/+$/, '') + '/rest/v1'; this.fetch = fetchImpl; this.persistent = true;
    this.headers = { apikey: serviceKey, 'Content-Type': 'application/json' };
    // Chaves legadas (JWT) também exigem Authorization; as novas sb_secret_ só apikey.
    if (serviceKey.startsWith('eyJ')) this.headers.Authorization = 'Bearer ' + serviceKey;
  }
  async req(path, opts = {}) {
    const res = await this.fetch(this.url + path, { ...opts, headers: { ...this.headers, ...(opts.headers || {}) } });
    const text = await res.text();
    const body = text ? JSON.parse(text) : null;
    if (!res.ok) { const e = new Error((body && body.message) || ('HTTP ' + res.status)); e.code = body && body.code; throw e; }
    return body;
  }
  async getProfile(userId) {
    const rows = await this.req('/profiles?user_id=eq.' + encodeURIComponent(userId) + '&select=*');
    return rows[0] || null;
  }
  async createProfile(userId, nickname, avatarId) {
    try {
      const rows = await this.req('/profiles', { method: 'POST', headers: { Prefer: 'return=representation' },
        body: JSON.stringify({ user_id: userId, nickname, avatar_id: AVATARS.includes(avatarId) ? avatarId : 'warrior', last_login_at: new Date().toISOString() }) });
      return { profile: rows[0] };
    } catch (e) {
      if (e.code === '23505') return { error: 'Este nome já está em uso.', code: 'nickname_taken' };
      if (e.code === '23514') return { error: 'Nome inválido.' };
      throw e;
    }
  }
  async touchLogin(userId) {
    await this.req('/profiles?user_id=eq.' + encodeURIComponent(userId), { method: 'PATCH', body: JSON.stringify({ last_login_at: new Date().toISOString() }) });
  }
  // ---------- Nome público (0004): regras no banco (fraiha_change_nickname / fraiha_nickname_available) ----------
  async nicknameAvailable(nick, exceptUserId = null) {
    return !!(await this.req('/rpc/fraiha_nickname_available', { method: 'POST', body: JSON.stringify({ p_nick: nick, p_user: exceptUserId }) }));
  }
  async changeNickname(userId, nick) {
    try {
      const row = await this.req('/rpc/fraiha_change_nickname', { method: 'POST', body: JSON.stringify({ p_user: userId, p_nick: nick }) });
      return { profile: row };
    } catch (e) {
      const msg = String(e.message || '');
      const cd = msg.match(/nickname_cooldown:(\S+)/);
      if (cd) return { error: 'Você só pode trocar o nome de novo em 30 dias.', code: 'nickname_cooldown', next_change_at: cd[1] };
      if (/nickname_taken/.test(msg) || e.code === '23505') return { error: 'Este nome já está em uso.', code: 'nickname_taken' };
      if (/nickname_invalid/.test(msg) || e.code === '23514') return { error: 'Nome inválido.', code: 'nickname_invalid' };
      if (/nickname_cooldown/.test(msg)) return { error: 'Você só pode trocar o nome de novo em 30 dias.', code: 'nickname_cooldown' };
      throw e;
    }
  }
  // ---------- Foto de perfil (0004): Supabase Storage, bucket "avatars", sempre <user_id>.webp ----------
  storageUrl() { return this.url.replace(/\/rest\/v1$/, '') + '/storage/v1'; }
  async saveAvatar(userId, bytes, mime) {
    const path = 'avatars/' + userId + '.webp';
    const res = await this.fetch(this.storageUrl() + '/object/' + path, { method: 'POST',
      headers: { ...this.headers, 'Content-Type': mime || 'image/webp', 'x-upsert': 'true' }, body: bytes });
    if (!res.ok) { const t = await res.text(); const e = new Error('storage ' + res.status + ' ' + t); e.code = 'storage_error'; throw e; }
    const url = this.storageUrl() + '/object/public/' + path + '?v=' + Date.now();
    const rows = await this.req('/profiles?user_id=eq.' + encodeURIComponent(userId) + '&select=*', { method: 'PATCH', headers: { Prefer: 'return=representation' },
      body: JSON.stringify({ avatar_url: url, avatar_updated_at: new Date().toISOString() }) });
    return { profile: rows[0] };
  }
  async clearAvatar(userId) {
    await this.fetch(this.storageUrl() + '/object/avatars/' + userId + '.webp', { method: 'DELETE', headers: this.headers }).catch(() => {});
    const rows = await this.req('/profiles?user_id=eq.' + encodeURIComponent(userId) + '&select=*', { method: 'PATCH', headers: { Prefer: 'return=representation' },
      body: JSON.stringify({ avatar_url: null, avatar_updated_at: new Date().toISOString() }) });
    return { profile: rows[0] };
  }
  async getRankedStats(userId) {
    const rows = await this.req('/ranked_stats?user_id=eq.' + encodeURIComponent(userId) + '&select=mode,league,pl,matches,wins,losses,draws,highest_league');
    const map = {}; for (const r of rows) map[r.mode] = r;
    return fullStats(map);
  }
  async recordRankedMatch(r) {
    return this.req('/rpc/fraiha_record_ranked_match', { method: 'POST', body: JSON.stringify({ p: r }) });
  }
  // ---------- Amigos (0002_fraiha_social). Todos os ids já validados como UUID pelo serviço. ----------
  async searchProfiles(query, limit = 20) {
    return this.req('/profiles?nickname=ilike.' + encodeURIComponent('*' + query + '*') + '&select=user_id,nickname,avatar_id,avatar_url&order=nickname.asc&limit=' + limit);
  }
  async getProfilesByIds(ids) {
    const ok = ids.filter(id => UUID_RE.test(id));
    if (!ok.length) return [];
    return this.req('/profiles?user_id=in.(' + ok.join(',') + ')&select=user_id,nickname,avatar_id,avatar_url');
  }
  async getRelations(uid) {
    const u = encodeURIComponent(uid), r = { friends: [], sent: [], received: [], blocked: [], blockedBy: [] };
    const [reqs, fr, bl] = await Promise.all([
      this.req(`/friend_requests?or=(from_user.eq.${u},to_user.eq.${u})&select=from_user,to_user`),
      this.req(`/friendships?or=(user_a.eq.${u},user_b.eq.${u})&select=user_a,user_b`),
      this.req(`/blocks?or=(blocker.eq.${u},blocked.eq.${u})&select=blocker,blocked`)]);
    for (const x of reqs) { if (x.from_user === uid) r.sent.push(x.to_user); else r.received.push(x.from_user); }
    for (const x of fr) r.friends.push(x.user_a === uid ? x.user_b : x.user_a);
    for (const x of bl) { if (x.blocker === uid) r.blocked.push(x.blocked); else r.blockedBy.push(x.blocker); }
    return r;
  }
  async _insert(table, row) {
    await this.req('/' + table, { method: 'POST', headers: { Prefer: 'resolution=ignore-duplicates,return=minimal' }, body: JSON.stringify(row) });
  }
  async _delete(table, filters) {
    const q = Object.entries(filters).map(([k, v]) => k + '=eq.' + encodeURIComponent(v)).join('&');
    await this.req('/' + table + '?' + q, { method: 'DELETE', headers: { Prefer: 'return=minimal' } });
  }
  async addRequest(from, to) { return this._insert('friend_requests', { from_user: from, to_user: to }); }
  async removeRequest(from, to) { return this._delete('friend_requests', { from_user: from, to_user: to }); }
  async addFriendship(a, b) { const [x, y] = [a, b].sort(); return this._insert('friendships', { user_a: x, user_b: y }); }
  async removeFriendship(a, b) { const [x, y] = [a, b].sort(); return this._delete('friendships', { user_a: x, user_b: y }); }
  async addBlock(a, b) { return this._insert('blocks', { blocker: a, blocked: b }); }
  async removeBlock(a, b) { return this._delete('blocks', { blocker: a, blocked: b }); }
  // ---------- Mensagens privadas (0003_fraiha_dm). Ids já validados como UUID pelo serviço. ----------
  async addDirectMessage(from, to, body) {
    const rows = await this.req('/direct_messages?select=' + DM_COLS, { method: 'POST', headers: { Prefer: 'return=representation' },
      body: JSON.stringify({ sender_id: from, recipient_id: to, body }) });
    return rows[0];
  }
  async getConversation(a, b, limit = 50, beforeId = 0) {
    const pair = `or=(and(sender_id.eq.${a},recipient_id.eq.${b}),and(sender_id.eq.${b},recipient_id.eq.${a}))`;
    const before = beforeId ? '&id=lt.' + Number(beforeId) : '';
    const rows = await this.req(`/direct_messages?${pair}${before}&select=${DM_COLS}&order=id.desc&limit=${Number(limit)}`);
    return rows.reverse();
  }
  async markDirectRead(recipient, sender) {
    const rows = await this.req(`/direct_messages?recipient_id=eq.${recipient}&sender_id=eq.${sender}&read_at=is.null&select=id`, {
      method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ read_at: new Date().toISOString() }) });
    return rows.length;
  }
  async unreadCounts(uid) {
    const rows = await this.req(`/direct_messages?recipient_id=eq.${uid}&read_at=is.null&select=sender_id&limit=5000`);
    const out = {}; for (const r of rows) out[r.sender_id] = (out[r.sender_id] || 0) + 1;
    return out;
  }
}
const DM_COLS = 'id,sender_id,recipient_id,body,created_at,read_at';

module.exports = { MemoryStore, SupabaseStore, validateNickname, cleanNickname, nextNickChange, NICK_COOLDOWN_MS, MODES, AVATARS, emptyStats, UUID_RE };
