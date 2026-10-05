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
const Cosmetics = require('./cosmetics');
// Avatares aceitos na criação do perfil (gratuitos + antigos). Os demais só por acct_set_cosmetics.
const AVATARS = [...Cosmetics.FREE_AVATARS, ...Cosmetics.LEGACY_AVATARS];
const FOUNDER_CLUB_DAYS = 30;          // Pacote Fundador inclui 30 dias de Club
const CLUB_MONTH_DAYS = 30;
// Novo vencimento do Club: soma `days` ao que ainda resta (nunca perde dias já pagos).
const extendClub = (expiresAt, days, now = Date.now()) => {
  const base = expiresAt && new Date(expiresAt).getTime() > now ? new Date(expiresAt).getTime() : now;
  return new Date(base + days * 86400e3).toISOString();
};
const SCHEMA_MISSING = e => /42P01|42703|PGRST200|PGRST204|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));
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
// Perfil público (Amigos, busca, convites, DM). R31: + selo/título/moldura e flags de Fundador/Club
// (Destaque social) — sempre já filtrados pelos direitos ATIVOS da conta.
const pub = (p, ent) => {
  const c = Cosmetics.effective(p, ent || p.entitlements || null);
  return { user_id: p.user_id, nickname: p.nickname, avatar_id: c.avatar_id, avatar_url: p.avatar_url || null,
    badge: c.badge, title: c.title, frame: c.frame, founder: c.founder, club: c.club };
};
// R37 · placar por modo (0009_fraiha_mode_stats): casual / marcha / xeque (o Ranked fica em ranked_stats).
const STAT_MODES = ['casual', 'marcha', 'xeque'];
const emptyModeStats = () => { const o = {}; for (const m of STAT_MODES) o[m] = { wins: 0, losses: 0, draws: 0 }; return o; };
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const fullStats = rows => { const out = {}; for (const m of MODES) out[m] = { ...emptyStats(), ...(rows[m] || {}) }; return out; };

