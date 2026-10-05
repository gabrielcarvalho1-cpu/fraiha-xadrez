'use strict';
// R35 · amigo automático para tests/party_client_test.gd: PeerParty envia pedido de amizade para o alvo,
// aceita convites de MARCHA REAL / XEQUE e joga a vez dele com o mesmo motor do servidor.
const { client } = require('./helpers.cjs');
const { Marcha, chooseAI } = require('../../online_v021/modes/marcha_rules');
const port = Number(process.argv[2]), target = process.argv[3] || 'GodotParty';
const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:PeerParty' });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: 'PeerParty' }); st = await c.next('acct_state', 5000); }
  if (process.env.PEER_FOUNDER) {   // R41 · amigo Fundador (selo/título/moldura/avatar na mesa)
    c.send({ type: 'dev_set_entitlements', is_founder: true, club_active: true, club_expires_at: new Date(Date.now() + 86400e3).toISOString() });
    await c.next('acct_state', 5000); await new Promise(r => setTimeout(r, 900));
    c.send({ type: 'acct_set_cosmetics', avatar_id: 'fundador', badge: 'fundador', title: 'fundador', frame: 'fundador' });
    await c.next('acct_cosmetics_saved', 5000);
  }
  // procura o alvo e pede amizade
  for (let i = 0; i < 60; i++) {
    c.send({ type: 'social_search', query: target });
    const r = await c.next(m => m.type === 'social_search' || m.type === 'social_error', 4000).catch(() => null);
    const u = r && (r.results || []).find(x => x.nickname === target);
    if (u) { c.send({ type: 'social_request', user_id: u.user_id }); console.log('pedido enviado'); break; }
    await sleep(500);
  }
  let room = '', game = '';
  c.ws.on('message', raw => {
    const m = JSON.parse(raw);
    if (m.type === 'invite_received') setTimeout(() => c.send({ type: 'invite_accept', invite_id: m.invite.id }), 800);
    if (m.type === 'party_start') { room = m.room_id; game = m.game; console.log('mesa', game, room); }
    if (m.type === 'party_event' && m.ev === 'turn' && m.snapshot.my_turn && m.snapshot.turn === 0) {
      const s = m.snapshot;
      setTimeout(() => {
        if (game === 'marcha') {
          const g = new Marcha();
          g.pawns = s.pawns; g.hands = s.hand_counts.map((n, i) => (i === 0 ? s.my_hand.slice() : Array(n).fill('2'))); g.turn = 0; g.winner = s.winner;
          c.send({ type: 'party_action', room_id: room, action: chooseAI(g, 0, null) });
        } else if (s.can_challenge && Math.random() < 0.5) c.send({ type: 'party_action', room_id: room, action: { kind: 'challenge' } });
        else c.send({ type: 'party_action', room_id: room, action: { kind: 'play', idx: [0] } });
      }, 300);
    }
    if (m.type === 'party_event' && m.ev === 'end') console.log('fim', game);
    // o alvo saiu: o teste segue para o próximo modo, então PeerParty também sai (a mesa encerra)
    if (m.type === 'party_event' && m.ev === 'left') setTimeout(() => c.send({ type: 'party_leave', room_id: room }), 200);
  });
  setInterval(() => c.send({ type: 'ping' }), 10000);
})().catch(e => { console.error(e); process.exit(1); });
