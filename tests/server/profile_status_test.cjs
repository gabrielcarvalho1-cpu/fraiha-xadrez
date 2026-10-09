'use strict';
// R55 · STATUS do perfil (cartão da Home): o servidor limpa e limita o texto, salva em profiles.settings
// (jsonb da 0001, sem migração) e devolve no acct_state em qualquer conexão da mesma conta.
const { startServer, client, check, summary } = require('./helpers.cjs');
const Status = require('../../online_v021/accounts/status');
const { MemoryStore } = require('../../online_v021/accounts/store');
const wait = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  // ---------- regras puras ----------
  check(Status.sanitize('  Bora   jogar\n\txadrez  ').status === 'Bora jogar xadrez', 'espaços, quebras e tabs viram um espaço (sem quebrar o painel)');
  check(Status.sanitize('a​b‮c\u0007d').status === 'a b c d', 'caracteres invisíveis/controle/bidi removidos');
  check(Status.sanitize('x'.repeat(80)).ok && Status.sanitize('x'.repeat(81)).code === 'status_too_long', 'limite de 80 caracteres');
  check(Status.sanitize('ç'.repeat(80)).ok && Status.sanitize('😀'.repeat(80)).ok, 'acentos e emoji contam como 1 caractere');
  check(Status.sanitize('').status === '' && Status.sanitize(null).status === '', 'vazio = volta ao texto padrão');
  check(Status.sanitize({ a: 1 }).code === 'status_invalid', 'tipo errado recusado');
  const st = new MemoryStore();
  await st.createProfile('u1', 'Rei', 'warrior');
  await st.setStatus('u1', 'Olá');
  check(Status.of(await st.getProfile('u1')) === 'Olá', 'MemoryStore guarda em settings.status');
  // ---------- SupabaseStore (fetch simulado): junta com as outras chaves de settings ----------
  const calls = [];
  const db = { settings: { theme: 'wood', lab: { coords: true } } };
  const fakeFetch = async (url, opts = {}) => {
    calls.push([opts.method || 'GET', url, opts.body || '']);
    let body;
    if ((opts.method || 'GET') === 'GET') body = [{ settings: db.settings }];
    else { db.settings = JSON.parse(opts.body).settings; body = [{ user_id: 'u9', settings: db.settings }]; }
    return { ok: true, status: 200, text: async () => JSON.stringify(body) };
  };
  const { SupabaseStore } = require('../../online_v021/accounts/store');
  const sup = new SupabaseStore({ url: 'https://x.supabase.co', serviceKey: 'sb_secret_test', fetchImpl: fakeFetch });
  const sr = await sup.setStatus('u9', 'Foco total');
  check(Status.of(sr.profile) === 'Foco total' && db.settings.theme === 'wood' && db.settings.lab.coords === true, 'Supabase: grava settings.status sem apagar as outras chaves');
  check(calls.length === 2 && calls[1][0] === 'PATCH' && calls[1][1].includes('user_id=eq.u9'), 'Supabase: lê e grava só a linha do próprio jogador');
  // ---------- WS ----------
  const s = await startServer({ FRAIHA_DEV_AUTH: '1' });
  const a = client(s.port);
  await a.open();
  a.send({ type: 'acct_auth', access_token: 'dev:ana' }); await a.next('acct_state');
  a.send({ type: 'acct_create_profile', nickname: 'AnaStatus' });
  let sa = await a.next('acct_state');
  check(sa.profile.status === '', 'perfil novo: sem status (o jogo mostra o padrão)');
  a.send({ type: 'acct_set_status', status: '  Rumo ao   Diamante!  ' });
  let r = await a.next('acct_status_saved');
  check(r.status === 'Rumo ao Diamante!', 'status salvo e limpo: ' + r.status);
  sa = await a.next('acct_state');
  check(sa.profile.status === 'Rumo ao Diamante!', 'acct_state traz o status novo');
  a.send({ type: 'acct_set_status', status: 'rápido demais' });
  r = await a.next('acct_status_error');
  check(r.code === 'rate_limited', 'duas alterações seguidas: aguarde um instante');
  await wait(1600);
  a.send({ type: 'acct_set_status', status: 'y'.repeat(81) });
  r = await a.next('acct_status_error');
  check(r.code === 'status_too_long', 'servidor recusa status longo demais');
  // outro "dispositivo" (nova conexão da mesma conta) e reconexão: o status continua
  const b = client(s.port);
  await b.open();
  b.send({ type: 'acct_auth', access_token: 'dev:ana' });
  const sb = await b.next('acct_state');
  check(sb.profile.status === 'Rumo ao Diamante!', 'outro dispositivo logado vê o mesmo status');
  a.close && a.close();
  const c = client(s.port);
  await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:ana' });
  const sc = await c.next('acct_state');
  check(sc.profile.status === 'Rumo ao Diamante!', 'sair e entrar de novo: status mantido');
  await wait(1600);
  c.send({ type: 'acct_set_status', status: '' });
  r = await c.next('acct_status_saved');
  check(r.status === '', 'apagar o status volta ao padrão');
  const g = client(s.port);
  await g.open();
  g.send({ type: 'acct_set_status', status: 'sem conta' });
  const saved = await g.next('acct_status_saved', 1200).then(() => true, () => false);
  check(!saved, 'sem conta/perfil: não salva');
  s.stop && s.stop();
  summary('profile_status');
  process.exit(process.exitCode || 0);
})();
