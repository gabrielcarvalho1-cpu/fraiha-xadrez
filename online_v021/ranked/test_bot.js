'use strict';
// R174 · BOT DE TESTE DO RANKED (só para o dono testar a subida de liga na prática).
// DESLIGADO por padrão (produção nunca liga). Liga com as DUAS variáveis de ambiente abaixo OU, no servidor de
// STAGING (FRAIHA_ENV=staging), com as contas padrão de teste do dono (STAGING_PADRAO); FRAIHA_RANKED_TEST_BOT=off desliga.
//   FRAIHA_RANKED_TEST_BOT_UID = user_id de uma conta FRAIHA criada para ser o bot (ex.: "BotMadeira");
//   FRAIHA_RANKED_TEST_OWNERS  = user_id(s) que podem cair contra ele (separados por vírgula);
//   FRAIHA_RANKED_TEST_BOT_MODES (opcional, padrão "ranked_3min" = Relâmpago);
//   FRAIHA_RANKED_TEST_BOT_WAIT_MS (opcional, padrão 3000: espera alguém de verdade antes de chamar o bot).
// Regras:
//   • só quem está em FRAIHA_RANKED_TEST_OWNERS cai contra o bot; ninguém mais o vê na fila;
//   • é uma partida Ranked NORMAL entre duas contas reais (PL, liga, placar, Força, Coroas: tudo como sempre);
//   • nível do BOT MADEIRA da escada de bots (bot/bot_ladder.json): Stockfish nível 0, profundidade 1,
//     35% de lance aleatório, responde em ~0,35–1,2 s; sem o motor, joga lances aleatórios (com preferência
//     por capturas). Nunca desiste, nunca oferece nem aceita empate; o relógio dele corre normalmente.
const { UciEngine } = require('../bots/engine');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
// Contas de teste do dono no staging (escolhidas por ele em 21/10/2026): bot = SextoSen1; quem cai contra = SextoSentro.
const STAGING_PADRAO = { bot: 'e0eb1d64-f4b1-438c-a2e5-fbdfc013abd3', owners: 'f523dc61-26f8-4a5c-9195-2d1e6e766d92' };
const MADEIRA = { skill: 0, depth: 1, randomChance: 0.35, thinkMs: [250, 650] };   // R176.9 · antes 350–1200 ms (parecia travado)

class RankedTestBot {
  constructor(ranked, { env = process.env, engine = null, random = Math.random } = {}) {
    this.ranked = ranked; this.random = random;
    const off = /^(0|off|nao|não|false)$/i.test(String(env.FRAIHA_RANKED_TEST_BOT || '').trim());
    const padrao = !off && String(env.FRAIHA_ENV || '').trim() === 'staging' ? STAGING_PADRAO : { bot: '', owners: '' };
    this.botUid = off ? '' : String(env.FRAIHA_RANKED_TEST_BOT_UID || padrao.bot).trim();
    this.owners = new Set(off ? [] : String(env.FRAIHA_RANKED_TEST_OWNERS || padrao.owners).split(',').map(s => s.trim()).filter(s => UUID.test(s)));
    this.modes = String(env.FRAIHA_RANKED_TEST_BOT_MODES || 'ranked_3min').split(',').map(s => s.trim()).filter(Boolean);
    this.waitMs = Math.max(0, Number(env.FRAIHA_RANKED_TEST_BOT_WAIT_MS || 3000));
    this.engine = engine;   // criado na primeira jogada (processo separado do verificador de bots)
    this.engineFailed = false;
    this.starting = false;
    this.thinking = new Set();
  }
  enabled() {
    return !!this.ranked.rated && UUID.test(this.botUid) && this.owners.size > 0 && !this.owners.has(this.botUid);
  }
  isBot(uid) { return this.enabled() && uid === this.botUid; }

