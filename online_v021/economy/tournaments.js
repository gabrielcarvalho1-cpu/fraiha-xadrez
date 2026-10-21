'use strict';
// R118 · TORNEIO DA SEMANA de XEQUE e de MARCHA REAL — entrada grátis, prêmio em Coroas. O servidor é a autoridade.
//   • semana = segunda 00:00 → domingo 23:59 (horário de Brasília);
//   • mesa ONLINE terminada com pelo menos 2 pessoas (contas): vitória 3 pontos, partida jogada até o fim 1;
//     até 8 partidas por dia (por modo) contam — o resto da diversão é livre, mas não soma;
//   • desempate: mais vitórias, depois quem chegou primeiro;
//   • prêmio (pago sozinho quando a semana vira, uma vez só): 1º 500 · 2º 300 · 3º 200 · 4º a 10º 100 Coroas,
//     × min(participantes/10, 1) (R173: com 2 contas, 20%; com 10 ou mais, integral).
//   tourn_get { game } → tourn_state { available, game, week, ends_in_s, top[], me, prizes, rules }
const GAMES = ['xeque', 'marcha'];
const NAMES = { xeque: 'XEQUE', marcha: 'MARCHA REAL' };
const WIN_PTS = 3, PLAY_PTS = 1, DAILY_GAMES = 8;
const PRIZES = [500, 300, 200, 100, 100, 100, 100, 100, 100, 100];
// R173 · prêmio PROPORCIONAL à participação (auditoria Orca: 2 contas levavam 1.600 Coroas/semana):
//   fator = min(contas distintas que pontuaram no modo na semana / 10, 1). Só muda QUANTO paga: placar,
//   posições e pontos seguem iguais. Conta inteira (sem ponto flutuante), arredonda para baixo, nunca passa do integral.
const FULL_AT = 10;
const prizeFor = (i, players) => { const p = PRIZES[i] || 0; const n = Math.max(0, Math.min(FULL_AT, players | 0)); return Math.floor(p * n / FULL_AT); };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const missing = e => /42P01|42703|42883|PGRST200|PGRST202|PGRST204|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));
const BRT = 3 * 3600e3, WEEK = 7 * 86400e3;

// segunda-feira 00:00 de Brasília da semana de `ms` (em ms UTC)
function weekStart(ms) {
  const d = new Date(ms - BRT);
  const dow = (d.getUTCDay() + 6) % 7;   // 0 = segunda
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - dow) + BRT;
}
// código ISO da semana (ex.: 2026-W42), pela quinta-feira da semana
function weekOf(ms) {
  const thu = new Date(weekStart(ms) - BRT + 3 * 86400e3);
  const y = thu.getUTCFullYear();
  const jan4 = Date.UTC(y, 0, 4), jan4dow = (new Date(jan4).getUTCDay() + 6) % 7;
  const w1 = jan4 - jan4dow * 86400e3;
  return y + '-W' + String(Math.floor((thu.getTime() - w1) / WEEK) + 1).padStart(2, '0');
}
const dayOf = ms => new Date(ms - BRT).toISOString().slice(0, 10);

