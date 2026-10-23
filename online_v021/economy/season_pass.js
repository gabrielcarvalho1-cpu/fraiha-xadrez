'use strict';
// R120 · PASSE DA TEMPORADA. Temporada = mês do calendário (horário de Brasília), 30 níveis de 150 XP (R178: +10 bônus).
// XP: vitória online 30 · partida online 10 (até 300 XP/dia de partidas) · missão do dia 50 · entrada do dia 20.
// Duas faixas: GRÁTIS (todos) e CLUB (faixa premium, liberada para quem tem Club FRAIHA ativo — inclusive
// os níveis já alcançados antes de assinar, entregues na hora). Recompensas entregues SOZINHAS ao subir de nível.
// Sem migration nova: XP em crown_daily (dia = 1º do mês, contador pass_xp), recompensas pelo extrato das Coroas
// (motivo 'pass', ref temporada:nível:faixa — nunca paga duas vezes) e itens pela Loja (crownBuy com preço 0).
const Shop = require('./store_catalog');

// R178 · 30 níveis + 10 níveis BÔNUS (31–40); prêmio em TODO nível nas duas faixas
const LEVELS = 40, MAIN_LEVELS = 30, XP_PER_LEVEL = 150;
const XP = { win: 30, play: 10, mission: 50, daily: 20 }, GAME_XP_CAP = 300;
// R178 · XP EM DOBRO (lançamento): janela pelo ambiente do servidor, datas ISO (ex.: 2026-11-01T03:00:00Z)
//   FRAIHA_PASS_XP2_FROM / FRAIHA_PASS_XP2_UNTIL — sem as duas, sem bônus
function xpBoost(ms, env = process.env) {
  const a = Date.parse(env.FRAIHA_PASS_XP2_FROM || ''), b = Date.parse(env.FRAIHA_PASS_XP2_UNTIL || '');
  if (!Number.isFinite(a) || !Number.isFinite(b) || ms < a || ms >= b) return null;
  return { mult: 2, until: new Date(b).toISOString(), ends_in_s: Math.max(0, Math.round((b - ms) / 1000)) };
}
const BRT = 3 * 3600e3;
const MONTHS = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const missing = e => /42P01|42703|42883|PGRST200|PGRST202|PGRST204|PGRST205|does not exist|Could not find/.test(String(e && e.code) + ' ' + String(e && e.message));

const seasonOf = ms => new Date(ms - BRT).toISOString().slice(0, 7);          // 2026-10
const seasonDay = s => s + '-01';
const seasonName = s => 'Temporada de ' + MONTHS[Number(s.slice(5, 7)) - 1];
const seasonEnd = s => { const y = Number(s.slice(0, 4)), m = Number(s.slice(5, 7)); return Date.UTC(m === 12 ? y + 1 : y, m === 12 ? 0 : m, 1) + BRT; };
const levelOf = xp => Math.min(LEVELS, Math.floor(Math.max(0, xp) / XP_PER_LEVEL));

// R178 · prêmios de cada temporada (rodízio): emotes, títulos e avatares exclusivos do Passe, moldura rara da Loja
const seasonIdx = s => Number(s.slice(0, 4)) * 12 + Number(s.slice(5, 7));
const rot = (list, s, off = 0) => list[(seasonIdx(s) + off) % list.length];
function seasonItems(s) {
  const ce = Shop.PASS_EMOTES.filter(e => e.track === 'club');
  return { 10: rot(ce, s).id, 5: rot(ce, s, 1).id, 20: rot(Shop.ofKind('frame'), s) };
}
function seasonFreeEmote(s) { return rot(Shop.PASS_EMOTES.filter(e => e.track === 'free'), s); }
const passName = id => {
  const e = Shop.PASS_EMOTES.find(x => x.id === id); if (e) return e.text;
  const t = Shop.PASS_TITLE_BY_ID[id]; if (t) return t.name;
  const a = Shop.PASS_BY_ID[id]; if (a) return a.name;
  return Shop.BY_ID[id] ? Shop.BY_ID[id].name : id;
};
const passKind = id => (Shop.PASS_EMOTES.some(x => x.id === id) ? 'emote' : Shop.PASS_TITLE_BY_ID[id] ? 'title' : Shop.PASS_BY_ID[id] ? 'avatar' : (Shop.BY_ID[id] ? Shop.BY_ID[id].kind : 'item'));
function seasonAvatars(s) {
  const pick = track => rot(Shop.PASS_AVATARS.filter(a => a.track === track), s);
  return { free: pick('free'), club: pick('club') };
}
const AVATAR_LEVEL = 25;
const it = (id, extra = {}) => ({ item: id, name: passName(id), kind: passKind(id), ...extra });
// recompensas de cada nível: { level, bonus, free: {crowns}|{item,name,kind[,crowns]}, club: idem }
//   grátis: 15 Coroas por nível · 5 título · 10 emote · 15 150 Coroas · 20 100 Coroas (selo de perfil quando tiver arte)
//           · 25 avatar · 30 título "Campeão da Temporada" + 300 · bônus 31–40: 50
//   Club:   40 Coroas por nível · 5 emote extra · 10 emote · 15 título · 20 moldura rara da Loja · 25 avatar
//           · 30 título "Lenda da Temporada" + 1000 (moldura exclusiva quando tiver arte) · bônus 31–40: 100
function rewards(s) {
  const items = seasonItems(s);
  const av = seasonAvatars(s);
  const t = track => rot(Shop.PASS_TITLES.filter(x => x.track === track), s).id;
  const out = [];
  for (let l = 1; l <= LEVELS; l++) {
    const bonus = l > MAIN_LEVELS;
    let free = { crowns: bonus ? 50 : 15 }, club = { crowns: bonus ? 100 : 40 };
    if (l === 5) { free = it(t('free')); club = it(items[5]); }
    if (l === 10) { free = it(seasonFreeEmote(s).id); club = it(items[10]); }
    if (l === 15) { free = { crowns: 150 }; club = it(t('club')); }
    if (l === 20) { free = { crowns: 100 }; club = it(items[20]); }
    if (l === AVATAR_LEVEL) { free = it(av.free.id); club = it(av.club.id); }
    if (l === MAIN_LEVELS) { free = it('pt_campeao_temporada', { crowns: 300 }); club = it('pt_lenda_temporada', { crowns: 1000 }); }
    out.push({ level: l, bonus, free, club });
  }
  return out;
}

