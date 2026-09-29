'use strict';
// Armazenamento competitivo. A lógica Ranked (ranked/progression.js) não sabe
// onde os dados ficam; troca-se o store sem mexer nas regras.
const MODES = ['ranked_3min', 'ranked_5min', 'ranked_10min', 'ranked_20min'];
const NICK_RE = /^[A-Za-z0-9_.À-ÖØ-öø-ÿ-]{3,16}$/;
const RESERVED = ['admin', 'fraiha', 'moderador', 'suporte', 'system', 'convidado', 'jogador'];
const AVATARS = ['warrior', 'archer', 'mage', 'paladin'];

function validateNickname(value) {
  const nick = String(value || '').trim();
  if (nick.length < 3 || nick.length > 16) return { error: 'O nome precisa ter entre 3 e 16 caracteres.' };
  if (!NICK_RE.test(nick)) return { error: 'Use apenas letras, números, ponto, hífen ou _ (sem espaços).' };
  if (RESERVED.includes(nick.toLowerCase())) return { error: 'Este nome é reservado. Escolha outro.' };
  return { nickname: nick };
}
const emptyStats = () => ({ league: 0, pl: 0, matches: 0, wins: 0, losses: 0, draws: 0, highest_league: 0 });
const fullStats = rows => { const out = {}; for (const m of MODES) out[m] = { ...emptyStats(), ...(rows[m] || {}) }; return out; };

class MemoryStore {
  constructor() { this.profiles = new Map(); this.stats = new Map(); this.matches = []; this.persistent = false; }
  async getProfile(userId) { return this.profiles.get(userId) || null; }
  async createProfile(userId, nickname, avatarId) {
    if (this.profiles.has(userId)) return { error: 'Este perfil já existe.' };
    for (const p of this.profiles.values()) if (p.nickname.toLowerCase() === nickname.toLowerCase()) return { error: 'Este nome já está em uso.', code: 'nickname_taken' };
    const now = new Date().toISOString();
    const profile = { user_id: userId, nickname, avatar_id: AVATARS.includes(avatarId) ? avatarId : 'warrior', profile_frame: 'madeira', account_status: 'active', created_at: now, updated_at: now, last_login_at: now };
    this.profiles.set(userId, profile);
    const s = {}; for (const m of MODES) s[m] = emptyStats(); this.stats.set(userId, s);
    return { profile };
  }
  async touchLogin(userId) { const p = this.profiles.get(userId); if (p) p.last_login_at = new Date().toISOString(); }
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
  async getRankedStats(userId) {
    const rows = await this.req('/ranked_stats?user_id=eq.' + encodeURIComponent(userId) + '&select=mode,league,pl,matches,wins,losses,draws,highest_league');
    const map = {}; for (const r of rows) map[r.mode] = r;
    return fullStats(map);
  }
  async recordRankedMatch(r) {
    return this.req('/rpc/fraiha_record_ranked_match', { method: 'POST', body: JSON.stringify({ p: r }) });
  }
}

module.exports = { MemoryStore, SupabaseStore, validateNickname, MODES, AVATARS, emptyStats };
