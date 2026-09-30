'use strict';
// Jogadores automáticos para o teste do cliente Godot de Amigos (tests/friends_client_test.gd).
// PeerAna e PeerBia enviam pedido para GodotAmigo; PeerCadu aceita qualquer pedido que receber.
const { client } = require('./helpers.cjs');
const port = Number(process.argv[2]), target = process.argv[3] || 'GodotAmigo';
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function login(name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; return c;
}
(async () => {
  const ana = await login('PeerAna'), bia = await login('PeerBia'), cadu = await login('PeerCadu');
  // PeerAna responde DMs do alvo com "eco: <texto>" depois de 1,5 s (dá tempo de testar não lidas).
  ana.ws.on('message', raw => { const m = JSON.parse(raw); if (m.type === 'dm_msg' && m.message.sender_id !== ana.id && m.message.body !== 'sem eco' && !m.message.body.startsWith('me convida')) setTimeout(() => ana.send({ type: 'dm_send', user_id: m.user_id, text: 'eco: ' + m.message.body }), 1500); });
  // Convites: DM "me convida <modo>" -> PeerAna convida; convites recebidos: 3 min aceita, 5 min recusa, outros ignora.
  ana.ws.on('message', raw => {
    const m = JSON.parse(raw);
    if (m.type === 'dm_msg' && m.message.sender_id !== ana.id && m.message.body.startsWith('me convida')) setTimeout(() => ana.send({ type: 'invite_send', user_id: m.user_id, mode: m.message.body.split(' ')[2] || 'casual_20min' }), 500);
    if (m.type === 'invite_received') setTimeout(() => {
      if (m.invite.mode === 'casual_3min') ana.send({ type: 'invite_accept', invite_id: m.invite.id });
      if (m.invite.mode === 'casual_5min') ana.send({ type: 'invite_decline', invite_id: m.invite.id });
    }, 1500);
  });
  cadu.ws.on('message', raw => { const m = JSON.parse(raw); if (m.type === 'social_event' && m.event === 'request_received') cadu.send({ type: 'social_accept', user_id: m.user.user_id }); });
  let found = null;
  for (let i = 0; i < 200 && !found; i++) {
    await sleep(700);
    ana.inbox.splice(0); ana.send({ type: 'social_search', query: target });
    const r = await ana.next(m => m.type === 'social_search' || m.type === 'social_error', 5000).catch(() => null);
    found = r && r.results && r.results.find(p => p.nickname === target);
  }
  if (!found) { console.log('PEER alvo não encontrado'); process.exit(1); }
  ana.send({ type: 'social_request', user_id: found.user_id });
  await sleep(300);
  bia.send({ type: 'social_request', user_id: found.user_id });
  console.log('PEER pedidos enviados');
  await sleep(150000);
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
