'use strict';
// R157 · TORNEIOS DE EVENTO (XADREZ) com CÓDIGO de inscrição. O dono cria o torneio no Admin (nome, código, ritmo,
// data, vagas), passa o código para as pessoas e só quem digitar o código entra. O Admin fecha as inscrições,
// monta as CHAVES (eliminação simples, sorteio; quem sobra passa direto) e marca o vencedor de cada partida.
// Por enquanto as partidas são combinadas entre os jogadores (convite de amigo no ritmo do torneio) e o Admin
// registra o resultado; a ligação automática partida→chave fica para depois.
//   jogo: tev_join { code } → tev_state | tev_error · tev_list → tev_state · tev_leave { id } → tev_state
//   admin (online_v021/admin/service.js): lista, salvar, montar chaves, marcar vencedor.
const crypto = require('crypto');
const { CASUAL_MODES } = require('../ranked/config');
const missing = e => /42P01|42703|PGRST200|PGRST202|PGRST204|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CODE = /^[A-Z0-9]{4,20}$/;
const STATUS = ['open', 'closed', 'running', 'finished', 'cancelled'];
const STATUS_TXT = { open: 'INSCRIÇÕES ABERTAS', closed: 'INSCRIÇÕES ENCERRADAS', running: 'EM ANDAMENTO', finished: 'ENCERRADO', cancelled: 'CANCELADO' };

// ---------- chaves (eliminação simples) ----------
// rounds[r] = [{ a, b, winner }]; a/b = user_id ou null (sem adversário = passa direto). Puro, testável.
function makeBracket(players, rand = Math.random) {
  const ids = players.slice();
  for (let i = ids.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [ids[i], ids[j]] = [ids[j], ids[i]]; }
  let size = 1; while (size < Math.max(2, ids.length)) size *= 2;
  // espalha os "passa direto" (cada vaga vazia fica contra um jogador, nunca vazia contra vazia)
  const slots = new Array(size).fill(null);
  const byes = size - ids.length;
  let k = 0;
  for (let m = 0; m < size / 2; m++) {
    slots[m * 2] = ids[k++] ?? null;
    slots[m * 2 + 1] = m < byes ? null : (ids[k++] ?? null);
  }
  const rounds = [[]];
  for (let m = 0; m < size / 2; m++) rounds[0].push({ a: slots[m * 2], b: slots[m * 2 + 1], winner: null });
  for (let n = size / 4; n >= 1; n /= 2) rounds.push(Array.from({ length: n }, () => ({ a: null, b: null, winner: null })));
  advance({ rounds });
  return { rounds, created_at: new Date().toISOString() };
}
// leva vencedores (e quem passou direto) para a rodada seguinte
function advance(br) {
  for (let r = 0; r < br.rounds.length; r++) {
    for (let m = 0; m < br.rounds[r].length; m++) {
      const x = br.rounds[r][m];
      if (!x.winner && r === 0 && ((x.a && !x.b) || (!x.a && x.b))) x.winner = x.a || x.b;
      if (r + 1 < br.rounds.length) {
        const nx = br.rounds[r + 1][Math.floor(m / 2)];
        nx[m % 2 === 0 ? 'a' : 'b'] = x.winner || null;
        if (nx.winner && nx.winner !== nx.a && nx.winner !== nx.b) nx.winner = null;   // resultado desfeito antes
      }
    }
  }
  return br;
}
function champion(br) { const last = br && br.rounds[br.rounds.length - 1]; return last && last[0] ? last[0].winner : null; }
function setWinner(br, r, m, uid) {
  const x = br && br.rounds[r] && br.rounds[r][m];
  if (!x) return { error: 'no_match' };
  if (uid && uid !== x.a && uid !== x.b) return { error: 'not_in_match' };
  if (!x.a || !x.b) return { error: 'match_not_ready' };
  x.winner = uid || null;
  advance(br);
  return { ok: true };
}

class Events {
  constructor({ backend, send, now = () => Date.now() }) {
    this.backend = backend; this.send = send; this.now = now; this.offUntil = 0; this.joins = new Map();
  }
  get store() { return this.backend.store; }
  ok() { return !!(this.store && this.store.evList) && this.offUntil <= this.now(); }
  off(e, where) { if (missing(e)) { this.offUntil = this.now() + 600e3; return true; } console.error('[eventos] ' + where, e && e.message); return false; }

