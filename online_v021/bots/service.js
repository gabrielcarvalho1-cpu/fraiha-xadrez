'use strict';
// Escada de bots (JOGAR CONTRA O COMPUTADOR): progresso por conta e recompensas cosméticas.
// O cliente NÃO pode simplesmente dizer "venci o Challenger". O servidor:
//   • só aceita o próximo nível da escada (o anterior precisa estar derrotado no banco);
//   • refaz a partida inteira com as regras do servidor (chess_rules.js): todos os lances
//     legais, a partir da posição inicial, terminando em XEQUE-MATE do lado do bot;
//   • grava a 1ª vitória uma única vez por (conta, bot) — repetir não gera nova recompensa;
//   • limita a frequência de pedidos por conexão.
// R171 · SEC-008: nos níveis fortes (platina em diante + challenger) o servidor roda o MESMO Stockfish do jogo
// (bots/verify.js) e confere se os lances do lado do bot são de bot daquele nível — lances inventados ou ruins
// enviados pelo cliente são recusados. A cor do bot sai da partida (quem levou o mate), não do que o cliente diz.
// A mesma partida (lances idênticos) não vale para duas contas. Revanche (bot já derrotado) não gasta motor.
// Limite conhecido: nos níveis baixos o bot erra de propósito, então lá só valem as regras e o mate.
const crypto = require('crypto');
const { Position } = require('../chess_rules');
const { BotVerifier } = require('./verify');
const { operation } = require('../accounts/operation');
const LADDER = require('../../bot/bot_ladder.json');
const IDS = LADDER.bots.map(b => b.id);
const MIN_PLIES = 4, MAX_PLIES = 600, CLAIM_GAP_MS = Number(process.env.FRAIHA_BOT_CLAIM_GAP_MS || 5000);
const UCI_RE = /^[a-h][1-8][a-h][1-8][qrbn]?$/;

function replay(moves) {
  const pos = new Position();
  for (const u of moves) {
    if (typeof u !== 'string' || !UCI_RE.test(u)) return null;
    const from = [u.charCodeAt(0) - 97, 8 - Number(u[1])], to = [u.charCodeAt(2) - 97, 8 - Number(u[3])];
    if (!pos.play({ from, to, promotion: (u[4] || 'q').toUpperCase() })) return null;
  }
  return pos;
}
// Valida uma vitória declarada. Devolve { ok:true } ou { error, code }.
function validateVictory(m) {
  const id = String(m.bot_id || '');
  if (!IDS.includes(id)) return { error: 'Bot desconhecido.', code: 'bot_invalid' };
  const color = String(m.human_color || '');
  if (color !== 'w' && color !== 'b') return { error: 'Cor inválida.', code: 'bot_invalid' };
  const moves = m.moves;
  if (!Array.isArray(moves) || moves.length < MIN_PLIES || moves.length > MAX_PLIES) return { error: 'Partida inválida.', code: 'bot_game_invalid' };
  const pos = replay(moves);
  if (!pos) return { error: 'Partida inválida: lance ilegal.', code: 'bot_game_invalid' };
  const botColor = color === 'w' ? 'b' : 'w';
  if (pos.outcome() !== 'checkmate' || pos.turn !== botColor) return { error: 'A partida não terminou com vitória sua.', code: 'bot_game_invalid' };
  return { ok: true, id, botColor: pos.turn };   // cor do bot = quem levou o mate (não a palavra do cliente)
}

