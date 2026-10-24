'use strict';
// R181 · RIVAL DE IA NA FILA (aprovado pelo dono: "vamos por essa linha", caminho do meio, honesto).
// Quem fica FRAIHA_QUEUE_AI_WAIT_MS (padrão 15 s desde R184; antes 30 s) na fila do Ranked ou do Casual sem achar ninguém de verdade
// recebe automaticamente um RIVAL DE IA da mesma liga:
//   • nome de personagem (Sir Gambito, Dama de Ferro…), avatar, tempo de pensar parecido com o de uma pessoa
//     (pelo relógio), emote de vez em quando;
//   • SEMPRE marcado como IA (publicPlayer.ai = true → selo "IA" no cartão do adversário);
//   • Ranked: METADE do PL (vitória e derrota), a Força oculta e o placar V/D/E não mudam, nada vai para a
//     tabela matches; a IA nunca entra no ranking nem nas vagas do Challenger (ela não tem conta);
//   • resultado precoce (desistência/abandono antes de 5 lances de cada lado) contra a IA: 0 PL;
//   • nunca oferece/aceita empate (jogar o lance recusa a oferta); desiste quando está claramente perdida.
// Força por liga (calibrada com o Stockfish do jogo, ver tools/calibrar_rival_ia.js e docs/ranked/R181_RIVAL_IA.md):
//   Madeira ≈ 1000, Ferro ≈ 1200 (abaixo do mínimo do UCI_Elo do Stockfish, 1320: nível 0 + erros "humanos");
//   Bronze em diante: UCI_LimitStrength/UCI_Elo do próprio Stockfish.
// FRAIHA_QUEUE_AI=off desliga tudo (volta a fila só com pessoas).
const crypto = require('crypto');
const { UciEngine } = require('../bots/engine');
const { expectedForca } = require('./progression');

const START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
// random: lance qualquer (prefere capturas, como iniciante) · shallow: enxerga só 1 lance (cai em tática) ·
// o resto: Stockfish no nível `skill` com profundidade `depth`. elo: usa o limitador oficial do Stockfish.
const LEVELS = [
  { name: 'Madeira', approx: 1000, skill: 0, depth: 6, shallow: 0.22, random: 0.06 },      // calibrado ≈ 1001 (80 partidas)
  { name: 'Ferro', approx: 1200, skill: 0, depth: 7, shallow: 0.08, random: 0.02 },        // calibrado ≈ 1225
  { name: 'Bronze', approx: 1400, elo: 1400, movetime: 250 },
  { name: 'Prata', approx: 1550, elo: 1550, movetime: 250 },
  { name: 'Ouro', approx: 1700, elo: 1700, movetime: 300 },
  { name: 'Platina', approx: 1850, elo: 1850, movetime: 300 },
  { name: 'Esmeralda', approx: 2000, elo: 2000, movetime: 350 },
  { name: 'Diamante', approx: 2150, elo: 2150, movetime: 350 },
  { name: 'Mestre', approx: 2300, elo: 2300, movetime: 400 },
  { name: 'Grande Mestre', approx: 2450, elo: 2450, movetime: 400 },
  { name: 'Challenger', approx: 2600, elo: 2600, movetime: 450 },
];
// Personagens (nunca nome de pessoa real). R181 · avatar = o retrato do BOT da mesma liga (bot/bot_ladder.json), nunca
// um avatar de jogador (antes usava os grátis e podia ficar igual ao do próprio jogador).
const PERSONAS = ['Sir Gambito', 'Dama de Ferro', 'Barão do Roque', 'Bispo Errante', 'Cavaleiro Veloz', 'Peão Audaz',
  'Duquesa da Diagonal', 'Capitão Xeque', 'Mestre Zugzwang', 'Lady Fianchetto', 'Conde En Passant', 'Torre de Vigia',
  'Dom Siciliano', 'Rainha do Centro'];
const LADDER = require('../../bot/bot_ladder.json');
const botAvatar = league => { const b = LADDER.bots[Math.max(0, Math.min(LADDER.bots.length - 1, league | 0))]; return (b && b.reward && b.reward.id) || 'madeira_reward'; };
const AI_PREFIX = 'ai:';
const isAiId = uid => String(uid || '').startsWith(AI_PREFIX);
const OFF = /^(0|off|nao|não|false)$/i;
const sq = ([x, y]) => 'abcdefgh'[x] + (8 - y);

// Estatísticas NEUTRAS da IA (só servem para a conta de PL de quem joga contra ela): mesma liga, 50 PL,
// Força igual à esperada para essa posição (o jogador ganha/perde o PL "normal" da liga, depois pela metade).
function aiStats(league) {
  const lg = Math.max(0, Math.min(10, league | 0)), pl = 50;
  return { league: lg, pl, matches: 50, wins: 25, losses: 25, draws: 0, highest_league: lg,
    forca: Math.round(expectedForca(lg * 100 + pl)), forca_rd: 200 };
}

