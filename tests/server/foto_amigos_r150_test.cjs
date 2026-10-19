'use strict';
// R150 · FOTO DE PERFIL VISTA PELOS AMIGOS. Antes a foto trocada só aparecia para quem trocou: o perfil público
// levava só o avatar do catálogo e ninguém era avisado da troca. Agora:
//   · avatar_url (foto pública) viaja no perfil público (amigos, convites, mesa, adversário) via Cosmetics.look;
//   · trocar/remover a foto (ou avatar/selo/nome) avisa NA HORA os amigos conectados (friend_profile);
//   · quem não é amigo não recebe nada.
const { startServer, client, check, summary } = require('./helpers.cjs');
const Cosmetics = require('../../online_v021/accounts/cosmetics');
const zlib = require('zlib');
const sleep = ms => new Promise(r => setTimeout(r, ms));
function crc32(buf) { let c, crc = 0xFFFFFFFF; for (let n = 0; n < buf.length; n++) { c = (crc ^ buf[n]) & 0xFF; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; crc = (crc >>> 8) ^ c; } return (crc ^ 0xFFFFFFFF) >>> 0; }
function png(w, h) {
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8;
  const raw = Buffer.alloc((w + 1) * h, 0x80); for (let y = 0; y < h; y++) raw[y * (w + 1)] = 0;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; return c;
}
async function social(c, type, user_id) { await sleep(70); c.send({ type, user_id }); return c.next(m => m.type === 'social_ok' || m.type === 'social_error', 5000); }

(async () => {
  // ---- regra pura: só URL http(s) curta passa
  check(Cosmetics.look({ avatar_url: 'https://x.supabase.co/storage/v1/object/public/avatars/u.webp?v=1' }).avatar_url.startsWith('https://'), 'look leva a foto (https)');
  check(Cosmetics.look({}).avatar_url === null, 'sem foto = null');
  check(Cosmetics.look({ avatar_url: 'javascript:alert(1)' }).avatar_url === null, 'URL estranha recusada');
  check(Cosmetics.look({ avatar_url: 'https://a.com/' + 'x'.repeat(500) }).avatar_url === null, 'URL gigante recusada');

  const s = await startServer({ FRAIHA_DEV_AUTH: '1' });
  try {
    const A = await login(s.port, 'GabrielFoto'), B = await login(s.port, 'NamoradaFoto'), C = await login(s.port, 'EstranhoFoto');
    await social(A, 'social_request', B.id); await social(B, 'social_accept', A.id);
    await sleep(200); for (const c of [A, B, C]) c.inbox.splice(0);

    A.send({ type: 'acct_avatar_upload', data: png(512, 512).toString('base64') });
    const saved = await A.next('acct_avatar_saved');
    check(!!saved.avatar_url, 'A trocou a foto');
    const fp = await B.next(m => m.type === 'friend_profile', 3000).catch(() => null);
    check(fp && fp.profile.user_id === A.id && fp.profile.avatar_url === saved.avatar_url, 'amiga recebe NA HORA a foto nova de A (friend_profile)');
    await sleep(300);
    check(!C.inbox.some(m => m.type === 'friend_profile'), 'quem não é amigo não recebe nada');
    check(!A.inbox.some(m => m.type === 'friend_profile'), 'quem trocou não recebe o próprio aviso de amigo');

    B.send({ type: 'social_list' });
    const list = await B.next('social_list');
    const fa = (list.friends || []).find(f => f.user_id === A.id);
    check(fa && fa.avatar_url === saved.avatar_url, 'lista de amigos da amiga traz a foto de A');

    // a amiga também troca: A recebe a dela
    B.send({ type: 'acct_avatar_upload', data: png(512, 512).toString('base64') });
    const sb = await B.next('acct_avatar_saved');
    const fpa = await A.next(m => m.type === 'friend_profile', 3000).catch(() => null);
    check(fpa && fpa.profile.user_id === B.id && fpa.profile.avatar_url === sb.avatar_url, 'e A recebe a foto nova da amiga');

    // remover a foto também avisa (volta ao avatar do catálogo)
    A.send({ type: 'acct_avatar_clear' });
    await A.next('acct_avatar_saved');
    const fc = await B.next(m => m.type === 'friend_profile', 3000).catch(() => null);
    check(fc && fc.profile.user_id === A.id && !fc.profile.avatar_url, 'remover a foto avisa a amiga (volta ao avatar)');

    // trocar o avatar do catálogo também avisa
    await sleep(1100);
    A.send({ type: 'acct_set_cosmetics', avatar_id: 'archer' });
    const cs = await A.next(m => m.type === 'acct_cosmetics_saved' || m.type === 'acct_cosmetics_error', 3000);
    if (cs.type === 'acct_cosmetics_saved') {
      const fx = await B.next(m => m.type === 'friend_profile', 3000).catch(() => null);
      check(fx && fx.profile.avatar_id === 'archer', 'trocar o avatar do catálogo avisa a amiga');
    } else check(false, 'troca de avatar aceita (' + cs.code + ')');
  } finally { s.stop(); }
  summary('FOTO_AMIGOS_R150');
})().catch(e => { console.error(e); process.exitCode = 1; });