class MemoryStore {
  constructor() { this.profiles = new Map(); this.stats = new Map(); this.matches = []; this.persistent = false; this.social = { requests: new Set(), friends: new Set(), blocks: new Set() }; this.dms = []; this.dmSeq = 0; }
  async getProfile(userId) { return this.profiles.get(userId) || null; }
  async getModeStats(userId) { const o = emptyModeStats(); const m = (this.modeStats || new Map()).get(userId) || {}; for (const k of STAT_MODES) Object.assign(o[k], m[k] || {}); return o; }
  async recordModeResult(userId, mode, result) {
    if (!STAT_MODES.includes(mode) || !['win', 'loss', 'draw'].includes(result)) return;
    this.modeStats = this.modeStats || new Map();
    const row = this.modeStats.get(userId) || {}; const r = row[mode] || { wins: 0, losses: 0, draws: 0 };
    r[result === 'win' ? 'wins' : result === 'loss' ? 'losses' : 'draws'] += 1; row[mode] = r; this.modeStats.set(userId, row);
  }
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
  // ---------- Direitos (0005): em memória só para desenvolvimento ----------
  async getEntitlements(userId) {
    this.entitlements = this.entitlements || new Map();
    const e = this.entitlements.get(userId) || {};
    return { is_founder: !!e.is_founder, club_active: !!e.club_active && (!e.club_expires_at || new Date(e.club_expires_at) > new Date()), club_expires_at: e.club_expires_at || null };
  }
  async setEntitlements(userId, patch) {
    this.entitlements = this.entitlements || new Map();
    this.entitlements.set(userId, { ...(this.entitlements.get(userId) || {}), ...patch });
    return this.getEntitlements(userId);
  }
  // ---------- R31: liberar direitos depois de pagamento confirmado (mesma regra da função 0007) ----------
  async grantEntitlement(userId, productId, source) {
    this.entitlements = this.entitlements || new Map();
    const e = { ...(this.entitlements.get(userId) || {}) }, now = new Date().toISOString();
    if (productId === 'founder') {
      e.is_founder = true; e.founder_since = e.founder_since || now;
      e.club_expires_at = extendClub(e.club_active ? e.club_expires_at : null, FOUNDER_CLUB_DAYS);
      e.club_active = true; e.club_source = e.club_source && e.club_source !== 'founder_bonus' ? e.club_source : 'founder_bonus';
    } else if (productId === 'club_monthly') {
      e.club_expires_at = extendClub(e.club_active ? e.club_expires_at : null, CLUB_MONTH_DAYS);
      e.club_active = true; e.club_source = String(source || 'manual');
    } else return null;
    e.updated_at = now;
    this.entitlements.set(userId, e);
    return this.getEntitlements(userId);
  }
  // ---------- R31: pagamentos (em memória só para desenvolvimento/testes) ----------
  async createPayment(row) {
    this.payments = this.payments || [];
    const p = { payment_id: require('crypto').randomUUID(), created_at: new Date().toISOString(), paid_at: null, ...row };
    this.payments.push(p); return { ...p };
  }
  async getPayment(provider, ref) {
    const p = (this.payments || []).find(x => x.provider === provider && x.provider_ref === ref);
    return p ? { ...p } : null;
  }
  // Só a transição pending → (paid|failed|…) conta: repetir o webhook não libera duas vezes.
  async markPayment(provider, ref, status) {
    const p = (this.payments || []).find(x => x.provider === provider && x.provider_ref === ref && x.status === 'pending');
    if (!p) return null;
    p.status = status; if (status === 'paid') p.paid_at = new Date().toISOString();
    return { ...p };
  }
  // R39: reembolso/contestação — só paid → refunded (uma vez).
  async markRefund(provider, ref) {
    const p = (this.payments || []).find(x => x.provider === provider && x.provider_ref === ref && x.status === 'paid');
    if (!p) return null;
    p.status = 'refunded';
    return { ...p };
  }
  // R39: retira o que o pagamento reembolsado liberou (mesma regra da função 0010).
  async revokeEntitlement(userId, productId) {
    this.entitlements = this.entitlements || new Map();
    const e = { ...(this.entitlements.get(userId) || {}) };
    const cut = (iso, days) => iso ? new Date(new Date(iso).getTime() - days * 86400000).toISOString() : null;
    if (productId === 'founder') { e.is_founder = false; e.founder_since = null; e.club_expires_at = cut(e.club_expires_at, FOUNDER_CLUB_DAYS); }
    else if (productId === 'club_monthly') e.club_expires_at = cut(e.club_expires_at, CLUB_MONTH_DAYS);
    else return null;
    if (!e.club_expires_at || new Date(e.club_expires_at) <= new Date()) { e.club_active = false; e.club_expires_at = null; }
    e.updated_at = new Date().toISOString();
    this.entitlements.set(userId, e);
    return this.getEntitlements(userId);
  }
  // R39: quantos Fundadores existem (limite de vagas).
  async countFounders() {
    let n = 0; for (const e of (this.entitlements || new Map()).values()) if (e.is_founder) n++;
    return n;
  }
  // ---------- R31: identidade cosmética (avatar, selo, título, moldura) ----------
  async setCosmetics(userId, v) {
    const p = this.profiles.get(userId);
    if (!p) return { error: 'Perfil não encontrado.', code: 'profile_missing' };
    if (v.avatar_id !== undefined) p.avatar_id = v.avatar_id;
    if (v.badge !== undefined) p.profile_badge = v.badge;
    if (v.title !== undefined) p.profile_title = v.title;
    if (v.frame !== undefined) p.profile_frame = v.frame;
    p.updated_at = new Date().toISOString();
    return { profile: p };
  }
  // ---------- Cota de análise (0005): N por dia UTC; Club = ilimitado ----------
  async analysisUsage(userId, day) {
    this.analysis = this.analysis || new Map();
    const k = userId + '|' + day;
    return this.analysis.get(k) || 0;
  }
  async analysisConsume(userId, day, limit) {
    this.analysis = this.analysis || new Map();
    const k = userId + '|' + day;
    const used = this.analysis.get(k) || 0;
    if (used >= limit) return { ok: false, used };
    this.analysis.set(k, used + 1);
    return { ok: true, used: used + 1 };
  }
  // ---------- R32 · MARCHA REAL (0008): partidas por dia UTC; Club = ilimitado (decidido no backend) ----------
  async marchaUsage(userId, day) {
    this.marcha = this.marcha || new Map();
    return this.marcha.get(userId + '|' + day) || 0;
  }
  async marchaConsume(userId, day, limit) {
    this.marcha = this.marcha || new Map();
    const k = userId + '|' + day, used = this.marcha.get(k) || 0;
    if (used >= limit) return { ok: false, used };
    this.marcha.set(k, used + 1);
    return { ok: true, used: used + 1 };
  }
  // ---------- Escada de bots (0006): 1ª vitória por (conta, bot) ----------
  async getBotProgress(userId) {
    if (this.botProgressDisabled) { const e = new Error('Could not find the table bot_progress'); e.code = 'PGRST205'; throw e; }
    this.bots = this.bots || new Map();
    return [...(this.bots.get(userId) || new Map()).values()];
  }
  async recordBotVictory(userId, botId, info) {
    this.bots = this.bots || new Map();
    if (!this.bots.has(userId)) this.bots.set(userId, new Map());
    const m = this.bots.get(userId);
    if (m.has(botId)) return false;
    m.set(botId, { bot_id: botId, defeated_at: new Date().toISOString(), plies: info.plies, human_color: info.human_color });
    return true;
  }
  async saveAnalysis(userId, sum) {
    this.analyses = this.analyses || [];
    this.analyses.push({ user_id: userId, ...sum });
    return true;
  }
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
    for (const p of this.profiles.values()) if (p.nickname.toLowerCase().includes(q)) out.push(pub(p, this._ent(p.user_id)));
    return out.sort((a, b) => a.nickname.localeCompare(b.nickname)).slice(0, limit);
  }
  async getProfilesByIds(ids) { return ids.map(id => this.profiles.get(id)).filter(Boolean).map(p => pub(p, this._ent(p.user_id))); }
  _ent(uid) { return this.entitlements ? this.entitlements.get(uid) || null : null; }
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
  // ---------- Direitos (0005): tabela entitlements, escrita só pelo webhook/backend ----------
  async getEntitlements(userId) {
    try {
      const rows = await this.req('/entitlements?user_id=eq.' + encodeURIComponent(userId) + '&select=is_founder,club_active,club_expires_at');
      const e = rows[0] || {};
      const active = !!e.club_active && (!e.club_expires_at || new Date(e.club_expires_at) > new Date());
      return { is_founder: !!e.is_founder, club_active: active, club_expires_at: e.club_expires_at || null };
    } catch (e) {
      if (/42P01|PGRST205|does not exist|Could not find the table/.test(String(e.code) + ' ' + String(e.message))) return { is_founder: false, club_active: false, club_expires_at: null, not_configured: true };
      throw e;
    }
  }
  async setEntitlements() { throw new Error('entitlements só mudam pelo webhook de pagamento'); }
  // ---------- R31: direitos liberados pelo backend (função fraiha_grant_entitlement, migração 0007) ----------
  async grantEntitlement(userId, productId, source) {
    await this.req('/rpc/fraiha_grant_entitlement', { method: 'POST', body: JSON.stringify({ p_user: userId, p_product: productId, p_source: String(source || 'manual') }) });
    return this.getEntitlements(userId);
  }
  // ---------- R31: pagamentos (tabela payments, 0005; índice único provider+provider_ref na 0007) ----------
  async createPayment(row) {
    const rows = await this.req('/payments', { method: 'POST', headers: { Prefer: 'return=representation' },
      body: JSON.stringify({ user_id: row.user_id, product_id: row.product_id, method: row.method, provider: row.provider, provider_ref: row.provider_ref, amount_cents: row.amount_cents, status: 'pending' }) });
    return rows[0];
  }
  async getPayment(provider, ref) {
    const rows = await this.req('/payments?provider=eq.' + encodeURIComponent(provider) + '&provider_ref=eq.' + encodeURIComponent(ref) + '&select=payment_id,user_id,product_id,method,status,paid_at,amount_cents&limit=1');
    return rows[0] || null;
  }
  // R39: reembolso/contestação — só paid → refunded (uma vez).
  async markRefund(provider, ref) {
    const rows = await this.req('/payments?provider=eq.' + encodeURIComponent(provider) + '&provider_ref=eq.' + encodeURIComponent(ref) + '&status=eq.paid&select=payment_id,user_id,product_id,status',
      { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ status: 'refunded' }) });
    return rows[0] || null;
  }
  // R39: retira o direito de um pagamento reembolsado (função fraiha_revoke_entitlement, migração 0010).
  async revokeEntitlement(userId, productId) {
    await this.req('/rpc/fraiha_revoke_entitlement', { method: 'POST', body: JSON.stringify({ p_user: userId, p_product: productId }) });
    return this.getEntitlements(userId);
  }
  // R39: quantos Fundadores existem (limite de vagas). Sem a tabela (0005) conta 0.
  async countFounders() {
    try { const rows = await this.req('/entitlements?is_founder=eq.true&select=user_id'); return Array.isArray(rows) ? rows.length : 0; }
    catch (e) { if (/42P01|PGRST205|does not exist|Could not find the table/.test(String(e.code) + ' ' + String(e.message))) return 0; throw e; }
  }
  async markPayment(provider, ref, status) {
    const patch = { status }; if (status === 'paid') patch.paid_at = new Date().toISOString();
    const rows = await this.req('/payments?provider=eq.' + encodeURIComponent(provider) + '&provider_ref=eq.' + encodeURIComponent(ref) + '&status=eq.pending&select=payment_id,user_id,product_id,status',
      { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify(patch) });
    return rows[0] || null;
  }
  // ---------- R31: identidade cosmética. Sem a 0007 (colunas profile_badge/profile_title) só o avatar é salvo. ----------
  async setCosmetics(userId, v) {
    const body = {};
    if (v.avatar_id !== undefined) body.avatar_id = v.avatar_id;
    if (v.frame !== undefined) body.profile_frame = v.frame;
    const extra = {};
    if (v.badge !== undefined) extra.profile_badge = v.badge;
    if (v.title !== undefined) extra.profile_title = v.title;
    const path = '/profiles?user_id=eq.' + encodeURIComponent(userId) + '&select=*';
    try {
      const rows = await this.req(path, { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ ...body, ...extra }) });
      return { profile: rows[0] };
    } catch (e) {
      if (!SCHEMA_MISSING(e) || !Object.keys(extra).length) throw e;
      if (!Object.keys(body).length) return { error: 'Ícone e título ainda não configurados no servidor (migração 0007 pendente).', code: 'not_configured' };
      const rows = await this.req(path, { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify(body) });
      return { profile: rows[0], partial: true };
    }
  }
  // ---------- Escada de bots (0006). Sem a tabela → erro PGRST205/42P01 (tratado como "não configurado"). ----------
  async getBotProgress(userId) {
    return await this.req('/bot_progress?user_id=eq.' + encodeURIComponent(userId) + '&select=bot_id,defeated_at&order=defeated_at.asc');
  }
  async recordBotVictory(userId, botId, info) {
    const rows = await this.req('/bot_progress?on_conflict=user_id,bot_id', { method: 'POST', headers: { Prefer: 'resolution=ignore-duplicates,return=representation' },
      body: JSON.stringify({ user_id: userId, bot_id: botId, plies: Number(info.plies) || 0, human_color: info.human_color === 'b' ? 'b' : 'w' }) });
    return Array.isArray(rows) && rows.length > 0;
  }
  async saveAnalysis(userId, sum) {
    const row = { user_id: userId, match_id: UUID_RE.test(String(sum.match_id || '')) ? sum.match_id : null, mode: String(sum.mode || ''),
      played_at: sum.played_at ? new Date(Number(sum.played_at) * 1000).toISOString() : null, color: sum.color || null, result: sum.result || null,
      accuracy: Number(sum.accuracy) || 0, counts: sum.counts || {}, critical_ply: Number(sum.critical_ply), best_ply: Number(sum.best_ply),
      moves: Array.isArray(sum.moves) ? sum.moves.slice(0, 400) : [], engine: String(sum.engine || '').slice(0, 60), depth: Number(sum.depth) || 0 };
    await this.req('/analysis_history', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify(row) });
    return true;
  }
  // ---------- Cota de análise (0005): fraiha_analysis_consume decide no banco (relógio do servidor) ----------
  async analysisUsage(userId, day) {
    try {
      const rows = await this.req('/analysis_usage?user_id=eq.' + encodeURIComponent(userId) + '&day=eq.' + day + '&select=used');
      return rows[0] ? Number(rows[0].used) : 0;
    } catch (e) {
      if (/42P01|PGRST205|does not exist|Could not find the table/.test(String(e.code) + ' ' + String(e.message))) return 0;
      throw e;
    }
  }
  async analysisConsume(userId, day, limit) {
    try {
      const used = await this.req('/rpc/fraiha_analysis_consume', { method: 'POST', body: JSON.stringify({ p_user: userId, p_day: day, p_limit: limit }) });
      return { ok: Number(used) >= 0, used: Math.abs(Number(used)) };
    } catch (e) {
      if (/42P01|PGRST205|does not exist|Could not find the (table|function)/.test(String(e.code) + ' ' + String(e.message))) return { ok: false, used: 0, not_configured: true };
      throw e;
    }
  }
  // ---------- R32 · MARCHA REAL (0008): fraiha_marcha_consume decide no banco. Sem a 0008 → not_configured ----------
  async getModeStats(userId) {
    try {
      const rows = await this.req('/mode_stats?user_id=eq.' + encodeURIComponent(userId) + '&select=mode_id,wins,losses,draws');
      const o = emptyModeStats();
      for (const r of rows) if (o[r.mode_id]) o[r.mode_id] = { wins: Number(r.wins) || 0, losses: Number(r.losses) || 0, draws: Number(r.draws) || 0 };
      return o;
    } catch (e) { if (SCHEMA_MISSING(e)) return { not_configured: true }; throw e; }
  }
  async recordModeResult(userId, mode, result) {
    if (!STAT_MODES.includes(mode) || !['win', 'loss', 'draw'].includes(result)) return;
    try { await this.req('/rpc/fraiha_mode_record', { method: 'POST', body: JSON.stringify({ p_user: userId, p_mode: mode, p_result: result }) }); }
    catch (e) { if (!SCHEMA_MISSING(e)) throw e; }
  }
  async marchaUsage(userId, day) {
    try {
      const rows = await this.req('/marcha_usage?user_id=eq.' + encodeURIComponent(userId) + '&day=eq.' + day + '&select=used');
      return rows[0] ? Number(rows[0].used) : 0;
    } catch (e) { if (SCHEMA_MISSING(e)) return { not_configured: true }; throw e; }
  }
  async marchaConsume(userId, day, limit) {
    try {
      const used = await this.req('/rpc/fraiha_marcha_consume', { method: 'POST', body: JSON.stringify({ p_user: userId, p_day: day, p_limit: limit }) });
      return { ok: Number(used) >= 0, used: Math.abs(Number(used)) };
    } catch (e) { if (SCHEMA_MISSING(e)) return { ok: false, used: 0, not_configured: true }; throw e; }
  }
  // ---------- Amigos (0002_fraiha_social). Todos os ids já validados como UUID pelo serviço. ----------
  // R31: perfis públicos com selo/título/moldura + direitos (embed entitlements, 1:1 por user_id).
  // Sem a migração 0007 (ou sem 0005) cai para as colunas antigas e tenta de novo em 5 minutos.
  async _publicProfiles(filter) {
    const base = 'user_id,nickname,avatar_id,avatar_url';
    if (!this.richUntil || Date.now() > this.richUntil) {
      try {
        const rows = await this.req('/profiles?' + filter.replace('{cols}', base + ',profile_frame,profile_badge,profile_title,entitlements(is_founder,club_active,club_expires_at)'));
        this.richUntil = 0;
        return rows.map(p => pub(p, Array.isArray(p.entitlements) ? p.entitlements[0] : p.entitlements));
      } catch (e) {
        if (!SCHEMA_MISSING(e)) throw e;
        this.richUntil = Date.now() + 5 * 60e3;
      }
    }
    return (await this.req('/profiles?' + filter.replace('{cols}', base))).map(p => pub(p, null));
  }
  async searchProfiles(query, limit = 20) {
    return this._publicProfiles('nickname=ilike.' + encodeURIComponent('*' + query + '*') + '&select={cols}&order=nickname.asc&limit=' + limit);
  }
  async getProfilesByIds(ids) {
    const ok = ids.filter(id => UUID_RE.test(id));
    if (!ok.length) return [];
    return this._publicProfiles('user_id=in.(' + ok.join(',') + ')&select={cols}');
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

module.exports = { STAT_MODES, MemoryStore, SupabaseStore, validateNickname, cleanNickname, nextNickChange, NICK_COOLDOWN_MS, MODES, AVATARS, emptyStats, UUID_RE, pub, extendClub, FOUNDER_CLUB_DAYS };
