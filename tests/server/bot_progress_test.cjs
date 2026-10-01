'use strict';
// Escada de bots: vitória validada pelo servidor (partida refeita, xeque-mate do bot, ordem da escada),
// 1ª vitória única, progresso no acct_state, e sem 0006 → "not_configured" (nada é gravado).
const { startServer, client, check, summary } = require('./helpers.cjs');
const { BotService, validateVictory, IDS } = require('../../online_v021/bots/service.js');
const SCHOLAR = ['e2e4', 'e7e5', 'd1h5', 'b8c6', 'f1c4', 'g8f6', 'h5f7'];          // brancas dão mate
const FOOL = ['f2f3', 'e7e5', 'g2g4', 'd8h4'];                                     // pretas dão mate
const wait = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  check(IDS.length === 11 && IDS[0] === 'madeira' && IDS[10] === 'challenger', 'escada com as 11 ligas na ordem do projeto');
  check(validateVictory({ bot_id: 'madeira', human_color: 'w', moves: SCHOLAR }).ok === true, 'mate das brancas = vitória do jogador de brancas');
  check(!!validateVictory({ bot_id: 'madeira', human_color: 'b', moves: SCHOLAR }).error, 'mesmo jogo declarado pelas pretas (perdedor) é recusado');
  check(validateVictory({ bot_id: 'madeira', human_color: 'b', moves: FOOL }).ok === true, 'jogador de pretas vencendo com mate também vale');
  check(!!validateVictory({ bot_id: 'madeira', human_color: 'w', moves: SCHOLAR.slice(0, 6) }).error, 'partida sem mate é recusada');
  check(!!validateVictory({ bot_id: 'madeira', human_color: 'w', moves: ['e2e4', 'e7e5', 'd1h5', 'b8c6', 'f1c4', 'g8f6', 'h5h8'] }).error, 'lance ilegal é recusado');
  check(!!validateVictory({ bot_id: 'rei', human_color: 'w', moves: SCHOLAR }).error, 'bot inexistente é recusado');
  check(!!validateVictory({ bot_id: 'madeira', human_color: 'w', moves: 'e2e4' }).error, 'formato inválido é recusado');
  // Sem a tabela (0006 não aplicada): nada é gravado, resposta clara.
  const sent = []; const fake = { getBotProgress: async () => { const e = new Error('Could not find the table public.bot_progress'); e.code = 'PGRST205'; throw e; }, recordBotVictory: async () => { throw new Error('não deveria gravar'); } };
  const svc = new BotService({ store: fake, send: (ws, o) => sent.push(o) });
  const ws = { user: { id: 'u' }, profile: { nickname: 'x' } };
  await svc.handle(ws, { type: 'bot_victory', bot_id: 'madeira', human_color: 'w', moves: SCHOLAR });
  check(sent[0] && sent[0].code === 'not_configured', 'sem migração 0006 → not_configured, nenhuma gravação');
  check((await svc.summary('u')).available === false, 'acct_state informa progresso indisponível sem 0006');

  const s = await startServer({ FRAIHA_DEV_AUTH: '1', FRAIHA_BOT_CLAIM_GAP_MS: '250' });
  const c = client(s.port); await c.open();
  c.send({ type: 'bot_victory', bot_id: 'madeira', human_color: 'w', moves: SCHOLAR });
  let m = await c.next('bot_error');
  check(m.code === 'auth_required', 'convidado não grava progresso no servidor');
  c.send({ type: 'acct_auth', access_token: 'dev:botfan' }); await c.next('acct_state');
  c.send({ type: 'acct_create_profile', nickname: 'BotFan' });
  let st = await c.next('acct_state');
  check(st.bots && st.bots.available === true && st.bots.defeated.length === 0, 'acct_state traz progresso dos bots (vazio)');
  c.send({ type: 'bot_victory', bot_id: 'ferro', human_color: 'w', moves: SCHOLAR });
  m = await c.next('bot_error');
  check(m.code === 'bot_locked', 'pular para FERRO sem vencer MADEIRA é recusado');
  await wait(300);
  c.send({ type: 'bot_victory', bot_id: 'challenger', human_color: 'w', moves: SCHOLAR });
  m = await c.next('bot_error');
  check(m.code === 'bot_locked', '"derrotei o Challenger" direto é recusado');
  await wait(300);
  c.send({ type: 'bot_victory', bot_id: 'madeira', human_color: 'w', moves: SCHOLAR.slice(0, 6) });
  m = await c.next('bot_error');
  check(m.code === 'bot_game_invalid', 'vitória sem xeque-mate é recusada pelo servidor');
  await wait(300);
  c.send({ type: 'bot_victory', bot_id: 'madeira', human_color: 'w', moves: SCHOLAR });
  m = await c.next('bot_progress');
  check(m.new_bot === 'madeira' && m.defeated.includes('madeira'), 'vitória válida contra MADEIRA é gravada (recompensa nova)');
  c.send({ type: 'bot_victory', bot_id: 'madeira', human_color: 'w', moves: SCHOLAR });
  m = await c.next('bot_error');
  check(m.code === 'rate_limited', 'pedidos em sequência rápida são limitados');
  await wait(300);
  c.send({ type: 'bot_victory', bot_id: 'madeira', human_color: 'w', moves: SCHOLAR });
  m = await c.next('bot_progress');
  check(m.new_bot === null && m.defeated.length === 1, 'repetir a vitória NÃO gera nova recompensa');
  await wait(300);
  c.send({ type: 'bot_victory', bot_id: 'ferro', human_color: 'b', moves: FOOL });
  m = await c.next('bot_progress');
  check(m.new_bot === 'ferro' && m.defeated.length === 2, 'FERRO liberado depois de MADEIRA e gravado');
  // Outro aparelho: mesma conta vê o progresso
  const d = client(s.port); await d.open();
  d.send({ type: 'acct_auth', access_token: 'dev:botfan' });
  st = await d.next('acct_state');
  check(st.bots.defeated.join(',') === 'madeira,ferro', 'outro aparelho recebe o progresso da conta');
  c.close(); d.close(); s.stop();
  summary('BOT_PROGRESS');
})().catch(e => { console.error(e); process.exitCode = 1; });