// Lance da IA para a posição atual. Exportado para a calibração usar exatamente a mesma lógica.
async function pickMove(engine, pos, level, random = Math.random) {
  const legal = pos.legalMoves();
  if (!legal.length) return { move: null };
  const r = random();
  const anyMove = () => {
    const caps = legal.filter(l => pos.piece(l.to[0], l.to[1]));
    const pool = caps.length && random() < 0.5 ? caps : legal;
    return pool[Math.floor(random() * pool.length)];
  };
  if (!engine) return { move: anyMove() };
  if (!level.elo && r < level.random) return { move: anyMove(), kind: 'random' };
  let opts;
  if (level.elo) opts = { options: { 'Skill Level': 20, UCI_LimitStrength: 'true', UCI_Elo: level.elo }, movetime: level.movetime };
  else if (r < level.random + level.shallow) opts = { options: { UCI_LimitStrength: 'false', 'Skill Level': 0 }, depth: 1 };
  else opts = { options: { UCI_LimitStrength: 'false', 'Skill Level': level.skill }, depth: level.depth };
  const res = await engine.analyse(START_FEN, { ...opts, moves: pos.history });
  const uci = res && res.best && res.best !== '(none)' ? res.best : '';
  const m = uci && legal.find(l => sq(l.from) + sq(l.to) === uci.slice(0, 4) && (uci.length < 5 || l.promotion === uci[4].toUpperCase()));
  return { move: m || anyMove(), cp: res ? res.cp : 0, mate: res ? res.mate : 0 };
}

// Tempo de pensar parecido com o de uma pessoa: rápido na abertura, mais devagar no meio-jogo, sempre pelo relógio
// que sobra (nunca perde por tempo de propósito). ms.
function thinkMs(match, color, random = Math.random, now = Date.now()) {
  const left = match.clock && match.clock.left ? match.clock.left(color, now) : NaN;
  const remain = Number.isFinite(left) && left > 0 ? left : 180000;
  const ply = (match.pos && match.pos.ply) || 0;
  if (ply < 8) return 700 + Math.floor(random() * 1500);
  const budget = remain / 32;                                 // ~32 lances ainda pela frente
  let t = budget * (0.35 + random() * 1.3);
  if (random() < 0.08) t *= 2.2;                              // às vezes "pensa muito" num lance
  return Math.round(Math.max(600, Math.min(t, 14000, remain * 0.12)));
}

class QueueAI {
  constructor(service, { env = process.env, engine = null, random = Math.random } = {}) {
    this.svc = service; this.random = random;
    this.on = !OFF.test(String(env.FRAIHA_QUEUE_AI || '').trim());
    this.env = env;
    this.engine = engine; this.engineFailed = false;
    this.starting = new Set(); this.thinking = new Set();
  }
  enabled() { return this.on; }
  // R181 · lido a cada verificação (variável do servidor; o dono aumenta quando a base crescer, sem build novo)
  get waitMs() { return Math.max(0, Number(this.env.FRAIHA_QUEUE_AI_WAIT_MS || 15000)); }

  // Chamado a cada tick do serviço, DEPOIS do pareamento normal (gente de verdade sempre tem prioridade).
  tick(now, open = true) {
    if (!this.on) return;
    const S = this.svc;
    if (open) for (const [mode, q] of S.mm.queues) {
      if (S.backend && S.backend.modeOpen && !S.backend.modeOpen(S.kind, mode)) continue;   // Admin fechou: sem IA
      for (const e of q) if (now - e.since >= this.waitMs && !this.starting.has(e.userId) && !(S.testBot && S.testBot.owners && S.testBot.isBot && S.testBot.enabled() && S.testBot.owners.has(e.userId)))
        void this.start(mode, e, now - e.since);
    }
    for (const match of S.matches.values()) if (match.aiColor && match.status === 'playing') this.maybeMove(match);
  }

  async leagueOf(entry, mode) {
    if (entry.stats) return entry.stats.league | 0;
    // Casual: usa a liga do Ranked da conta (mesmo ritmo), se tiver; convidado = Madeira
    const S = this.svc, { UUID_RE } = require('../accounts/store');
    if (!UUID_RE.test(String(entry.userId || '')) || !S.backend || !S.backend.store || !S.backend.store.getRankedStats) return 0;
    try {
      const all = await S.backend.store.getRankedStats(entry.userId);
      const same = all && all[String(mode).replace(/^casual_/, 'ranked_')];
      return same ? same.league | 0 : 0;
    } catch { return 0; }
  }

