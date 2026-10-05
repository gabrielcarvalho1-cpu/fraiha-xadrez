'use strict';
const { client } = require('./helpers.cjs');
const port = Number(process.argv[2]);
const sq = s => ['abcdefgh'.indexOf(s[0]), 8 - Number(s[1])];
(async () => {
  const c = client(port); await c.open();
  c.send({ type: 'guest_auth' }); await c.next('guest_state');
  c.send({ type: 'casual_queue', mode: 'casual_10min' }); await c.next('casual_queued');
  const f = await c.next('casual_found', 60000);
  const me = f.you; let played = 0, seen = 0;
  const moves = me === 'w' ? [['d2','d4'],['c2','c4'],['a2','a3'],['h2','h3']] : [['d7','d5'],['c7','c6'],['a7','a6'],['h7','h6']];
  c.ws.on('message', raw => {
    const m = JSON.parse(raw);
    if (m.type !== 'casual_state' || m.status !== 'playing') return;
    const ply = m.position.ply;
    if (m.position.turn === me && ply >= seen && played < moves.length) {
      seen = ply + 1; const [a, b] = moves[played++];
      setTimeout(() => c.send({ type: 'casual_move', match_id: f.match_id, from: sq(a), to: sq(b) }), 300);
    }
  });
  setTimeout(() => process.exit(0), 280000);
})().catch(e => { console.error(e); process.exit(1); });
