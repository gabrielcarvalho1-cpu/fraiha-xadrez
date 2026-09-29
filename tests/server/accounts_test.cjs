'use strict';
const { startServer, client, check, summary } = require('./helpers.cjs');
const { SupabaseAuth } = require('../../online_v021/accounts/auth');
const { SupabaseStore } = require('../../online_v021/accounts/store');
(async () => {
  // 1. Sem configuração: contas desabilitadas, casual continua.
  let s = await startServer({ FRAIHA_DEV_AUTH: '', SUPABASE_URL: '', SUPABASE_SERVICE_ROLE_KEY: '' });
  let c = client(s.port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:x' });
  check((await c.next('acct_error')).code === 'accounts_disabled', 'sem Supabase: contas desabilitadas com mensagem clara');
  c.send({ type: 'create' });
  check((await c.next('welcome')).color === 'w', 'Online Casual continua criando sala');
  c.close(); s.stop();

  // 2. Modo dev: autenticação, perfil, nickname.
  s = await startServer({ FRAIHA_DEV_AUTH: '1' });
  check(s.log().includes('backend: dev'), 'servidor informa backend dev');
  c = client(s.port); await c.open();
  c.send({ type: 'acct_create_profile', nickname: 'Ana' });
  check((await c.next('acct_error')).code === 'auth_required', 'criar perfil sem login é recusado');
  c.send({ type: 'ranked_queue', mode: 'ranked_5min' });
  check((await c.next('acct_error')).code === 'auth_required', 'Ranked sem login é recusado');
  c.send({ type: 'acct_auth', access_token: 'nao-e-token' });
  check((await c.next('acct_error')).code === 'invalid_token', 'token inválido é recusado');
  c.send({ type: 'acct_auth', access_token: 'dev:ana' });
  let st = await c.next('acct_state');
  check(st.needs_nickname === true && st.profile === null, 'primeiro login pede nickname');
  check(st.persistent === false, 'modo dev informa que NÃO é persistente');
  for (const [nick, label] of [['ab', 'curto'], ['nome com espaço', 'espaço'], ['<script>', 'símbolos'], ['admin', 'reservado'], ['a'.repeat(17), 'longo']]) {
    c.send({ type: 'acct_create_profile', nickname: nick });
    check((await c.next('acct_error')).code === 'nickname_invalid', 'nickname inválido recusado: ' + label);
  }
  c.send({ type: 'acct_create_profile', nickname: 'AnaXadrez', avatar_id: 'mage' });
  st = await c.next('acct_state');
  check(st.profile && st.profile.nickname === 'AnaXadrez' && st.profile.avatar_id === 'mage', 'perfil criado com nickname e avatar');
  check(st.ranked && Object.keys(st.ranked).join() === 'ranked_3min,ranked_5min,ranked_10min,ranked_20min', 'quatro modalidades criadas');
  check(Object.values(st.ranked).every(r => r.league === 0 && r.pl === 0), 'todas começam em Madeira 0 PL');
  const d = client(s.port); await d.open();
  d.send({ type: 'acct_auth', access_token: 'dev:bia' }); await d.next('acct_state');
  d.send({ type: 'acct_create_profile', nickname: 'anaxadrez' });
  check((await d.next('acct_error')).code === 'nickname_taken', 'nickname duplicado (maiúsc./minúsc.) recusado');
  c.send({ type: 'acct_create_profile', nickname: 'OutroNome' });
  check((await c.next('acct_error')).message.includes('já existe'), 'não cria segundo perfil para a mesma conta');
  // reconexão: mesma conta reconhecida
  c.close(); const c2 = client(s.port); await c2.open();
  c2.send({ type: 'acct_auth', access_token: 'dev:ana' }); st = await c2.next('acct_state');
  check(st.profile && st.profile.nickname === 'AnaXadrez' && st.needs_nickname === false, 'nova conexão recupera o mesmo perfil');
  c2.send({ type: 'acct_logout' }); check(!!(await c2.next('acct_logged_out')), 'logout');
  c2.send({ type: 'acct_refresh' });
  check((await c2.next('acct_error')).code === 'auth_required', 'após logout não há usuário na conexão');
  c2.close(); d.close(); s.stop();

  // 3. Formato das chamadas ao Supabase (sem rede).
  const calls = [];
  const fake = async (url, opts = {}) => { calls.push({ url, opts }); return { ok: true, status: 200, json: async () => ({ id: 'u1', email: 'a@b', app_metadata: { provider: 'google' } }), text: async () => '[]' }; };
  const auth = new SupabaseAuth({ url: 'https://p.supabase.co/', apiKey: 'sb_publishable_x', fetchImpl: fake });
  const u = await auth.verify('x'.repeat(40));
  check(u.id === 'u1' && u.provider === 'google', 'SupabaseAuth lê usuário de /auth/v1/user');
  check(calls[0].url === 'https://p.supabase.co/auth/v1/user' && calls[0].opts.headers.Authorization === 'Bearer ' + 'x'.repeat(40), 'token enviado como Bearer ao Supabase Auth');
  await auth.verify('x'.repeat(40)); check(calls.length === 1, 'validação em cache (sem chamada repetida)');
  const store = new SupabaseStore({ url: 'https://p.supabase.co', serviceKey: 'sb_secret_y', fetchImpl: fake });
  await store.getRankedStats('u1');
  check(calls[1].url.startsWith('https://p.supabase.co/rest/v1/ranked_stats?user_id=eq.u1') && calls[1].opts.headers.apikey === 'sb_secret_y' && !calls[1].opts.headers.Authorization, 'PostgREST com secret key só no servidor');
  summary('ACCOUNTS');
})().catch(e => { console.error(e); process.exit(1); });