class BotService {
  constructor({ store, send, backend, verifier = null, env = process.env }) {
    this.store = store; this.send = send; this.backend = backend;
    this.verifier = verifier || new BotVerifier({ env });
    this.games = new Map();   // hash dos lances -> conta (níveis conferidos): a mesma partida não vale para outra conta
  }
  // Para o acct_state: progresso salvo na conta (ou indisponível sem a migração 0006).
  async summary(uid) {
    try { const rows = await this.store.getBotProgress(uid); return { available: true, defeated: rows.map(r => r.bot_id).filter(id => IDS.includes(id)) }; }
    catch (e) { if (notConfigured(e)) return { available: false, defeated: [] }; throw e; }
  }
  async handle(ws, m) {
    const a = String(m.type || '');
    if (!ws.user || !ws.profile) return this.send(ws, { type: 'bot_error', code: 'auth_required', message: 'Entre na sua conta para salvar o progresso dos bots.' });
    const op = operation(this.backend, ws);
    if (a === 'bot_progress') return this.send(ws, { type: 'bot_progress', ...(await op.wait(() => this.summary(op.uid))), new_bot: null });
    if (a !== 'bot_victory') return this.send(ws, { type: 'bot_error', code: 'unknown', message: 'Ação desconhecida.' });
    const now = Date.now();
    if (ws.botClaimAt && now - ws.botClaimAt < CLAIM_GAP_MS) return this.send(ws, { type: 'bot_error', code: 'rate_limited', message: 'Aguarde um instante.' });
    ws.botClaimAt = now;
    const v = validateVictory(m);
    if (v.error) return this.send(ws, { type: 'bot_error', code: v.code, message: v.error, bot_id: String(m.bot_id || '') });
    let progress;
    try { progress = await op.wait(() => this.summary(op.uid)); } catch (e) { throw e; }
    if (!progress.available) return this.send(ws, { type: 'bot_error', code: 'not_configured', message: 'Progresso dos bots ainda não configurado no servidor (migração 0006 pendente).', bot_id: v.id });
    const idx = IDS.indexOf(v.id);
    if (idx > 0 && !progress.defeated.includes(IDS[idx - 1])) return this.send(ws, { type: 'bot_error', code: 'bot_locked', message: 'Derrote o bot anterior primeiro.', bot_id: v.id });
    let hash = null;
    if (!progress.defeated.includes(v.id)) {
      // R171b · SEC-008 (reteste Orca): a mesma partida (lances idênticos) só vale para UMA conta — conferido no BANCO
      // (bot_progress.game_hash, migração 0024), então reiniciar o servidor ou ter outra instância não libera o replay
      hash = gameHash(v.id, m.moves);
      if (await this.reusedBy(op, hash)) return this.send(ws, { type: 'bot_error', code: 'bot_game_reused', message: REUSED_MSG, bot_id: v.id });
      if (this.verifier.needs(v.id)) {
        const err = await this.verify(op, v, m.moves);
        if (err) return this.send(ws, { type: 'bot_error', ...err, bot_id: v.id });
      }
    }
    let fresh;
    try { fresh = await op.wait(() => this.store.recordBotVictory(op.uid, v.id, { plies: m.moves.length, human_color: m.human_color, game_hash: hash })); }
    catch (e) {
      if (e && e.code === 'bot_game_reused') return this.send(ws, { type: 'bot_error', code: 'bot_game_reused', message: REUSED_MSG, bot_id: v.id });
      throw e;
    }
    if (fresh && hash) { if (this.games.size > 50000) this.games.clear(); this.games.set(hash, op.uid); }
    if (fresh && this.backend && this.backend.crowns && this.backend.crowns.onBotWin) {   // R184e · coroas da 1ª vitória
      const b = LADDER.bots[idx] || {};
      try { await op.wait(() => this.backend.crowns.onBotWin(op.uid, v.id, idx, b.name || '')); } catch (e) { console.error('[bots] coroas', e && e.message); }
    }
    const after = await op.wait(() => this.summary(op.uid));
    return this.send(ws, { type: 'bot_progress', ...after, new_bot: fresh ? v.id : null });
  }
}
const REUSED_MSG = 'Esta partida já foi registrada por outra conta.';
const gameHash = (botId, moves) => crypto.createHash('sha256').update(botId + '|' + moves.join(' ')).digest('hex');
// Dono atual da partida (banco; o mapa em memória só cobre banco sem a 0024). true = é de OUTRA conta.
BotService.prototype.reusedBy = async function (op, hash) {
  let owner = null;
  if (this.store.botGameOwner) owner = await op.wait(() => this.store.botGameOwner(hash));
  if (!owner) owner = this.games.get(hash) || null;
  if (owner && owner !== op.uid) { console.log('[bot-verify]', JSON.stringify({ ok: false, reason: 'reused', uid: op.uid })); return true; }
  return false;
};
// R171 · SEC-008: confere os lances do bot (só 1ª vitória em nível forte). Devolve null (ok) ou { code, message }.
BotService.prototype.verify = async function (op, v, moves) {
  const r = await this.verifier.check(v.id, moves, v.botColor);
  op.assert();
  if (r.ok) return null;
  if (r.code === 'bot_game_rejected') {
    console.log('[bot-verify] RECUSADA', JSON.stringify({ uid: op.uid, bot: v.id, ...r.stats }));
    return { code: 'bot_game_rejected', message: 'Não foi possível confirmar esta vitória: os lances do bot não conferem com o nível escolhido.' };
  }
  return { code: r.code, message: r.code === 'verify_busy' ? 'O servidor está conferindo outras partidas agora. Tente de novo em instantes.' : 'Não foi possível conferir a partida agora. Tente de novo em alguns minutos.' };
};
function notConfigured(e) { return e && /42P01|PGRST205|does not exist|Could not find the table/.test(String(e.code) + ' ' + String(e.message)); }

module.exports = { BotService, validateVictory, replay, IDS, gameHash };
