'use strict';
// R119 · EMOTES na partida online: de graça para todos (inclusive convidado); os da Loja só para quem comprou;
// entregue aos dois pelo canal do chat (chat_msg com `emote`), 1 a cada 2,5 s, 12 por partida; id desconhecido recusa.
const { startServer, client, check, summary } = require('./helpers.cjs');
const { ChatHub } = require('../../online_v021/chat');
const Shop = require('../../online_v021/economy/store_catalog');
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function guest(port) { const c = client(port); await c.open(); c.send({ type: 'guest_auth' }); c.guest = await c.next('guest_state'); return c; }
async function pair(a, b, kind, mode) {
  a.send({ type: kind + '_queue', mode }); await a.next(kind + '_queued');
  b.send({ type: kind + '_queue', mode }); await b.next(kind + '_queued');
  const fa = await a.next(kind + '_found', 4000); await b.next(kind + '_found', 4000);
  await a.next(m => m.type === kind + '_state' && m.status === 'playing', 4000);
  return fa.match_id;
}

(async () => {
  // catálogo
  check(Shop.FREE_EMOTES.length === 7 && Shop.ofKind('emote').length === 13 && Shop.PASS_EMOTES.length === 5, 'catálogo: 7 emotes de graça + 13 na loja + 5 do passe');
  check(Shop.emoteText('emote_quase') === 'QUASE!' && !Shop.isFreeEmote('emote_quase'), 'emote do passe: texto do servidor, não é de graça');
  check(Shop.emoteText('emote_ola') === 'Olá!' && Shop.emoteText('emote_lenda') === 'Lenda!' && Shop.emoteText('xyz') === null, 'texto de cada emote vem do servidor');
  const gd = require('fs').readFileSync(require('path').join(__dirname, '../../economy/crown_store_catalog.gd'), 'utf8');
  check(Shop.FREE_EMOTES.every(e => gd.includes(`"id": "${e.id}", "text": "${e.text}"`)), 'emotes de graça iguais no cliente');

  const s = await startServer({ FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_MM_EXPAND_MS: '60000' });
  const a = await guest(s.port), b = await guest(s.port);
  const id = await pair(a, b, 'casual', 'casual_3min');
  a.send({ type: 'chat_emote', match_id: id, id: 'emote_boa_jogada' });
  const mb = await b.next('chat_msg'), ma = await a.next('chat_msg');
  check(mb.emote === 'emote_boa_jogada' && mb.text === 'Boa jogada!' && ma.id === mb.id, 'emote de graça chega aos dois (com o texto do servidor)');
  a.send({ type: 'chat_emote', match_id: id, id: 'emote_ola' });
  const e1 = await a.next('chat_error');
  check(e1.code === 'rate_limited', 'um emote de cada vez (2,5 s)');
  await sleep(2600);
  a.send({ type: 'chat_emote', match_id: id, id: 'emote_lenda' });
  const e2 = await a.next('chat_error');
  check(e2.code === 'emote_locked', 'emote da loja sem comprar: recusado');
  a.send({ type: 'chat_emote', match_id: id, id: 'emote_hack' });
  check((await a.next('chat_error')).code === 'invalid', 'emote desconhecido: recusado');
  await s.stop();

  // dono do emote comprado (unidade, sem rede)
  const sent = [];
  const hub = new ChatHub({ send: (ws, o) => sent.push(o) });
  hub.ownedEmotes = async uid => uid === 'dono' ? ['emote_lenda'] : [];
  let entregue = null;
  await hub.emote({}, 'dono', { type: 'chat_emote', id: 'emote_lenda' }, { scope: 'm1', entry: {} }, e => { entregue = e; });
  check(entregue && entregue.text === 'Lenda!', 'emote comprado: entregue');
  let n = 0;
  hub.now = (() => { let t = 1e6; return () => (t += 3000); })();
  for (let i = 0; i < 15; i++) await hub.emote({}, 'dono2', { type: 'chat_emote', id: 'emote_ola' }, { scope: 'm2', entry: {} }, () => n++);
  check(n === 12, 'no máximo 12 emotes por partida (' + n + ')');
  summary('EMOTES_R119');
})().catch(e => { console.error(e); process.exit(1); });
