'use strict';
// R120 · PASSE DA TEMPORADA. Temporada = mês do calendário (horário de Brasília), 30 níveis de 150 XP.
// XP: vitória online 30 · partida online 10 (até 300 XP/dia de partidas) · missão do dia 50 · entrada do dia 20.
// Duas faixas: GRÁTIS (todos) e CLUB (faixa premium, liberada para quem tem Club FRAIHA ativo — inclusive
// os níveis já alcançados antes de assinar, entregues na hora). Recompensas entregues SOZINHAS ao subir de nível.
// Sem migration nova: XP em crown_daily (dia = 1º do mês, contador pass_xp), recompensas pelo extrato das Coroas
// (motivo 'pass', ref temporada:nível:faixa — nunca paga duas vezes) e itens pela Loja (crownBuy com preço 0).
const Shop = require('./store_catalog');

const LEVELS = 30, XP_PER_LEVEL = 150;
const XP = { win: 30, play: 10, mission: 50, daily: 20 }, GAME_XP_CAP = 300;
const BRT = 3 * 3600e3;
const MONTHS = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const missing = e => /42P01|42703|42883|PGRST200|PGRST202|PGRST204|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));

const seasonOf = ms => new Date(ms - BRT).toISOString().slice(0, 7);          // 2026-10
const seasonDay = s => s + '-01';
const seasonName = s => 'Temporada de ' + MONTHS[Number(s.slice(5, 7)) - 1];
const seasonEnd = s => { const y = Number(s.slice(0, 4)), m = Number(s.slice(5, 7)); return Date.UTC(m === 12 ? y + 1 : y, m === 12 ? 0 : m, 1) + BRT; };
const levelOf = xp => Math.min(LEVELS, Math.floor(Math.max(0, xp) / XP_PER_LEVEL));

// itens da faixa CLUB giram a cada temporada (emote no nível 10, título no 20, moldura no 30)
function seasonItems(s) {
  const idx = Number(s.slice(0, 4)) * 12 + Number(s.slice(5, 7));
  const pick = kind => { const l = Shop.ofKind(kind); return l[idx % l.length]; };
  return { 10: pick('emote'), 20: pick('title'), 30: pick('frame') };
}
// recompensas de cada nível: { free: {crowns}|null, club: {crowns}|{item} }
function rewards(s) {
  const items = seasonItems(s);
  const out = [];
  for (let l = 1; l <= LEVELS; l++) {
    const free = l === 15 ? { crowns: 100 } : l === LEVELS ? { crowns: 200 } : l % 3 === 0 ? { crowns: 30 } : null;
    const club = items[l] ? { item: items[l], name: Shop.BY_ID[items[l]].name, kind: Shop.BY_ID[items[l]].kind } : { crowns: l % 5 === 0 ? 60 : 20 };
    out.push({ level: l, free, club });
  }
  return out;
}

