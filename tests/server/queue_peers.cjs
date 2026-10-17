'use strict';
// R144 · jogadores automáticos para tests/r144_fila_online_client.gd: entram na fila do XEQUE e da MARCHA
// (um de cada vez, quando a fila do Godot chega) e saem da mesa logo depois de ela começar.
const { client } = require('./helpers.cjs');
const port = Number(process.argv[2]), game = process.argv[3] || 'xeque', n = Number(process.argv[4] || 3);
const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const peers = [];
  for (let i = 0; i < n; i++) {
    const c = client(port); await c.open();
    const name = 'Fila' + game + i;
    c.send({ type: 'acct_auth', access_token: 'dev:' + name });
    let st = await c.next('acct_state', 5000);
    if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
    peers.push(c);
  }
  await sleep(Number(process.env.PEER_DELAY_MS || 4000));   // o Godot entra primeiro
  for (const c of peers) { c.send({ type: 'party_queue', game }); await sleep(150); }
  for (const c of peers) {
    const s = await c.next('party_start', 30000).catch(() => null);
    console.log(s ? 'mesa ' + s.room_id + ' humanos=' + s.players.filter(p => !p.bot).length : 'sem mesa');
  }
  await sleep(4000);
  for (const c of peers) c.close();
  process.exit(0);
})();
