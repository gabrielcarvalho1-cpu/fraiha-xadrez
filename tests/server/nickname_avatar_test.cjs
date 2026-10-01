'use strict';
// 0004: nome público único (case-insensitive), troca com cooldown de 30 dias (relógio do servidor),
// verificação de disponibilidade e foto de perfil (upload validado). Backend em memória (dev).
const { startServer, client, check, summary } = require('./helpers.cjs');
const { validateNickname, cleanNickname, nextNickChange, NICK_COOLDOWN_MS, MemoryStore } = require('../../online_v021/accounts/store');
const { validateAvatarUpload } = require('../../online_v021/accounts/avatar');
const zlib = require('zlib');

function png(w, h) {   // PNG mínimo válido (cinza) só com cabeçalhos corretos
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 0; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const raw = Buffer.alloc((w + 1) * h, 0x80); for (let y = 0; y < h; y++) raw[y * (w + 1)] = 0;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
function crc32(buf) { let c, crc = 0xFFFFFFFF; for (let n = 0; n < buf.length; n++) { c = (crc ^ buf[n]) & 0xFF; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; crc = (crc >>> 8) ^ c; } return (crc ^ 0xFFFFFFFF) >>> 0; }

(async () => {
  // ---- regras puras
  check(validateNickname('Gabriel').nickname === 'Gabriel', 'nome simples válido');
  check(validateNickname('Gabriel_01').nickname === 'Gabriel_01', 'letras, números e _ válidos');
  check(!!validateNickname('ab').error, 'mínimo 3');
  check(!!validateNickname('a'.repeat(21)).error && !validateNickname('a'.repeat(20)).error, 'máximo 20');
  check(!!validateNickname('Ga briel').error, 'espaço interno recusado');
  check(validateNickname('  Gabriel  ').nickname === 'Gabriel', 'espaços nas pontas removidos');
  check(validateNickname('Gab​riel‮').nickname === 'Gabriel', 'invisíveis e bidi removidos');
  check(validateNickname('Ｇａｂｒｉｅｌ').nickname === 'Gabriel', 'normalização NFKC');
  check(!!validateNickname('').error && !!validateNickname('​​​').error, 'vazio / só invisível recusado');
  check(!!validateNickname('Gabriél').error, 'acento recusado em nome novo');
  check(!!validateNickname('fundador').error, 'reservado recusado');
  check(cleanNickname(null) === '', 'cleanNickname tolera null');
  const past = new Date(Date.now() - 31 * 24 * 3600e3).toISOString();
  check(nextNickChange({ nickname_changed_at: past }) < new Date().toISOString(), 'próxima troca calculada a partir de nickname_changed_at');

  // ---- cooldown no store (relógio do servidor)
  const ms = new MemoryStore();
  await ms.createProfile('u1', 'Gabriel', 'warrior');
  let r = await ms.changeNickname('u1', 'Gabriel2');
  check(r.profile && r.profile.nickname === 'Gabriel2' && r.profile.nickname_changed_at, 'primeira troca permitida e carimbada');
  r = await ms.changeNickname('u1', 'Gabriel3');
  check(r.code === 'nickname_cooldown' && r.next_change_at, 'segunda troca bloqueada por 30 dias com data da próxima');
  ms.profiles.get('u1').nickname_changed_at = new Date(Date.now() - NICK_COOLDOWN_MS - 1000).toISOString();
  r = await ms.changeNickname('u1', 'Gabriel3');
  check(r.profile && r.profile.nickname === 'Gabriel3', 'após 30 dias a troca volta a ser permitida');
  await ms.createProfile('u2', 'Outro', 'warrior');
  r = await ms.changeNickname('u2', 'GABRIEL3');
  check(r.code === 'nickname_taken', 'troca para nome igual (case-insensitive) é recusada');
  check(await ms.nicknameAvailable('gabriel3') === false && await ms.nicknameAvailable('Livre') === true, 'disponibilidade case-insensitive');
  check(await ms.nicknameAvailable('gabriel3', 'u1') === true, 'o próprio nome do jogador conta como disponível para ele');

  // ---- avatar: validação do upload
  const ok = png(512, 512);
  check(validateAvatarUpload(ok.toString('base64')).mime === 'image/png', 'PNG 512x512 aceito');
  check(!!validateAvatarUpload(png(300, 512).toString('base64')).error, 'dimensão errada recusada');
  check(!!validateAvatarUpload(Buffer.from('not an image').toString('base64')).error, 'formato desconhecido recusado');
  check(!!validateAvatarUpload(Buffer.alloc(500 * 1024, 1).toString('base64')).error, 'arquivo grande recusado');
  check(!!validateAvatarUpload('').error, 'vazio recusado');

  // ---- servidor (dev, memória)
  const s = await startServer({ FRAIHA_DEV_AUTH: '1' });
  const c = client(s.port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:gab' }); await c.next('acct_state');
  c.send({ type: 'acct_check_nickname', nickname: 'Gabriel' });
  let m = await c.next('acct_nickname_check');
  check(m.available === true, 'verificação: nome livre');
  c.send({ type: 'acct_create_profile', nickname: 'Gabriel' });
  let st = await c.next('acct_state');
  check(st.profile.nickname === 'Gabriel' && st.profile.nickname_next_change_at === null, 'perfil criado; sem cooldown antes da primeira troca');
  const d = client(s.port); await d.open();
  d.send({ type: 'acct_auth', access_token: 'dev:outro' }); await d.next('acct_state');
  d.send({ type: 'acct_check_nickname', nickname: 'GABRIEL' });
  m = await d.next('acct_nickname_check');
  check(m.available === false && m.code === 'nickname_taken', 'verificação: nome usado (case-insensitive)');
  d.send({ type: 'acct_check_nickname', nickname: 'ab' });
  m = await d.next('acct_nickname_check');
  check(m.available === false && m.code === 'nickname_invalid', 'verificação: inválido');
  c.send({ type: 'acct_change_nickname', nickname: 'Gabriel_Rei' });
  m = await c.next('acct_nickname_changed');
  st = await c.next('acct_state');
  check(m.nickname === 'Gabriel_Rei' && st.profile.nickname === 'Gabriel_Rei' && st.profile.nickname_next_change_at, 'troca de nome aplicada e próxima data informada pelo servidor');
  c.send({ type: 'acct_change_nickname', nickname: 'Gabriel_Rei2' });
  m = await c.next('acct_error');
  check(m.code === 'nickname_cooldown' && m.next_change_at, 'segunda troca recusada com nickname_cooldown + next_change_at');
  // avatar
  c.send({ type: 'acct_avatar_upload', data: ok.toString('base64') });
  m = await c.next('acct_avatar_saved');
  check(!!m.avatar_url, 'upload de avatar válido grava avatar_url');
  st = await c.next('acct_state');
  check(!!st.profile.avatar_url, 'acct_state traz avatar_url');
  c.send({ type: 'acct_avatar_upload', data: png(100, 100).toString('base64') });
  m = await c.next('acct_error');
  check(m.code === 'avatar_invalid', 'upload inválido recusado');
  c.send({ type: 'acct_avatar_clear' });
  m = await c.next('acct_avatar_saved');
  check(m.avatar_url === null, 'remover foto volta ao avatar padrão');
  // busca de perfil mostra nick novo e nunca e-mail
  d.send({ type: 'acct_create_profile', nickname: 'Outro' }); await d.next('acct_state');
  d.send({ type: 'social_search', query: 'gabriel' });
  const res = await d.next(x => x.type === 'social_search' || x.type === 'social_error');
  check(res.type === 'social_search' && (JSON.stringify(res).includes('Gabriel_Rei') && !JSON.stringify(res).includes('@')), 'pesquisa mostra o nick novo e sem e-mail');
  c.close(); d.close(); s.stop();
  summary('NICKNAME_AVATAR');
})().catch(e => { console.error(e); process.exitCode = 1; });