class SeasonPass {
  constructor({ backend, send, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.backend = backend; this.send = send; this.now = now; this.log = log;
    this.offUntil = 0; this.busy = new Map();
  }
  get store() { return this.backend.store; }
  ok() { return !!(this.store && this.store.crownBump && this.store.crownAward) && this.offUntil <= this.now(); }
  off(e, where) { if (missing(e)) { this.offUntil = this.now() + 600e3; return; } console.error('[passe] ' + where, e && e.message); }
  async club(uid) {
    const ent = this.store.getEntitlements ? await this.store.getEntitlements(uid).catch(() => null) : null;
    return !!(ent && ent.club_active && (!ent.club_expires_at || new Date(ent.club_expires_at) > new Date(this.now())));
  }

  // XP ganho (kind: win | play | mission | daily). Devolve as linhas de recompensa entregues (para o aviso).
  async add(uid, kind, n = 1) {
    if (!this.ok() || !UUID.test(String(uid || '')) || !XP[kind]) return [];
    const prev = this.busy.get(uid) || Promise.resolve();
    const job = prev.then(() => this._add(uid, kind, n)).catch(e => { this.off(e, 'xp'); return []; });
    this.busy.set(uid, job.finally(() => { if (this.busy.get(uid) === job) this.busy.delete(uid); }));
    return job;
  }
  async _add(uid, kind, n) {
    const s = seasonOf(this.now());
    let xp = XP[kind] * n;
    if (kind === 'win' || kind === 'play') {   // limite diário de XP de partidas
      const day = new Date(this.now() - BRT).toISOString().slice(0, 10);
      const c = await this.store.crownBump(uid, day, { pass_game_xp: xp });
      const before = (c.pass_game_xp || 0) - xp;
      xp = Math.max(0, Math.min(xp, GAME_XP_CAP - before));
      if (!xp) return [];
    }
    const c = await this.store.crownBump(uid, seasonDay(s), { pass_xp: xp });
    const total = c.pass_xp || 0, from = levelOf(total - xp) + 1, to = levelOf(total);
    if (to < from) return [];
    return this.grant(uid, s, from, to, await this.club(uid));
  }

  // entrega as recompensas dos níveis from..to (idempotente)
  async grant(uid, s, from, to, club) {
    const lines = [];
    let gained = 0;
    const R = rewards(s);
    for (let l = from; l <= to; l++) {
      const r = R[l - 1];
      if (r.free && await this.store.crownAward(uid, r.free.crowns, 'pass', `${s}:${l}:f`) !== null) { gained += r.free.crowns; lines.push(`Passe nível ${l} +${r.free.crowns}`); }
      if (!club) continue;
      if (r.club.crowns) {
        if (await this.store.crownAward(uid, r.club.crowns, 'pass', `${s}:${l}:c`) !== null) { gained += r.club.crowns; lines.push(`Passe Club nível ${l} +${r.club.crowns}`); }
      } else if (await this.store.crownAward(uid, 0, 'pass', `${s}:${l}:c`) !== null) {   // trava do item
        const got = this.store.crownBuy ? await this.store.crownBuy(uid, r.club.item, 0).catch(() => 'erro') : 'erro';
        if (got === 'ok') lines.push(`Passe Club nível ${l}: ${r.club.name} (seu para sempre)`);
        else if (await this.store.crownAward(uid, 300, 'pass', `${s}:${l}:c+`) !== null) { gained += 300; lines.push(`Passe Club nível ${l}: você já tinha ${r.club.name} · +300`); }
      }
    }
    if (lines.length && this.backend.crowns) {
      await this.backend.crowns.notify(uid, gained, lines);
      if (this.backend.crownStore) for (const ws of (this.backend.socketsOf ? this.backend.socketsOf(uid) : [])) await this.backend.crownStore.sendState(ws, uid);
    }
    return lines;
  }

  async handle(ws, m) {
    if (String(m.type) !== 'pass_get') return;
    const s = seasonOf(this.now());
    const base = { type: 'pass_state', season: s, name: seasonName(s), levels: LEVELS, xp_per_level: XP_PER_LEVEL, xp_rules: XP, game_xp_cap: GAME_XP_CAP,
      ends_in_s: Math.max(0, Math.round((seasonEnd(s) - this.now()) / 1000)), rewards: rewards(s) };
    const uid = ws.user && ws.profile ? ws.user.id : null;
    if (!uid) return this.send(ws, { ...base, available: this.ok(), xp: 0, level: 0, club: false });
    if (!this.ok()) return this.send(ws, { ...base, available: false });
    try {
      const club = await this.club(uid);
      const c = await this.store.crownDaily(uid, seasonDay(s)) || {};
      const xp = c.pass_xp || 0, level = levelOf(xp);
      if (club && level > 0) await this.grant(uid, s, 1, level, true);   // assinou depois: entrega a faixa Club já alcançada
      this.send(ws, { ...base, available: true, xp, level, club });
    } catch (e) { this.off(e, 'estado'); this.send(ws, { ...base, available: false }); }
  }
}

module.exports = { SeasonPass, seasonOf, seasonName, seasonEnd, levelOf, rewards, seasonItems, LEVELS, XP_PER_LEVEL, XP, GAME_XP_CAP };