  async names(ids) {
    const ok = [...new Set(ids.filter(id => UUID.test(String(id || ''))))];
    if (!ok.length || !this.store.getProfilesByIds) return {};
    const ps = await this.store.getProfilesByIds(ok);
    return Object.fromEntries(ps.map(p => [p.user_id, p.nickname]));
  }
  // visão pública de um torneio (para quem está inscrito)
  async view(ev, uid) {
    const entries = await this.store.evEntries(ev.id);
    const br = ev.bracket || null;
    const ids = entries.map(e => e.user_id);
    if (br) for (const r of br.rounds) for (const x of r) ids.push(x.a, x.b);
    const nm = await this.names(ids);
    const who = id => id ? (nm[id] || 'Jogador') : null;
    const mode = CASUAL_MODES[ev.mode];
    return { id: ev.id, name: ev.name, game: ev.game, status: ev.status, status_text: STATUS_TXT[ev.status] || ev.status,
      mode: ev.mode, mode_name: mode ? mode.name : ev.mode, starts_at: ev.starts_at || null, notes: ev.notes || '',
      players: entries.length, max_players: ev.max_players, joined: entries.some(e => e.user_id === uid),
      entrants: entries.map(e => who(e.user_id)),
      bracket: br ? br.rounds.map(r => r.map(x => ({ a: who(x.a), b: who(x.b), winner: who(x.winner), mine: !!uid && (x.a === uid || x.b === uid) }))) : null,
      champion: br ? who(champion(br)) : null };
  }
  async mine(uid) {
    const ids = await this.store.evOfUser(uid);
    const out = [];
    for (const id of ids) { const ev = await this.store.evGet(id); if (ev && ev.status !== 'cancelled') out.push(await this.view(ev, uid)); }
    return out;
  }
  fail(ws, code, message) { this.send(ws, { type: 'tev_error', code, message }); }
  async handle(ws, m) {
    const a = String(m.type || '');
    const uid = ws.user && ws.profile ? ws.user.id : null;
    if (!uid) return this.fail(ws, 'auth_required', 'Entre na sua conta para participar de torneios.');
    if (!this.ok()) return this.send(ws, { type: 'tev_state', available: false, events: [] });
    try {
      if (a === 'tev_join') {
        const t = this.now(), last = this.joins.get(uid) || [];
        const recent = last.filter(x => t - x < 60e3);
        if (recent.length >= 8) return this.fail(ws, 'rate_limited', 'Muitas tentativas. Espere um minuto e tente de novo.');
        recent.push(t); this.joins.set(uid, recent);
        const code = String(m.code || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
        if (!CODE.test(code)) return this.fail(ws, 'bad_code', 'Código inválido. Confira com quem organiza o torneio.');
        const ev = await this.store.evByCode(code);
        if (!ev || ev.status === 'cancelled') return this.fail(ws, 'not_found', 'Nenhum torneio com esse código.');
        const entries = await this.store.evEntries(ev.id);
        if (!entries.some(e => e.user_id === uid)) {
          if (ev.status !== 'open') return this.fail(ws, 'closed', 'As inscrições deste torneio já encerraram.');
          if (entries.length >= ev.max_players) return this.fail(ws, 'full', 'O torneio já está com todas as vagas preenchidas.');
          await this.store.evJoin(ev.id, uid);
        }
        return this.send(ws, { type: 'tev_state', available: true, joined_id: ev.id, events: await this.mine(uid) });
      }
      if (a === 'tev_leave') {
        const ev = await this.store.evGet(String(m.id || ''));
        if (!ev) return this.fail(ws, 'not_found', 'Torneio não encontrado.');
        if (ev.status !== 'open') return this.fail(ws, 'closed', 'As chaves já foram montadas: fale com quem organiza para sair.');
        await this.store.evLeave(ev.id, uid);
        return this.send(ws, { type: 'tev_state', available: true, events: await this.mine(uid) });
      }
      if (a === 'tev_list') return this.send(ws, { type: 'tev_state', available: true, events: await this.mine(uid) });
    } catch (e) {
      if (this.off(e, a)) return this.send(ws, { type: 'tev_state', available: false, events: [] });
      return this.fail(ws, 'server_error', 'Erro temporário no servidor. Tente novamente.');
    }
  }

  // ---------- Admin ----------
  async adminList() {
    if (!this.ok()) return { available: false, error: 'migration_0021_missing' };
    try {
      const evs = await this.store.evList();
      const items = [];
      for (const ev of evs) {
        const entries = await this.store.evEntries(ev.id);
        const ids = entries.map(e => e.user_id);
        if (ev.bracket) for (const r of ev.bracket.rounds) for (const x of r) ids.push(x.a, x.b);
        const nm = await this.names(ids);
        items.push({ ...ev, entrants: entries.map(e => ({ user_id: e.user_id, nickname: nm[e.user_id] || 'Jogador', joined_at: e.joined_at })), names: nm,
          champion: ev.bracket ? champion(ev.bracket) : null });
      }
      return { available: true, items, modes: Object.keys(CASUAL_MODES).map(k => ({ id: k, name: CASUAL_MODES[k].name })), statuses: STATUS };
    } catch (e) { if (this.off(e, 'admin list')) return { available: false, error: 'migration_0021_missing' }; throw e; }
  }
  validate(b, cur) {
    const code = String(b.code ?? (cur && cur.code) ?? '').trim().toUpperCase();
    const name = String(b.name ?? (cur && cur.name) ?? '').trim();
    const mode = String(b.mode ?? (cur && cur.mode) ?? 'casual_10min');
    const max = Number(b.max_players ?? (cur && cur.max_players) ?? 16);
    const status = String(b.status ?? (cur && cur.status) ?? 'open');
    const notes = String(b.notes ?? (cur && cur.notes) ?? '').slice(0, 500);
    let starts = b.starts_at === undefined ? (cur ? cur.starts_at : null) : (b.starts_at || null);
    if (!CODE.test(code)) return { error: 'invalid_code' };
    if (name.length < 3 || name.length > 60) return { error: 'invalid_name' };
    if (!CASUAL_MODES[mode]) return { error: 'invalid_mode' };
    if (!Number.isInteger(max) || max < 2 || max > 256) return { error: 'invalid_max' };
    if (!STATUS.includes(status)) return { error: 'invalid_status' };
    if (starts && isNaN(Date.parse(starts))) return { error: 'invalid_date' };
    if (starts) starts = new Date(starts).toISOString();
    return { value: { code, name, game: 'chess', mode, max_players: max, status, notes, starts_at: starts } };
  }
  async adminSave(id, body) {
    const cur = id ? await this.store.evGet(id) : null;
    if (id && !cur) return { status: 404, body: { error: 'not_found' } };
    const v = this.validate(body || {}, cur);
    if (v.error) return { status: 400, body: { error: v.error } };
    try {
      const row = await this.store.evSave(cur ? { ...v.value, id: cur.id } : v.value);
      return { status: 200, body: { item: row }, before: cur, after: row };
    } catch (e) {
      if (String(e && e.code) === '23505') return { status: 409, body: { error: 'code_taken' } };
      if (this.off(e, 'admin save')) return { status: 503, body: { error: 'migration_0021_missing' } };
      throw e;
    }
  }
  async adminBracket(id) {
    const ev = await this.store.evGet(id);
    if (!ev) return { status: 404, body: { error: 'not_found' } };
    const entries = await this.store.evEntries(id);
    if (entries.length < 2) return { status: 400, body: { error: 'not_enough_players' } };
    const bracket = makeBracket(entries.map(e => e.user_id), () => crypto.randomInt(0, 1 << 30) / (1 << 30));
    const row = await this.store.evSave({ id, bracket, status: 'running' });
    return { status: 200, body: { item: row }, before: ev.bracket || null, after: bracket };
  }
  async adminResult(id, b) {
    const ev = await this.store.evGet(id);
    if (!ev || !ev.bracket) return { status: 404, body: { error: 'no_bracket' } };
    const br = JSON.parse(JSON.stringify(ev.bracket));
    const r = setWinner(br, Number(b.round), Number(b.match), b.winner ? String(b.winner) : null);
    if (r.error) return { status: 400, body: { error: r.error } };
    const champ = champion(br);
    const row = await this.store.evSave({ id, bracket: br, status: champ ? 'finished' : 'running' });
    return { status: 200, body: { item: row }, before: ev.bracket.rounds[b.round][b.match], after: br.rounds[b.round][b.match] };
  }
}
module.exports = { Events, makeBracket, setWinner, advance, champion };
