'use strict';
// R41 · Adversário Fundador (selo, título, moldura e avatar Fundador) para o teste do cliente Godot.
// Entra na fila Casual, joga um lance quando for a vez dele e desiste depois de alguns segundos.
const { client } = require('./helpers.cjs');
const port = Number(process.argv[2]), mode = process.argv[3] || 'casual_3min', holdMs = Number(process.argv[4] || 9000);
const sq = s => ['abcdefgh'.indexOf(s[0]), 8 - Number(s[1])];
(async () => {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:ReiFundador' });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: 'ReiFundador' }); st = await c.next('acct_state', 5000); }
  c.send({ type: 'dev_set_entitlements', is_founder: true, club_active: true, club_expires_at: new Date(Date.now() + 86400e3).toISOString() });
  await c.next('acct_state'); await new Promise(r => setTimeout(r, 900));
  c.send({ type: 'acct_set_cosmetics', avatar_id: 'fundador', badge: 'fundador', title: 'fundador', frame: 'fundador' });
  await c.next('acct_cosmetics_saved');
  c.send({ type: 'casual_queue', mode }); await c.next('casual_queued', 5000);
  const f = await c.next('casual_found', 60000);
  const me = f.you; let played = false;
  c.ws.on('message', raw => {
    const m = JSON.parse(raw);
    if (m.type === 'casual_state' && m.status === 'playing' && m.position.turn === me && !played) {
      played = true;
      const [a, b] = me === 'w' ? ['e2', 'e4'] : ['e7', 'e5'];
      setTimeout(() => c.send({ type: 'casual_move', match_id: f.match_id, from: sq(a), to: sq(b) }), 300);
    }
  });
  setTimeout(() => c.send({ type: 'casual_resign', match_id: f.match_id }), holdMs);
  setTimeout(() => process.exit(0), holdMs + 4000);
})().catch(e => { console.error(e); process.exit(1); });
