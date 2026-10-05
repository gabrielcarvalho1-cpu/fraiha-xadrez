'use strict';
// R42.1 · adversário automático (conta dev) para partidas online seguidas contra o cliente Godot.
// argv: PORTA AÇÕES — uma por partida, separadas por vírgula, no formato tipo:ação[:segundos]
//   tipo = ranked | casual ; ação = resign (o adversário desiste → cliente VENCE) |
//   wait (espera o cliente desistir → cliente PERDE). segundos = espera antes de desistir (padrão 1,5).
const { client } = require('./helpers.cjs');
const port = Number(process.argv[2]);
const actions = String(process.argv[3] || 'ranked:resign').split(',');
const MODE = { ranked: 'ranked_3min', casual: 'casual_3min' };
(async () => {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:PeerRk' + process.pid }); await c.next('acct_state');
  c.send({ type: 'acct_create_profile', nickname: 'Peer' + (process.pid % 100000) }); await c.next('acct_state');
  for (const a of actions) {
    const [kind, act, secs] = a.split(':');
    await new Promise(r => setTimeout(r, 1500));
    c.send({ type: kind + '_queue', mode: MODE[kind] }); await c.next(kind + '_queued', 10000);
    const f = await c.next(kind + '_found', 180000);
    await c.next(m => m.type === kind + '_state' && m.match_id === f.match_id && m.status === 'playing', 20000);
    if (act === 'resign') { await new Promise(r => setTimeout(r, Number(secs || 1.5) * 1000)); c.send({ type: kind + '_resign', match_id: f.match_id }); }
    await c.next(m => m.type === kind + '_result' && m.match_id === f.match_id, 180000);
  }
  setTimeout(() => process.exit(0), 3000);
})().catch(e => { console.error(e); process.exit(1); });
