'use strict';
// FRAIHA Admin · popula um servidor LOCAL de desenvolvimento (FRAIHA_DEV_AUTH=1, memória) com atividade REAL
// de jogo para ver o Admin funcionando: contas DEV, jogadores na Home, fila Ranked/Casual e partidas Casual.
// Nunca apontar para staging/produção (só aceita 127.0.0.1). Uso: node tests/admin/seed_dev.cjs <porta>
const { client } = require('../server/helpers.cjs');
const port = Number(process.argv[2] || 8140);
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function account(name, nick) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name }); await c.next('acct_state', 5000);
  c.send({ type: 'acct_create_profile', nickname: nick, avatar_id: 'warrior' }); await c.next(m => m.type === 'acct_state' || m.type === 'acct_error', 5000).catch(() => null);
  return c;
}
(async () => {
  const boss = await account('boss', 'Gabriel');
  const names = ['ReiFundador', 'DamaDeFerro', 'TorreAlta', 'BispoVeloz', 'CavaloLouco', 'PeaoValente', 'XequeMate', 'RoqueLongo', 'GambitoRei', 'SicilianaX'];
  const cs = [];
  for (const [i, n] of names.entries()) cs.push(await account('p' + i, n));
  // 2 partidas Casual (4 jogadores) — pareiam na hora
  for (const i of [0, 1, 2, 3]) cs[i].send({ type: 'casual_queue', mode: i < 2 ? 'casual_5min' : 'casual_10min' });
  await sleep(1500);
  // 1 partida Ranked (2 jogadores, mesma liga/PL inicial)
  for (const i of [4, 5]) cs[i].send({ type: 'ranked_queue', mode: 'ranked_3min' });
  await sleep(1500);
  // 1 esperando sozinho na fila Ranked 10 min, 1 na Casual 20 min
  cs[6].send({ type: 'ranked_queue', mode: 'ranked_10min' });
  cs[7].send({ type: 'casual_queue', mode: 'casual_20min' });
  // 3 convidados só na Home
  for (let i = 0; i < 3; i++) { const g = client(port); await g.open(); g.send({ type: 'guest_auth' }); }
  console.log('SEED OK — 11 contas DEV + 3 convidados; 3 partidas; 2 na fila. Ctrl+C para encerrar.');
  setInterval(() => {}, 1 << 30);
  void boss;
})().catch(e => { console.error('SEED FALHOU', e.message); process.exit(1); });
