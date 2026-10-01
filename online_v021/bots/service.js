'use strict';
// Escada de bots (JOGAR CONTRA O COMPUTADOR): progresso por conta e recompensas cosméticas.
// O cliente NÃO pode simplesmente dizer "venci o Challenger". O servidor:
//   • só aceita o próximo nível da escada (o anterior precisa estar derrotado no banco);
//   • refaz a partida inteira com as regras do servidor (chess_rules.js): todos os lances
//     legais, a partir da posição inicial, terminando em XEQUE-MATE do lado do bot;
//   • grava a 1ª vitória uma única vez por (conta, bot) — repetir não gera nova recompensa;
//   • limita a frequência de pedidos por conexão.
// Limite conhecido (documentado no handoff): o servidor não roda o Stockfish, então não prova
// que os lances do lado do bot foram mesmo do bot. Fecha o atalho trivial, não é anti-cheat completo.
const { Position } = require('../chess_rules');
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
  return { ok: true, id };
}

class BotService {
  constructor({ store, send }) { this.store = store; this.send = send; }
  // Para o acct_state: progresso salvo na conta (ou indisponível sem a migração 0006).
  async summary(uid) {
    try { const rows = await this.store.getBotProgress(uid); return { available: true, defeated: rows.map(r => r.bot_id).filter(id => IDS.includes(id)) }; }
    catch (e) { if (notConfigured(e)) return { available: false, defeated: [] }; throw e; }
  }
  async handle(ws, m) {
    const a = String(m.type || '');
    if (!ws.user || !ws.profile) return this.send(ws, { type: 'bot_error', code: 'auth_required', message: 'Entre na sua conta para salvar o progresso dos bots.' });
    if (a === 'bot_progress') return this.send(ws, { type: 'bot_progress', ...(await this.summary(ws.user.id)), new_bot: null });
    if (a !== 'bot_victory') return this.send(ws, { type: 'bot_error', code: 'unknown', message: 'Ação desconhecida.' });
    const now = Date.now();
    if (ws.botClaimAt && now - ws.botClaimAt < CLAIM_GAP_MS) return this.send(ws, { type: 'bot_error', code: 'rate_limited', message: 'Aguarde um instante.' });
    ws.botClaimAt = now;
    const v = validateVictory(m);
    if (v.error) return this.send(ws, { type: 'bot_error', code: v.code, message: v.error, bot_id: String(m.bot_id || '') });
    let progress;
    try { progress = await this.summary(ws.user.id); } catch (e) { throw e; }
    if (!progress.available) return this.send(ws, { type: 'bot_error', code: 'not_configured', message: 'Progresso dos bots ainda não configurado no servidor (migração 0006 pendente).', bot_id: v.id });
    const idx = IDS.indexOf(v.id);
    if (idx > 0 && !progress.defeated.includes(IDS[idx - 1])) return this.send(ws, { type: 'bot_error', code: 'bot_locked', message: 'Derrote o bot anterior primeiro.', bot_id: v.id });
    const fresh = await this.store.recordBotVictory(ws.user.id, v.id, { plies: m.moves.length, human_color: m.human_color });
    const after = await this.summary(ws.user.id);
    return this.send(ws, { type: 'bot_progress', ...after, new_bot: fresh ? v.id : null });
  }
}
function notConfigured(e) { return e && /42P01|PGRST205|does not exist|Could not find the table/.test(String(e.code) + ' ' + String(e.message)); }

module.exports = { BotService, validateVictory, replay, IDS };