class SeasonPass {
  constructor({ backend, send, now = () => Date.now(), log = (...a) => console.log(...a) }) {
    this.backend = backend; this.send = send; this.now = now; this.log = log;
    this.offUntil = 0; this.busy = new Map(); this.granted = new Map();
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
    const boost = xpBoost(this.now());
    const mult = boost ? boost.mult : 1;
    let xp = XP[kind] * n * mult;
    if (kind === 'win' || kind === 'play') {   // limite diário de XP de partidas (com XP em dobro, o limite dobra junto)
      const day = new Date(this.now() - BRT).toISOString().slice(0, 10);
      const c = await this.store.crownBump(uid, day, { pass_game_xp: xp });
      const before = (c.pass_game_xp || 0) - xp;
      xp = Math.max(0, Math.min(xp, GAME_XP_CAP * mult - before));
      if (!xp) return [];
    }
    const c = await this.store.crownBump(uid, seasonDay(s), { pass_xp: xp });
    const total = c.pass_xp || 0, from = levelOf(total - xp) + 1, to = levelOf(total);
    if (to < from) return [];
    return this.grant(uid, s, from, to, await this.club(uid));
  }

  // entrega as recompensas dos níveis from..to (idempotente: a trava de cada prêmio é o lançamento no extrato)
  async grant(uid, s, from, to, club) {
    const lines = [];
    let gained = 0;
    const R = rewards(s);
    const KIND = { emote: 'emote', avatar: 'avatar', title: 'título', frame: 'moldura' };
    const give = async (r, tag, label, l) => {
      if (!r) return;
      if (r.item) {
        if (await this.store.crownAward(uid, 0, 'pass', `${s}:${l}:${tag}`) !== null) {   // trava do item
          const got = this.store.crownBuy ? await this.store.crownBuy(uid, r.item, 0).catch(() => 'erro') : 'erro';
          if (got === 'ok') lines.push(`${label} nível ${l}: ${KIND[r.kind] || 'item'} ${r.name} (seu para sempre)`);
          else if (await this.store.crownAward(uid, 300, 'pass', `${s}:${l}:${tag}+`) !== null) { gained += 300; lines.push(`${label} nível ${l}: você já tinha ${r.name} · +300`); }
        }
        if (r.crowns && await this.store.crownAward(uid, r.crowns, 'pass', `${s}:${l}:${tag}$`) !== null) { gained += r.crowns; lines.push(`${label} nível ${l} +${r.crowns}`); }
      } else if (r.crowns && await this.store.crownAward(uid, r.crowns, 'pass', `${s}:${l}:${tag}`) !== null) { gained += r.crowns; lines.push(`${label} nível ${l} +${r.crowns}`); }
    };
    for (let l = from; l <= to; l++) {
      const r = R[l - 1];
      await give(r.free, 'f', 'Passe', l);
      if (club) await give(r.club, 'c', 'Passe Club', l);
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
      ends_in_s: Math.max(0, Math.round((seasonEnd(s) - this.now()) / 1000)), rewards: rewards(s),
      main_levels: MAIN_LEVELS, xp_boost: xpBoost(this.now()) };
    const uid = ws.user && ws.profile ? ws.user.id : null;
    if (!uid) return this.send(ws, { ...base, available: this.ok(), xp: 0, level: 0, club: false });
    if (!this.ok()) return this.send(ws, { ...base, available: false });
    try {
      const club = await this.club(uid);
      const c = await this.store.crownDaily(uid, seasonDay(s)) || {};
      const xp = c.pass_xp || 0, level = levelOf(xp);
      // assinou depois: entrega a faixa Club já alcançada. R165 · uma vez por nível/temporada (antes repetia ~60 consultas ao banco
      // a cada abertura do passe e a resposta podia demorar muito); a entrega é idempotente de qualquer forma.
      const gk = uid + ':' + s;
      if (club && level > 0 && (this.granted.get(gk) || 0) < level) { await this.grant(uid, s, 1, level, true); this.granted.set(gk, level); if (this.granted.size > 5000) this.granted.clear(); }
      this.send(ws, { ...base, available: true, xp, level, club });
    } catch (e) { this.off(e, 'estado'); this.send(ws, { ...base, available: false }); }
  }
}

module.exports = { SeasonPass, seasonOf, seasonName, seasonEnd, levelOf, rewards, seasonItems, seasonAvatars, seasonFreeEmote, xpBoost, AVATAR_LEVEL, LEVELS, MAIN_LEVELS, XP_PER_LEVEL, XP, GAME_XP_CAP };
