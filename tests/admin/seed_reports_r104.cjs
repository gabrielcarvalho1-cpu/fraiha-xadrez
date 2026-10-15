'use strict';
// R104 · cria denúncias de exemplo num servidor LOCAL de desenvolvimento (só 127.0.0.1) para ver a tela Denúncias do Admin.
const { client } = require('../server/helpers.cjs');
const port = Number(process.argv[2] || 8140);
async function account(name, nick) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name }); await c.next('acct_state', 5000);
  c.send({ type: 'acct_create_profile', nickname: nick, avatar_id: 'warrior' }); c.state = await c.next(m => m.type === 'acct_state' || m.type === 'acct_error', 5000).catch(() => null);
  return c;
}
(async () => {
  const ana = await account('rep_a', 'AnaDenuncia'), bru = await account('rep_b', 'BrunoChato'), cai = await account('rep_c', 'CaioTeste');
  const id = c => c.state.profile.user_id;
  for (const [x, y] of [[ana, bru], [cai, bru]]) {
    x.send({ type: 'social_request', user_id: id(y) }); await x.next(m => m.type.startsWith('social_'), 3000).catch(() => {});
    y.send({ type: 'social_accept', user_id: id(x) }); await y.next(m => m.type.startsWith('social_'), 3000).catch(() => {});
  }
  for (const t of ['você joga muito mal, desinstala', 'vou te achar no ranking e te humilhar', 'perdedor kkkk']) {
    bru.send({ type: 'dm_send', user_id: id(ana), text: t }); await bru.next('dm_msg', 3000).catch(() => {}); await new Promise(r => setTimeout(r, 600));
  }
  ana.send({ type: 'social_report', user_id: id(bru), from: 'dm' }); console.log(JSON.stringify(await ana.next(m => m.type.startsWith('social_'), 3000).catch(e => String(e))));
  cai.send({ type: 'social_report', user_id: id(bru) }); console.log(JSON.stringify(await cai.next(m => m.type.startsWith('social_'), 3000).catch(e => String(e))));
  ana.send({ type: 'social_report', user_id: id(cai) }); await ana.next(m => m.type.startsWith('social_'), 3000).catch(() => {});
  console.log('REPORTS OK');
})().catch(e => { console.error(e); process.exit(1); });
