'use strict';
// Adversário automático (convidado) para o teste do cliente Godot no Casual.
// Joga 1 lance quando for a vez dele e desiste depois do segundo lance do cliente.
const { client } = require('./helpers.cjs');
const port = Number(process.argv[2]), mode = process.argv[3] || 'casual_3min';
const sq = s => ['abcdefgh'.indexOf(s[0]), 8 - Number(s[1])];
(async () => {
  const c = client(port); await c.open();
  c.send({ type: 'guest_auth' }); await c.next('guest_state');
  c.send({ type: 'casual_queue', mode }); await c.next('casual_queued');
  const f = await c.next('casual_found', 60000);
  const me = f.you; let played = 0, seen = 0;
  c.ws.on('message', raw => {
    const m = JSON.parse(raw);
    if (m.type === 'chat_msg' && m.from_color !== me) c.send({ type: 'chat_send', match_id: f.match_id, text: 'eco: ' + m.text });
    if (m.type !== 'casual_state' || m.status !== 'playing') return;
    const ply = m.position.ply;
    if (m.position.turn === me && ply >= seen) {
      seen = ply + 1;
      const theirs = me === 'w' ? Math.floor(ply / 2) : Math.floor((ply - 1) / 2) + 1;
      if (theirs >= 2 || played >= 2) { setTimeout(() => c.send({ type: 'casual_resign', match_id: f.match_id }), 400); return; }
      const moves = me === 'w' ? [['d2','d4'],['c2','c4']] : [['d7','d5'],['c7','c6']];
      const [a, b] = moves[played++];
      setTimeout(() => c.send({ type: 'casual_move', match_id: f.match_id, from: sq(a), to: sq(b) }), 300);
    }
    if (m.type === 'casual_result') setTimeout(() => process.exit(0), 300);
  });
  setTimeout(() => process.exit(0), 90000);
})().catch(e => { console.error(e); process.exit(1); });