class Tournaments {
  constructor({ backend, send, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.backend = backend; this.send = send; this.now = now; this.log = log;
    this.offUntil = 0;
    this.timer = null;
  }
  get store() { return this.backend.store; }
  ok() { return !!(this.store && this.store.tournAdd && this.store.crownAward) && this.offUntil <= this.now(); }
  off(e, where) { if (missing(e)) { this.offUntil = this.now() + 600e3; return; } console.error('[torneio] ' + where, e && e.message); }
  rules() { return { win: WIN_PTS, play: PLAY_PTS, daily_games: DAILY_GAMES, prizes: PRIZES, full_at: FULL_AT }; }

  start() {
    if (this.timer) return;
    const tick = () => this.payDue().catch(e => this.off(e, 'pagamento'));
    setTimeout(tick, 15e3).unref?.();
    this.timer = setInterval(tick, 3600e3);
    if (this.timer.unref) this.timer.unref();
  }
  stop() { clearInterval(this.timer); this.timer = null; }

  // Mesa de XEQUE/MARCHA terminada. results = [{ uid, win, left }]
  async onTable(game, results) {
    if (!this.ok() || !GAMES.includes(game)) return;
    const humans = results.filter(r => UUID.test(String(r.uid || '')));
    if (new Set(humans.map(r => r.uid)).size < 2) return;   // só contra outra pessoa
    const week = weekOf(this.now()), day = dayOf(this.now());
    for (const r of humans) {
      if (r.left) continue;
      try {
        const c = await this.store.crownBump(r.uid, day, { ['t_' + game]: 1 });
        if ((c['t_' + game] || 0) > DAILY_GAMES) continue;
        await this.store.tournAdd(week, game, r.uid, r.win ? WIN_PTS : PLAY_PTS, !!r.win);
      } catch (e) { this.off(e, 'pontos'); return; }
    }
  }

  async handle(ws, m) {
    if (String(m.type) !== 'tourn_get') return;
    const game = GAMES.includes(String(m.game)) ? String(m.game) : 'xeque';
    const uid = ws.user && ws.profile ? ws.user.id : null;
    const base = { type: 'tourn_state', game, name: NAMES[game], rules: this.rules(), week: weekOf(this.now()),
      ends_in_s: Math.max(0, Math.round((weekStart(this.now()) + WEEK - this.now()) / 1000)) };
    if (!this.ok()) return this.send(ws, { ...base, available: false });
    try { this.send(ws, { ...base, ...(await this.board(base.week, game, uid)), available: true }); }
    catch (e) { this.off(e, 'placar'); this.send(ws, { ...base, available: false }); }
  }

  async board(week, game, uid) {
    const rows = await this.store.tournTop(week, game, 200);
    const top10 = rows.slice(0, 10);
    const profs = top10.length && this.store.getProfilesByIds ? await this.store.getProfilesByIds(top10.map(r => r.user_id)) : [];
    const by = Object.fromEntries(profs.map(p => [p.user_id, p]));
    const top = top10.map((r, i) => ({ pos: i + 1, user_id: r.user_id, nickname: by[r.user_id] ? by[r.user_id].nickname : 'Jogador',
      avatar_id: by[r.user_id] ? by[r.user_id].avatar_id : '', points: r.points, wins: r.wins, games: r.games, prize: prizeFor(i, rows.length) }));
    let me = null;
    if (uid) {
      const i = rows.findIndex(r => r.user_id === uid);
      me = i >= 0 ? { pos: i + 1, points: rows[i].points, wins: rows[i].wins, games: rows[i].games, prize: prizeFor(i, rows.length) } : { pos: null, points: 0, wins: 0, games: 0, prize: 0 };
    }
    return { top, me, players: rows.length, prize_pct: Math.round(100 * Math.min(FULL_AT, rows.length) / FULL_AT) };
  }

  // Paga a semana anterior (e a de antes, se o servidor ficou fora) — idempotente pelo extrato das Coroas.
  async payDue() {
    if (!this.ok()) return;
    for (const back of [1, 2]) {
      const week = weekOf(weekStart(this.now()) - back * WEEK + 3600e3);
      for (const game of GAMES) {
        const rows = await this.store.tournTop(week, game, PRIZES.length);   // até 10 linhas = min(participantes, 10)
        for (let i = 0; i < rows.length; i++) {
          if (!PRIZES[i]) break;
          const prize = prizeFor(i, rows.length); if (!prize) continue;
          const r = rows[i];
          const paid = await this.store.crownAward(r.user_id, prize, 'tournament', week + ':' + game);
          if (paid === null) continue;   // já pago
          this.log('[torneio] ' + JSON.stringify({ week, game, pos: i + 1, user: r.user_id, prize }));
          if (this.backend.crowns) await this.backend.crowns.notify(r.user_id, prize, [`Torneio da Semana · ${NAMES[game]}: ${i + 1}º lugar +${prize}`]);
        }
      }
    }
  }
}

module.exports = { Tournaments, weekOf, weekStart, dayOf, PRIZES, prizeFor, FULL_AT, WIN_PTS, PLAY_PTS, DAILY_GAMES, GAMES };
