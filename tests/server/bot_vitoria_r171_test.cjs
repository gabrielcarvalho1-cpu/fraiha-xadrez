'use strict';
// R171 · SEC-008 — vitória contra bot: o servidor não confia no resultado, na cor nem no progresso que o cliente
// diz. Nos níveis fortes ele confere os lances do LADO DO BOT com o mesmo Stockfish do jogo (motor real, não mock).
// Partidas do fixture: geradas com o Stockfish do jogo (ver o _doc do arquivo).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { MemoryStore } = require('../../online_v021/accounts/store');
const { BotService, IDS } = require('../../online_v021/bots/service');
const { BotVerifier, STRONG } = require('../../online_v021/bots/verify');
const G = require('./fixtures/bot_games_r171.json');

function setup(env = {}) {
  const store = new MemoryStore(), sent = [], logs = [];
  const quiet = console.log; console.log = (...a) => logs.push(a.join(' '));
  const svc = new BotService({ store, send: (ws, o) => sent.push({ to: ws.user.id, ...o }), env: { FRAIHA_BOT_CLAIM_GAP_MS: '0', ...env } });
  const ws = id => ({ user: { id }, profile: { nickname: id } });
  // conta que já venceu todos os bots ANTES do nível pedido (progresso vem do servidor, não do cliente)
  const unlockUntil = async (uid, bot) => { for (const id of IDS.slice(0, IDS.indexOf(bot))) await store.recordBotVictory(uid, id, {}); };
  const claim = async (uid, game, extra = {}) => { await svc.handle(ws(uid), { type: 'bot_victory', bot_id: game.level, human_color: game.human_color, moves: game.moves, ...extra }); return sent.filter(o => o.to === uid).at(-1); };
  const done = () => { svc.verifier.stop(); console.log = quiet; };
  return { store, svc, sent, logs, unlockUntil, claim, done, ws };
}

test('SEC-008: níveis conferidos = platina em diante + challenger; níveis baixos ficam de fora (erram de propósito)', () => {
  assert.deepEqual([...STRONG], ['platina', 'esmeralda', 'diamante', 'mestre', 'grande_mestre', 'challenger']);
});

test('SEC-008: partida REAL contra o bot (platina e diamante) é aceita e grava a vitória', async () => {
  const t = setup();
  try {
    await t.unlockUntil('ana', 'platina');
    for (const g of [G.real_platina, G.real_diamante]) {
      if (g === G.real_diamante) await t.store.recordBotVictory('ana', 'esmeralda', {});
      const r = await t.claim('ana', g);
      assert.equal(r.type, 'bot_progress', JSON.stringify(r)); assert.equal(r.new_bot, g.level);
    }
    assert.ok(t.logs.some(l => l.includes('[bot-verify]') && l.includes('"ok":true')), 'o motor rodou de verdade');
  } finally { t.done(); }
});

test('SEC-008: lances inventados/ruins do lado do bot (terminando em mate) são recusados; nada é gravado', async () => {
  const t = setup();
  try {
    await t.unlockUntil('bia', 'platina');
    const r = await t.claim('bia', G.random_platina);
    assert.equal(r.type, 'bot_error'); assert.equal(r.code, 'bot_game_rejected');
    assert.ok(!(await t.store.getBotProgress('bia')).some(x => x.bot_id === 'platina'));
  } finally { t.done(); }
});

test('SEC-008: resultado falso (sem mate / lance ilegal / cor trocada) é recusado antes do motor', async () => {
  const t = setup();
  try {
    await t.unlockUntil('caio', 'platina');
    const g = G.real_platina;
    assert.equal((await t.claim('caio', { ...g, moves: g.moves.slice(0, -1) })).code, 'bot_game_invalid', 'sem o lance do mate');
    const bad = g.moves.slice(); bad[10] = 'a1a8';
    assert.equal((await t.claim('caio', { ...g, moves: bad })).code, 'bot_game_invalid', 'lance ilegal');
    assert.equal((await t.claim('caio', { ...g, human_color: g.human_color === 'w' ? 'b' : 'w' })).code, 'bot_game_invalid', 'cor declarada errada');
    assert.equal(t.logs.filter(l => l.includes('[bot-verify]')).length, 0, 'nenhum gasto de motor com pedido inválido');
  } finally { t.done(); }
});

test('SEC-008: progresso declarado pelo cliente não vale (pular nível é recusado)', async () => {
  const t = setup();
  try {
    const r = await t.claim('dani', G.real_platina, { defeated: IDS, progress: IDS });
    assert.equal(r.code, 'bot_locked');
  } finally { t.done(); }
});

test('SEC-008: a mesma vitória duas vezes (mesma conta) não dá nova recompensa nem roda o motor de novo', async () => {
  const t = setup();
  try {
    await t.unlockUntil('eva', 'platina');
    assert.equal((await t.claim('eva', G.real_platina)).new_bot, 'platina');
    const runs = t.logs.filter(l => l.includes('[bot-verify]')).length;
    const again = await Promise.all([t.claim('eva', G.real_platina), t.claim('eva', G.real_platina_b)]);
    for (const r of again) { assert.equal(r.type, 'bot_progress'); assert.equal(r.new_bot, null); }
    assert.equal(t.logs.filter(l => l.includes('[bot-verify]')).length, runs, 'revanche não gasta motor');
    assert.equal((await t.store.getBotProgress('eva')).filter(x => x.bot_id === 'platina').length, 1);
  } finally { t.done(); }
});

test('SEC-008: replay duplicado — a mesma partida enviada por OUTRA conta é recusada', async () => {
  const t = setup();
  try {
    await t.unlockUntil('fabi', 'platina'); await t.unlockUntil('gil', 'platina');
    assert.equal((await t.claim('fabi', G.real_platina)).new_bot, 'platina');
    const r = await t.claim('gil', G.real_platina);
    assert.equal(r.code, 'bot_game_reused');
    assert.equal((await t.claim('gil', G.real_platina_b)).new_bot, 'platina', 'outra partida real da mesma conta vale');
  } finally { t.done(); }
});

test('SEC-008: motor indisponível → nível forte recusado com aviso (fail-closed); nível baixo segue só com as regras', async () => {
  const t = setup({ FRAIHA_ENGINE_PATH: '/nao/existe/stockfish.js' });
  const quietE = console.error; console.error = () => {};
  try {
    t.svc.verifier = new BotVerifier({ env: { FRAIHA_ENGINE_PATH: '/nao/existe/stockfish.js' }, log: () => {} });
    t.svc.verifier._engine = async () => { throw new Error('engine_missing'); };
    await t.unlockUntil('hugo', 'platina');
    assert.equal((await t.claim('hugo', G.real_platina)).code, 'verify_unavailable');
    const scholar = { level: 'madeira', human_color: 'w', moves: ['e2e4', 'e7e5', 'd1h5', 'b8c6', 'f1c4', 'g8f6', 'h5f7'] };
    assert.equal((await t.claim('ivo', scholar)).new_bot, 'madeira');
  } finally { console.error = quietE; t.done(); }
});

test('SEC-008: fila do motor cheia → "tente de novo" (não aceita sem conferir)', async () => {
  const t = setup({ FRAIHA_BOT_VERIFY_QUEUE: '1' });
  try {
    await t.unlockUntil('ju', 'platina'); await t.unlockUntil('ka', 'platina');
    const [a, b] = await Promise.all([t.claim('ju', G.real_platina), t.claim('ka', G.real_platina_b)]);
    const codes = [a, b].map(r => r.code || r.new_bot).sort();
    assert.deepEqual(codes, ['platina', 'verify_busy']);
  } finally { t.done(); }
});
