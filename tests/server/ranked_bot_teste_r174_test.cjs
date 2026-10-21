'use strict';
// R174 · BOT DE TESTE DO RANKED: servidor de verdade (dev auth + MemoryStore), bot ligado por variável de ambiente.
//  • só a conta dona cai contra o bot (outra conta sozinha na fila continua esperando);
//  • só no Relâmpago (ranked_3min) por padrão;
//  • o bot joga lances legais sozinho (Stockfish nível Madeira ou aleatório), o relógio corre;
//  • partida Ranked NORMAL: PL/liga/placar gravados para as duas contas;
//  • sem as variáveis: nenhum bot.
const crypto = require('crypto');
const { Position } = require('../../online_v021/chess_rules');
const { startServer, client, check, summary } = require('./helpers.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const devId = name => { const h = crypto.createHash('sha256').update('dev:' + name).digest('hex'); return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-a${h.slice(17, 20)}-${h.slice(20, 32)}`; };
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  const st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); await c.next('acct_state'); }
  return c;
}
const sq = ([x, y]) => 'abcdefgh'[x] + (8 - y);

(async () => {
  const BOT = 'BotMadeira', DONO = 'DonoTeste', OUTRO = 'OutroJog';
  const env = { FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_RANKED_TEST_BOT_UID: devId(BOT),
    FRAIHA_RANKED_TEST_OWNERS: devId(DONO), FRAIHA_RANKED_TEST_BOT_WAIT_MS: '600' };
  const s = await startServer(env);
  try {
    // a conta do bot existe (perfil criado uma vez, como qualquer conta)
    const b0 = await login(s.port, BOT); b0.ws.close(); await sleep(200);
    // 1. outra conta sozinha na fila do Relâmpago: NUNCA cai contra o bot
    const outro = await login(s.port, OUTRO);
    outro.send({ type: 'ranked_queue', mode: 'ranked_3min' }); await outro.next('ranked_queued');
    let got = null; try { got = await outro.next('ranked_found', 2500); } catch {}
    check(!got, 'conta que não é a dona: continua na fila, sem bot');
    outro.send({ type: 'ranked_cancel' }); outro.ws.close(); await sleep(200);
    // 2. dono em outra fila (Rápida): sem bot (só Relâmpago)
    const dono = await login(s.port, DONO);
    dono.send({ type: 'ranked_queue', mode: 'ranked_5min' }); await dono.next('ranked_queued');
    got = null; try { got = await dono.next('ranked_found', 2000); } catch {}
    check(!got, 'dono na Rápida: sem bot (só Relâmpago)');
    dono.send({ type: 'ranked_cancel' }); await sleep(300); dono.inbox.length = 0;
    // 3. dono no Relâmpago: cai contra o bot depois da espera
    const t0 = Date.now();
    dono.send({ type: 'ranked_queue', mode: 'ranked_3min' }); await dono.next('ranked_queued');
    const found = await dono.next('ranked_found', 5000);
    check(found.opponent.nickname === BOT && Date.now() - t0 >= 500, `dono no Relâmpago: pareado com ${found.opponent.nickname} depois de esperar alguém de verdade`);
    const me = found.you, id = found.match_id;
    // espelho local da partida: aplica os lances do bot, joga lances aleatórios legais pelo dono
    const pos = new Position(); let botMoves = 0, illegal = false;
    const deadline = Date.now() + 45000;
    while (pos.ply < 12 && Date.now() < deadline) {
      const st = await dono.next(m => m.type === 'ranked_state' && m.match_id === id && m.status === 'playing' && (m.position.ply > pos.ply || (m.position.ply === pos.ply && m.position.turn === me)), 8000);
      if (st.position.ply > pos.ply) {   // lance do bot
        const lm = st.last_move; const r = pos.play({ from: lm.from, to: lm.to, promotion: 'Q' });
        if (!r) illegal = true; botMoves++;
      }
      if (pos.turn === me && st.position.turn === me) {
        const legal = pos.legalMoves(); const m = legal[Math.floor(Math.random() * legal.length)];
        pos.play(m);
        dono.send({ type: 'ranked_move', match_id: id, from: m.from, to: m.to, promotion: m.promotion });
      }
    }
    check(botMoves >= 5 && !illegal, `bot jogou ${botMoves} lances sozinho, todos legais`);
    // 4. dono desiste depois do mínimo: resultado Ranked normal, gravado para as duas contas
    dono.send({ type: 'ranked_resign', match_id: id });
    const res = await dono.next('ranked_result', 8000);
    check(res.outcome === 'loss' && !res.early && res.saved === true, 'desistência depois de 10+ meios-lances: derrota normal, gravada');
    dono.send({ type: 'acct_refresh' }); const acc = await dono.next('acct_state');
    check(acc.ranked.ranked_3min.matches === 1 && acc.ranked.ranked_3min.losses === 1, 'placar do dono: 1 partida, 1 derrota (Relâmpago)');
    const bot = await login(s.port, BOT); const accb = await bot.next('acct_state').catch(() => null);
    bot.send({ type: 'acct_refresh' }); const ab = await bot.next('acct_state');
    check(ab.ranked.ranked_3min.matches === 1 && ab.ranked.ranked_3min.wins === 1 && ab.ranked.ranked_3min.pl > 0, `conta do bot: 1 vitória, +${ab.ranked.ranked_3min.pl} PL (partida normal)`);
    void accb; bot.ws.close(); dono.ws.close();
  } finally { s.stop(); }
  // 5. sem as variáveis: dono sozinho na fila, nada de bot
  const s2 = await startServer({ FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200' });
  try {
    const dono = await login(s2.port, DONO);
    dono.send({ type: 'ranked_queue', mode: 'ranked_3min' }); await dono.next('ranked_queued');
    let got = null; try { got = await dono.next('ranked_found', 2500); } catch {}
    check(!got, 'sem FRAIHA_RANKED_TEST_*: bot desligado');
    dono.ws.close();
  } finally { s2.stop(); }
  // 6. padrão do STAGING (FRAIHA_ENV=staging): contas de teste do dono; produção/sem ambiente: desligado; "off" desliga
  { const { RankedTestBot, STAGING_PADRAO } = require('../../online_v021/ranked/test_bot');
    const R = { rated: true };
    const st = new RankedTestBot(R, { env: { FRAIHA_ENV: 'staging' } });
    check(st.enabled() && st.botUid === STAGING_PADRAO.bot && st.owners.has(STAGING_PADRAO.owners) && st.modes.join() === 'ranked_3min', 'staging: bot padrão ligado (SextoSen1 contra SextoSentro, só Relâmpago)');
    check(!new RankedTestBot(R, { env: {} }).enabled() && !new RankedTestBot(R, { env: { FRAIHA_ENV: 'production' } }).enabled(), 'produção / sem FRAIHA_ENV: desligado');
    check(!new RankedTestBot(R, { env: { FRAIHA_ENV: 'staging', FRAIHA_RANKED_TEST_BOT: 'off' } }).enabled(), 'staging com FRAIHA_RANKED_TEST_BOT=off: desligado');
    check(!new RankedTestBot({ rated: false }, { env: { FRAIHA_ENV: 'staging' } }).enabled(), 'Casual: nunca tem bot'); }
  summary('RANKED_BOT_TESTE');
})().catch(e => { console.error(e); process.exit(1); });
