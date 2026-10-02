'use strict';
// R31: identidade premium (avatar/ícone/título/moldura validados pelo servidor), Destaque social
// (selo visível para os outros) e liberação de direitos por pagamento (Fundador = +30 dias de Club).
const { startServer, client, check, summary } = require('./helpers.cjs');
const { MemoryStore, extendClub } = require('../../online_v021/accounts/store');
const Cosmetics = require('../../online_v021/accounts/cosmetics');
(async () => {
  // ---------- regras puras ----------
  const none = { is_founder: false, club_active: false };
  const founder = { is_founder: true, club_active: false };
  const club = { is_founder: false, club_active: true };
  check(Cosmetics.validate({ badge: 'fundador' }, none, []).code === 'cosmetic_locked', 'Selo Fundador sem o pacote: recusado');
  check(Cosmetics.validate({ badge: 'fundador' }, founder, []).ok, 'Selo Fundador com o pacote: aceito');
  check(Cosmetics.validate({ badge: 'club_b' }, founder, []).code === 'cosmetic_locked', 'Selo Club sem Club ativo: recusado');
  check(Cosmetics.validate({ badge: 'club_b', avatar_id: 'club_avatar_c' }, club, []).ok, 'Club ativo: selo e avatar Club aceitos');
  check(Cosmetics.validate({ avatar_id: 'fundador' }, club, []).code === 'cosmetic_locked', 'avatar Fundador exige o pacote');
  check(Cosmetics.validate({ avatar_id: 'ouro_reward' }, none, ['madeira']).code === 'cosmetic_locked', 'avatar da escada exige o bot vencido');
  check(Cosmetics.validate({ avatar_id: 'madeira_reward' }, none, ['madeira']).ok, 'avatar da escada liberado pelo bot vencido');
  check(Cosmetics.validate({ avatar_id: 'madeira_reward' }, none, null).code === 'not_configured', 'escada sem tabela (0006): avatar da escada não é aceito às cegas');
  check(Cosmetics.validate({ avatar_id: 'hacker' }, founder, []).code === 'cosmetic_invalid', 'avatar inexistente recusado');
  check(Cosmetics.validate({ title: 'rei' }, founder, []).code === 'cosmetic_invalid', 'título inexistente recusado');
  check(Cosmetics.validate({ frame: 'fundador' }, founder, []).ok && Cosmetics.validate({ frame: 'club' }, founder, []).code === 'cosmetic_locked', 'molduras por direito');
  const eff = Cosmetics.effective({ avatar_id: 'club_avatar_a', profile_badge: 'club_a', profile_title: 'club', profile_frame: 'club' }, { is_founder: false, club_active: true, club_expires_at: new Date(Date.now() - 1000).toISOString() });
  check(eff.badge === '' && eff.title === '' && eff.frame === 'liga' && eff.avatar_id === 'warrior', 'Club vencido: selo/título/moldura/avatar do Club somem para os outros');
  // ---------- direitos por pagamento (memória = mesma regra da função 0007) ----------
  const st = new MemoryStore();
  await st.createProfile('u1', 'Rei', 'warrior');
  let e = await st.grantEntitlement('u1', 'founder', 'pix');
  const days = (new Date(e.club_expires_at) - Date.now()) / 86400e3;
  check(e.is_founder && e.club_active && days > 29.9 && days < 30.1, 'Fundador: is_founder + 30 dias de Club (%s)'.replace('%s', days.toFixed(2)));
  e = await st.grantEntitlement('u1', 'club_monthly', 'pix');
  const days2 = (new Date(e.club_expires_at) - Date.now()) / 86400e3;
  check(days2 > 59.9 && days2 < 60.1, 'Club mensal soma 30 dias ao que resta (60)');
  check((await st.grantEntitlement('u1', 'xyz', 'pix')) === null, 'produto desconhecido não libera nada');
  const pay = await st.createPayment({ user_id: 'u1', product_id: 'club_monthly', method: 'pix', provider: 'test', provider_ref: 'ch_1', amount_cents: 1990, status: 'pending' });
  check(pay.status === 'pending' && (await st.getPayment('test', 'ch_1')).product_id === 'club_monthly', 'pagamento criado e consultado');
  const m1 = await st.markPayment('test', 'ch_1', 'paid');
  const m2 = await st.markPayment('test', 'ch_1', 'paid');
  check(m1 && m1.status === 'paid' && m2 === null, 'webhook repetido não libera duas vezes (pending → paid uma vez)');
  check(new Date(extendClub(new Date(Date.now() - 5 * 86400e3).toISOString(), 30)) - Date.now() > 29.9 * 86400e3, 'Club vencido: 30 dias a partir de agora');
  // ---------- WS: acct_set_cosmetics + Destaque social ----------
  const s = await startServer({ FRAIHA_DEV_AUTH: '1' });
  const a = client(s.port), b = client(s.port);
  await a.open(); await b.open();
  a.send({ type: 'acct_auth', access_token: 'dev:ana' }); await a.next('acct_state');
  a.send({ type: 'acct_create_profile', nickname: 'AnaFundadora' }); let sa = await a.next('acct_state');
  check(sa.cosmetics && sa.cosmetics.badge === '' && sa.cosmetics.frame === 'liga', 'acct_state traz cosmetics (vazio)');
  b.send({ type: 'acct_auth', access_token: 'dev:bia' }); await b.next('acct_state');
  b.send({ type: 'acct_create_profile', nickname: 'BiaAmiga' }); await b.next('acct_state');
  a.send({ type: 'acct_set_cosmetics', badge: 'fundador' });
  let r = await a.next('acct_cosmetics_error');
  check(r.code === 'cosmetic_locked' && r.field === 'badge', 'sem Fundador: Selo Fundador recusado pelo servidor');
  a.send({ type: 'dev_set_entitlements', is_founder: true, club_active: true, club_expires_at: new Date(Date.now() + 86400e3).toISOString() });
  await a.next('acct_state');
  await new Promise(res => setTimeout(res, 900));
  a.send({ type: 'acct_set_cosmetics', avatar_id: 'fundador', badge: 'fundador', title: 'fundador', frame: 'fundador' });
  r = await a.next('acct_cosmetics_saved');
  check(r.avatar_id === 'fundador' && r.badge === 'fundador' && r.title === 'fundador' && r.frame === 'fundador', 'Fundador salva avatar, ícone, título e moldura');
  sa = await a.next('acct_state');
  check(sa.cosmetics.badge === 'fundador' && sa.profile.profile_badge === 'fundador', 'acct_state reflete a escolha');
  a.send({ type: 'acct_set_cosmetics', badge: 'club_c' });
  r = await a.next(x => x.type === 'acct_cosmetics_error' || x.type === 'acct_cosmetics_saved');
  check(r.type === 'acct_cosmetics_error' && r.code === 'rate_limited', 'pedidos em rajada: rate_limited');
  await new Promise(res => setTimeout(res, 900));
  // Bia procura Ana: vê o selo e as flags (Destaque social)
  b.send({ type: 'social_search', query: 'AnaFun' });
  const found = await b.next('social_search_result').catch(() => null) || await b.next(x => x.type && x.type.startsWith('social_'));
  const hit = found && (found.results || found.users || []).find(u => u.nickname === 'AnaFundadora');
  check(hit && hit.badge === 'fundador' && hit.founder === true && hit.title === 'fundador' && hit.avatar_id === 'fundador', 'Amigos/busca: outros veem selo, título e avatar do Fundador');
  // Club vence: selo do Club some para os outros, Fundador continua
  a.send({ type: 'acct_set_cosmetics', badge: 'club_c' }); await a.next('acct_cosmetics_saved');
  await a.next('acct_state');
  a.send({ type: 'dev_set_entitlements', is_founder: true, club_active: true, club_expires_at: new Date(Date.now() - 1000).toISOString() });
  await a.next('acct_state');
  await new Promise(res => setTimeout(res, 900));
  b.send({ type: 'social_search', query: 'AnaFun' });
  const found2 = await b.next(x => x.type && x.type.startsWith('social_search'));
  const hit2 = (found2.results || found2.users || []).find(u => u.nickname === 'AnaFundadora');
  check(hit2 && hit2.badge === '' && hit2.club === false && hit2.founder === true, 'Club vencido: selo Club escondido dos outros (escolha guardada)');
  a.close(); b.close(); s.stop();
  summary('PREMIUM_IDENTITY');
})().catch(e => { console.error(e); process.exitCode = 1; });