  // Chamado a cada tick do serviço Ranked (antes do pareamento normal: o dono só cai contra o bot depois de
  // esperar waitMs sem ninguém de verdade).
  tick(now, open = true) {
    if (!this.enabled()) return;
    const R = this.ranked;
    const modeOpen = mode => open && !(R.backend && R.backend.modeOpen && !R.backend.modeOpen(R.kind, mode));   // Admin fechou: sem bot
    if (!this.starting) for (const mode of this.modes.filter(modeOpen)) {
      const q = this.ranked.mm.queues.get(mode); if (!q) continue;
      const entry = q.find(e => this.owners.has(e.userId) && now - e.since >= this.waitMs);
      if (entry) { void this.start(mode, entry); break; }
    }
    for (const match of this.ranked.matches.values()) if (match.testBot && match.status === 'playing') this.maybeMove(match);
  }

  async start(mode, human) {
    const R = this.ranked;
    if (R.activeMatchOf(this.botUid) || R.persistPending(this.botUid)) return;   // um teste por vez
    this.starting = true;
    try {
      const [all, profs] = await Promise.all([R.statsFull(this.botUid),
        R.backend.store.getProfilesByIds ? R.backend.store.getProfilesByIds([this.botUid]) : []]);
      const prof = (profs || [])[0] || {};
      const q = R.mm.queues.get(mode);
      if (!q || !q.includes(human)) return;                      // o dono saiu da fila / já foi pareado
      if (!all || !all[mode]) return;
      R.mm.cancel(human.userId);
      const bot = { userId: this.botUid, nickname: prof.nickname || 'BotMadeira', avatar: prof.avatar_id || 'warrior', stats: all[mode], since: R.now() };
      try { R.startMatch(mode, human, bot, R.now(), false, { botUid: this.botUid }); }
      catch (e) { if (R.queueEligible(human.userId)) R.mm.enqueue(mode, human); if (e.code !== 'player_unavailable') throw e; }
    } catch (e) { console.error('[bot de teste] não iniciou', e && e.message); }
    finally { this.starting = false; }
  }

  maybeMove(match) {
    const color = match.testBot;
    if (match.pos.turn !== color || this.thinking.has(match.id)) return;
    this.thinking.add(match.id);
    const ply = match.pos.ply;
    const [lo, hi] = MADEIRA.thinkMs;
    const delay = lo + Math.floor(this.random() * (hi - lo));
    setTimeout(async () => {
      try {
        const mv = await this.choose(match);
        const R = this.ranked, now = R.now();
        if (match.status !== 'playing' || match.pos.ply !== ply || match.pos.turn !== color || !mv) return;
        const r = match.move(color, mv, now);
        if (r && r.ok) R.after(match, now);
      } catch (e) { console.error('[bot de teste] lance', e && e.message); }
      finally { this.thinking.delete(match.id); }
    }, delay).unref?.();
  }

  // Lance no nível do BOT MADEIRA
  async choose(match) {
    const legal = match.pos.legalMoves();
    if (!legal.length) return null;
    if (this.random() >= MADEIRA.randomChance) {
      const uci = await this.engineMove(match.pos.history);
      const m = uci && legal.find(l => sq(l.from) + sq(l.to) === uci.slice(0, 4) && (uci.length < 5 || l.promotion === uci[4].toUpperCase()));
      if (m) return m;
    }
    // aleatório, preferindo capturas (como um iniciante)
    const caps = legal.filter(l => match.pos.piece(l.to[0], l.to[1]));
    const pool = caps.length && this.random() < 0.5 ? caps : legal;
    return pool[Math.floor(this.random() * pool.length)];
  }
  async engineMove(history) {
    if (this.engineFailed) return null;
    try {
      if (!this.engine) {
        const e = new UciEngine({ timeoutMs: 5000 });
        if (!e.available()) { this.engineFailed = true; return null; }
        e.start(); this.engine = e;
        await e.setOptions({ 'Skill Level': MADEIRA.skill });
      }
      const r = await this.engine.analyse(START_FEN, { depth: MADEIRA.depth, moves: history });
      return r && r.best && r.best !== '(none)' ? r.best : null;
    } catch (e) {
      console.error('[bot de teste] motor', e && e.message);
      try { this.engine && this.engine.stop(); } catch {}
      this.engine = null;
      return null;
    }
  }
  stop() { try { this.engine && this.engine.stop(); } catch {} this.engine = null; }
}
const sq = ([x, y]) => 'abcdefgh'[x] + (8 - y);

module.exports = { RankedTestBot, MADEIRA, STAGING_PADRAO };