  async start(mode, human, waited) {
    const S = this.svc;
    this.starting.add(human.userId);
    try {
      const league = await this.leagueOf(human, mode);
      const q = S.mm.queues.get(mode);
      if (!q || !q.includes(human) || !S.queueEligible(human.userId)) return;   // saiu da fila / já pareou
      const nickname = PERSONAS[Math.floor(this.random() * PERSONAS.length)], avatar = botAvatar(league);
      const ai = { userId: AI_PREFIX + crypto.randomUUID(), nickname, avatar, ai: true, frame: 'liga',
        stats: S.rated ? aiStats(league) : null, since: S.now(), aiLevel: Math.max(0, Math.min(LEVELS.length - 1, league)) };
      S.mm.cancel(human.userId);
      try {
        const match = S.startMatch(mode, human, ai, S.now(), false, { botUid: ai.userId, ai: true, aiWaitMs: waited });
        match.aiLevel = ai.aiLevel; match.aiState = { lost: 0, emotes: 0 };
        console.log('[rival IA]', S.kind, mode, 'liga', LEVELS[ai.aiLevel].name, 'após', Math.round(waited / 1000) + 's', match.id);
        if (this.random() < 0.6) this.emote(match, 'emote_boa_sorte', 1500 + this.random() * 2500);
      } catch (e) { if (S.queueEligible(human.userId)) S.mm.enqueue(mode, human); if (e.code !== 'player_unavailable') throw e; }
    } catch (e) { console.error('[rival IA] não iniciou', e && e.message); }
    finally { this.starting.delete(human.userId); }
  }

  // emote da IA pelo mesmo canal do chat (o jogador pode silenciar)
  emote(match, id, delayMs = 0) {
    const S = this.svc, chat = S.backend && S.backend.chat;
    const go = () => {
      if (!chat || !match.aiColor || match.aiState.emotes >= 4) return;
      const Shop = require('../economy/store_catalog');
      const text = Shop.emoteText(id); if (!text) return;
      match.aiState.emotes++;
      match.chat = match.chat || []; match.chatSeq = (match.chatSeq || 0) + 1;
      const e = { id: match.chatSeq, from_color: match.aiColor, nickname: match.players[match.aiColor].nickname, text, emote: id, ts: new Date(S.now()).toISOString() };
      match.chat.push(e); if (match.chat.length > 60) match.chat.shift();
      chat.broadcast(S, match, { type: 'chat_msg', match_id: match.id, ...e });
    };
    if (delayMs > 0) { const t = setTimeout(go, delayMs); if (t.unref) t.unref(); } else go();
  }

  onFinished(match) {
    if (!match.aiColor || !match.result) return;
    const w = match.result.winner, c = match.aiColor;
    if (((match.pos && match.pos.ply) || 0) < 10) return;
    if (w !== c && this.random() < 0.7) this.emote(match, w === 'draw' ? 'emote_boa_partida' : 'emote_parabens', 900 + this.random() * 1200);
    else if (w === c && this.random() < 0.6) this.emote(match, 'emote_boa_partida', 900 + this.random() * 1200);
  }

  maybeMove(match) {
    const color = match.aiColor;
    if (match.status !== 'playing' || match.pos.turn !== color || this.thinking.has(match.id)) return;
    this.thinking.add(match.id);
    const ply = match.pos.ply, S = this.svc;
    const delay = thinkMs(match, color, this.random, S.now());
    const work = this.choose(match);   // calcula enquanto "pensa"
    const t = setTimeout(async () => {
      try {
        const res = await work;
        const now = S.now();
        if (match.status !== 'playing' || match.pos.ply !== ply || match.pos.turn !== color) return;
        // desiste quando está claramente perdida (depois do meio-jogo, como uma pessoa faria)
        const lost = (res.mate && res.mate < 0) || res.cp <= -900;
        match.aiState.lost = lost ? match.aiState.lost + 1 : 0;
        if (ply >= 40 && match.aiState.lost >= 3 && this.random() < 0.5) { match.resign(color, now); return S.after(match, now); }
        if (!res.move) return;
        const r = match.move(color, res.move, now);
        if (r && r.ok) {
          if (match.status === 'playing' && ply > 16 && this.random() < 0.02) this.emote(match, 'emote_boa_jogada', 600);
          S.after(match, now);
        }
      } catch (e) { console.error('[rival IA] lance', e && e.message); }
      finally { this.thinking.delete(match.id); }
    }, delay);
    if (t.unref) t.unref();
  }

  async choose(match) {
    const level = LEVELS[match.aiLevel | 0] || LEVELS[0];
    const engine = await this.getEngine();
    try { return await pickMove(engine, match.pos, level, this.random); }
    catch (e) {
      console.error('[rival IA] motor', e && e.message);
      try { this.engine && this.engine.stop(); } catch {}
      this.engine = null;
      return pickMove(null, match.pos, level, this.random);
    }
  }
  async getEngine() {
    if (this.engine) return this.engine;
    if (this.engineFailed) return null;
    const e = new UciEngine({ timeoutMs: 8000 });
    if (!e.available()) { this.engineFailed = true; return null; }
    try { await e.init(); this.engine = e; return e; } catch { this.engineFailed = true; return null; }
  }
  stop() { try { this.engine && this.engine.stop(); } catch {} this.engine = null; }
}

module.exports = { QueueAI, LEVELS, PERSONAS, botAvatar, pickMove, thinkMs, aiStats, isAiId, AI_PREFIX };
