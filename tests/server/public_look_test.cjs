'use strict';
// R41 · Selo, título e moldura (e founder/club) do jogador chegam aos OUTROS: Casual (fila), convite de
// xadrez, mesa da MARCHA REAL (party_start), DM e cartão de perfil. Free continua 'liga' / sem selo.
const { startServer, client, check, summary } = require('./helpers.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; return c;
}
const pause = () => sleep(90);
(async () => {
  const s = await startServer({ FRAIHA_DEV_AUTH: '1', FRAIHA_PARTY_INTRO_MS: '5' });
  const A = await login(s.port, 'AnaRei'), B = await login(s.port, 'BiaFree');
  A.send({ type: 'dev_set_entitlements', is_founder: true, club_active: true, club_expires_at: new Date(Date.now() + 86400e3).toISOString() });
  await A.next('acct_state'); await sleep(900);
  A.send({ type: 'acct_set_cosmetics', avatar_id: 'fundador', badge: 'fundador', title: 'fundador', frame: 'fundador' });
  await A.next('acct_cosmetics_saved'); await A.next('acct_state');
  const isFounderLook = (o) => o && o.badge === 'fundador' && o.title === 'fundador' && o.frame === 'fundador' && o.founder === true && o.club === true;
  const isFree = (o) => o && o.badge === '' && o.title === '' && o.frame === 'liga' && o.founder === false && o.club === false;
  // ---------- Casual pela fila ----------
  A.send({ type: 'casual_queue', mode: 'casual_5min' }); await A.next('casual_queued');
  B.send({ type: 'casual_queue', mode: 'casual_5min' }); await B.next('casual_queued');
  const fa = await A.next('casual_found', 5000), fb = await B.next('casual_found', 5000);
  check(isFounderLook(fb.opponent) && fb.opponent.avatar_id === 'fundador', 'Casual: o adversário vê selo, título, moldura e avatar do Fundador');
  check(isFree(fa.opponent), 'Casual: jogador free aparece sem selo, sem título, moldura da liga');
  const stB = await B.next('casual_state', 5000);
  const meA = stB.white.nickname === 'AnaRei' ? stB.white : stB.black;
  check(isFounderLook(meA), 'Casual: o estado da partida (white/black) também traz a identidade');
  A.send({ type: 'casual_resign' }); await sleep(300);
  // ---------- amizade + DM ----------
  await pause(); A.send({ type: 'social_request', user_id: B.id }); await A.next(m => m.type === 'social_ok' || m.type === 'social_error', 5000);
  await pause(); B.send({ type: 'social_accept', user_id: A.id }); await B.next(m => m.type === 'social_ok' || m.type === 'social_error', 5000);
  await pause(); A.send({ type: 'dm_send', user_id: B.id, text: 'oi' });
  const dm = await B.next('dm_msg', 5000);
  check(isFounderLook(dm.from), 'DM: a mensagem chega com a identidade de quem mandou');
  // ---------- cartão de perfil ----------
  await pause(); B.send({ type: 'social_card', user_id: A.id });
  const card = await B.next('social_card', 5000);
  check(card.card && card.card.frame === 'fundador' && card.card.badge === 'fundador' && card.card.title === 'fundador', 'cartão de perfil traz selo, título e moldura');
  // ---------- MARCHA REAL com amigo ----------
  B.inbox.splice(0); A.inbox.splice(0);
  await pause(); A.send({ type: 'invite_send', user_id: B.id, game: 'marcha' });
  const rec = await B.next('invite_received', 5000);
  check(isFounderLook(rec.invite.from) && isFree(rec.invite.to), 'convite: quem convida chega com selo/título/moldura');
  await pause(); B.send({ type: 'invite_accept', invite_id: rec.invite.id });
  const sb = await B.next('party_start', 5000);
  const ana = sb.players.find(p => p.name === 'AnaRei');
  check(isFounderLook(ana) && ana.avatar === 'fundador', 'MARCHA REAL: o amigo vê o selo, título, moldura e avatar na mesa');
  check(sb.players.filter(p => p.bot).every(p => p.frame === 'liga' && !p.founder), 'bots da mesa sem moldura premium');
  A.close(); B.close(); s.stop();
  summary('PUBLIC_LOOK');
})().catch(e => { console.error(e); process.exit(1); });
