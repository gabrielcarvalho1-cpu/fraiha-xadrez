'use strict';
// R96 · RANKING (botão do troféu na Home). Placares públicos por modo, montados no servidor.
//   Xadrez Ranked: um placar por fila (ranked_3min Relâmpago, ranked_5min Rápida, ranked_10min Normal,
//   ranked_20min Convencional), a partir de ranked_stats (0001).
//   XEQUE e MARCHA REAL online: um placar cada, a partir de mode_stats (0009). Sem a 0009 → not_configured.
// Ordem: APROVEITAMENTO (vitória = 1 ponto, empate = ½, sobre o total de partidas) — pedido do dono: "a média,
// só por quantidade de vitórias não seria justo". Para 1 vitória em 1 partida não virar 100% no topo, só entra
// quem tem MIN_MATCHES partidas; desempate: mais partidas, mais vitórias, (xadrez) mais PL.
// Cache por placar (TTL_MS): a lista inteira é lida e ordenada no Node uma vez por minuto, no máximo.
const BOARDS = {
  ranked_3min: 'ranked', ranked_5min: 'ranked', ranked_10min: 'ranked', ranked_20min: 'ranked',
  xeque: 'mode', marcha: 'mode',
};
const MIN_MATCHES = 5;
const TOP = 50;
const TTL_MS = 60000;

const total = r => (Number(r.wins) || 0) + (Number(r.losses) || 0) + (Number(r.draws) || 0);
const rateOf = r => { const n = total(r); return n ? ((Number(r.wins) || 0) + 0.5 * (Number(r.draws) || 0)) / n : 0; };

function rank(rows) {
  return rows
    .map(r => ({ user_id: String(r.user_id), wins: Number(r.wins) || 0, losses: Number(r.losses) || 0, draws: Number(r.draws) || 0,
      league: r.league === undefined ? null : Number(r.league) || 0, pl: r.pl === undefined ? null : Number(r.pl) || 0 }))
    .map(r => ({ ...r, matches: total(r), rate: rateOf(r) }))
    .filter(r => r.matches >= MIN_MATCHES)
    .sort((a, b) => b.rate - a.rate || b.matches - a.matches || b.wins - a.wins || (b.pl || 0) - (a.pl || 0) ||
      (b.league || 0) - (a.league || 0) || (a.user_id < b.user_id ? -1 : a.user_id > b.user_id ? 1 : 0));
}

class Leaderboard {
  constructor({ send, backend, now = () => Date.now() }) {
    this.send = send; this.backend = backend; this.now = now;
    this.cache = new Map();     // board -> { at, list, notConfigured }
    this.loading = new Map();   // board -> Promise (pedidos simultâneos dividem a mesma leitura)
  }
  get store() { return this.backend && this.backend.store; }
  async sorted(board) {
    const c = this.cache.get(board);
    if (c && this.now() - c.at < TTL_MS) return c;
    if (this.loading.has(board)) return this.loading.get(board);
    const p = (async () => {
      const st = this.store;
      const raw = st && st.leaderboardRows ? await st.leaderboardRows(board, BOARDS[board], MIN_MATCHES) : { not_configured: true };
      const entry = raw && raw.not_configured ? { at: this.now(), list: [], notConfigured: true } : { at: this.now(), list: rank(raw || []), notConfigured: false };
      this.cache.set(board, entry);
      return entry;
    })();
    this.loading.set(board, p);
    try { return await p; } finally { this.loading.delete(board); }
  }
  invalidate(board) { if (board) this.cache.delete(board); else this.cache.clear(); }
  view(r, pos, profile) {
    return { pos, user_id: r.user_id, nickname: profile ? profile.nickname : 'Jogador', avatar_id: profile ? profile.avatar_id : '',
      avatar_url: profile ? profile.avatar_url || null : null, frame: profile ? profile.frame || '' : '',
      wins: r.wins, losses: r.losses, draws: r.draws, matches: r.matches, rate: Math.round(r.rate * 1000) / 10,
      league: r.league, pl: r.pl };
  }
  async build(board, uid) {
    const { list, notConfigured } = await this.sorted(board);
    const out = { type: 'leaderboard', board, available: !notConfigured, min_matches: MIN_MATCHES, rows: [], me: null };
    if (notConfigured) return out;
    const top = list.slice(0, TOP);
    const idx = uid ? list.findIndex(r => r.user_id === uid) : -1;
    const ids = top.map(r => r.user_id);
    if (idx >= TOP) ids.push(uid);
    const st = this.store;
    const profiles = ids.length && st && st.getProfilesByIds ? await st.getProfilesByIds(ids) : [];
    const byId = new Map(profiles.map(p => [String(p.user_id), p]));
    out.rows = top.map((r, i) => this.view(r, i + 1, byId.get(r.user_id)));
    if (idx >= 0) out.me = this.view(list[idx], idx + 1, byId.get(uid));
    else if (uid && st) {
      // fora do placar: mostra o próprio placar e quantas partidas faltam para entrar
      let mine = null;
      try {
        if (BOARDS[board] === 'ranked' && st.getRankedStats) mine = (await st.getRankedStats(uid))[board];
        else if (st.getModeStats) { const all = await st.getModeStats(uid); mine = all && !all.not_configured ? all[board] : null; }
      } catch (e) { mine = null; }
      if (mine) {
        const r = { user_id: uid, wins: Number(mine.wins) || 0, losses: Number(mine.losses) || 0, draws: Number(mine.draws) || 0 };
        r.matches = total(r);
        out.me = { pos: 0, user_id: uid, wins: r.wins, losses: r.losses, draws: r.draws, matches: r.matches,
          rate: Math.round(rateOf(r) * 1000) / 10, missing: Math.max(0, MIN_MATCHES - r.matches) };
      }
    }
    return out;
  }
  async handle(ws, m) {
    const board = String(m.board || '');
    if (!BOARDS[board]) return this.send(ws, { type: 'leaderboard', board, available: false, error: 'invalid_board', rows: [], me: null });
    const uid = ws.user && ws.profile ? ws.user.id : null;   // convidado vê o placar, sem "sua posição"
    try { return this.send(ws, await this.build(board, uid)); }
    catch (e) {
      console.error('leaderboard', board, e && e.message);
      return this.send(ws, { type: 'leaderboard', board, available: false, error: 'server_error', rows: [], me: null });
    }
  }
}

module.exports = { Leaderboard, BOARDS, MIN_MATCHES, TOP, rank };
