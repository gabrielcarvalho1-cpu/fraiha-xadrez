'use strict';
// H03 · resultado Ranked não se perde em falha transitória da gravação e o PL nunca é aplicado duas vezes.
// Parte 1: unidade (ranked/persist.js) com store em memória. Parte 2: servidor real com gravação instável.
const path = require('path');
const { spawn } = require('child_process');
const { client, check, summary } = require('./helpers.cjs');
const { persistRanked, permanent } = require('../../online_v021/ranked/persist');
const { MemoryStore } = require('../../online_v021/accounts/store');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const quiet = { error() {}, log() {} };
const noWait = async () => {};

async function seeded() {
  const st = new MemoryStore();
  const w = '11111111-1111-4111-8111-111111111111', b = '22222222-2222-4222-8222-222222222222';
  await st.createProfile(w, 'BrancasH03', 'warrior'); await st.createProfile(b, 'PretasH03', 'warrior');
  const ws = (await st.getRankedStats(w)).ranked_3min, bs = (await st.getRankedStats(b)).ranked_3min;
  const rec = { match_id: '33333333-3333-4333-8333-333333333333', mode: 'ranked_3min', white_user_id: w, black_user_id: b,
    started_at: new Date().toISOString(), finished_at: new Date().toISOString(), result: 'white', result_reason: 'resign',
    white_pl_before: ws.pl, black_pl_before: bs.pl, white_pl_change: 15, black_pl_change: 0, white_pl_after: ws.pl + 15, black_pl_after: bs.pl,
    white_league_before: ws.league, black_league_before: bs.league, white_league_after: ws.league, black_league_after: bs.league, moves: '' };
  return { st, w, b, rec };
}
const statsOf = async (st, uid) => (await st.getRankedStats(uid)).ranked_3min;

async function unit() {
  // a) duas falhas transitórias e depois grava: salvo, PL uma vez
  { const { st, w, rec } = await seeded(); const orig = st.recordRankedMatch.bind(st); let n = 0;
    st.recordRankedMatch = async r => { if (++n <= 2) throw new Error('fetch failed'); return orig(r); };
    const r = await persistRanked(st, rec, { delays: [1, 1, 1], log: quiet, wait: noWait });
    const s = await statsOf(st, w);
    check(r.saved && r.attempts === 3 && !r.already, 'unidade: 2 falhas transitórias → grava na 3ª tentativa');
    check(s.pl === 15 && s.matches === 1 && st.matches.length === 1, 'unidade: PL aplicado UMA vez (+15, 1 partida)'); }
  // b) gravou mas a resposta se perdeu: a nova tentativa vê a partida gravada e NÃO reaplica
  { const { st, w, rec } = await seeded(); const orig = st.recordRankedMatch.bind(st); let n = 0;
    st.recordRankedMatch = async r => { const out = await orig(r); if (++n === 1) throw new Error('HTTP 504'); return out; };
    const r = await persistRanked(st, rec, { delays: [1, 1, 1], log: quiet, wait: noWait });
    const s = await statsOf(st, w);
    check(r.saved && r.already && n === 1, 'unidade: commit feito + resposta perdida → reconhecido como gravado, sem nova chamada');
    check(s.pl === 15 && s.matches === 1 && st.matches.length === 1, 'unidade: resposta perdida NÃO duplica PL'); }
  // c) erro permanente: não repete
  { const { st, rec } = await seeded(); let n = 0;
    st.recordRankedMatch = async () => { n++; throw new Error('estado Ranked mudou durante a partida'); };
    const r = await persistRanked(st, rec, { delays: [1, 1, 1], log: quiet, wait: noWait });
    check(!r.saved && n === 1, 'unidade: erro permanente (estado mudou) → para sem repetir'); }
  // d) banco fora do ar o tempo todo: desiste, registra a partida inteira no log para reconciliação
  { const { st, rec } = await seeded(); let n = 0, logged = '';
    st.recordRankedMatch = async () => { n++; throw new Error('fetch failed'); };
    const r = await persistRanked(st, rec, { delays: [1, 1, 1], log: { error: (...a) => { logged += a.join(' ') + '\n'; } }, wait: noWait });
    check(!r.saved && n === 4, 'unidade: sempre fora do ar → 4 tentativas e desiste (saved=false)');
    check(logged.includes('RANKED_PERSIST_GAVE_UP') && logged.includes(rec.match_id) && logged.includes('"white_pl_after":15'), 'unidade: desistência registra a partida completa no log'); }
  // e) a consulta "já gravada?" também falha: continua tentando
  { const { st, w, rec } = await seeded(); const orig = st.recordRankedMatch.bind(st); let n = 0;
    st.hasRankedMatch = async () => { throw new Error('fetch failed'); };
    st.recordRankedMatch = async r => { if (++n <= 1) throw new Error('fetch failed'); return orig(r); };
    const r = await persistRanked(st, rec, { delays: [1, 1], log: quiet, wait: noWait });
    check(r.saved && (await statsOf(st, w)).matches === 1, 'unidade: consulta indisponível não impede a nova tentativa'); }
  // f) violação de chave (23505) = já gravada
  { const { st, rec } = await seeded();
    st.recordRankedMatch = async () => { const e = new Error('duplicate key'); e.code = '23505'; throw e; };
    st.hasRankedMatch = async () => false;
    const r = await persistRanked(st, rec, { delays: [1], log: quiet, wait: noWait });
    check(r.saved && r.already, 'unidade: 23505 (match_id já existe) = já gravada, sem reaplicar'); }
  // g) SupabaseStore.hasRankedMatch: só leitura de matches por match_id (service role), sem RPC nova
  { const { SupabaseStore } = require('../../online_v021/accounts/store'); const seen = [];
    const fake = async (url, opts) => { seen.push([url, opts.method || 'GET']); const found = url.includes('33333333-3333-4333-8333-333333333333');
      return { ok: true, status: 200, text: async () => JSON.stringify(found ? [{ match_id: '33333333-3333-4333-8333-333333333333' }] : []) }; };
    const sb = new SupabaseStore({ url: 'https://exemplo.supabase.co', serviceKey: 'sb_secret_teste', fetchImpl: fake });
    const yes = await sb.hasRankedMatch('33333333-3333-4333-8333-333333333333'), no = await sb.hasRankedMatch('44444444-4444-4444-8444-444444444444'), bad = await sb.hasRankedMatch('x;drop');
    check(yes === true && no === false && bad === false, 'unidade: SupabaseStore.hasRankedMatch acha/não acha e recusa id inválido');
    check(seen.length === 2 && seen.every(([u, m]) => m === 'GET' && u.startsWith('https://exemplo.supabase.co/rest/v1/matches?match_id=eq.') && u.endsWith('&select=match_id')), 'unidade: consulta GET /rest/v1/matches?match_id=eq.…&select=match_id'); }
  check(permanent(new Error('estado Ranked mudou durante a partida')) && !permanent(new Error('fetch failed')) && !permanent(Object.assign(new Error('x'), { code: '503' })), 'unidade: classificação permanente × transitória');
}

async function startFlaky(env) {
  const port = 20000 + Math.floor(Math.random() * 20000);
  const proc = spawn(process.execPath, [path.join(__dirname, 'flaky_persist_server.cjs')], { env: { ...process.env, PORT: String(port), FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_MM_EXPAND_MS: '60000', ...env }, stdio: ['ignore', 'pipe', 'pipe'] });
  let log = ''; proc.stdout.on('data', d => log += d); proc.stderr.on('data', d => log += d);
  for (let i = 0; i < 100 && !log.includes('listening'); i++) await sleep(50);
  return { port, log: () => log, stop: () => proc.kill() };
}
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  const st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); await c.next('acct_state'); }
  return c;
}
async function playAndResign(port, n1, n2) {
  const a = await login(port, n1), b = await login(port, n2);
  a.send({ type: 'ranked_queue', mode: 'ranked_3min' }); await a.next('ranked_queued');
  b.send({ type: 'ranked_queue', mode: 'ranked_3min' }); await b.next('ranked_queued');
  const fa = await a.next('ranked_found', 4000); await b.next('ranked_found', 4000);
  await a.next(m => m.type === 'ranked_state' && m.status === 'playing', 4000);
  a.send({ type: 'ranked_resign', match_id: fa.match_id });
  return { a, b, id: fa.match_id };
}
async function ranked3(c) { c.send({ type: 'acct_refresh' }); const st = await c.next('acct_state'); return st.ranked.ranked_3min; }

async function server() {
  // transitória: 2 falhas antes de gravar → resultado chega salvo e o PL entra uma vez; durante a gravação não reentra na fila
  { const s = await startFlaky({ FLAKY_MODE: 'transient', FLAKY_N: '2', FRAIHA_RANKED_PERSIST_RETRY_MS: '400,400,400' });
    const { a, b } = await playAndResign(s.port, 'transA', 'transB');
    await sleep(150);
    b.send({ type: 'ranked_queue', mode: 'ranked_3min' });
    const pend = await b.next(m => m.type === 'ranked_error' || m.type === 'ranked_queued', 3000);
    check(pend.type === 'ranked_error' && pend.code === 'result_pending', 'servidor: durante as novas tentativas o vencedor NÃO entra em outra fila (result_pending)');
    const ra = await a.next('ranked_result', 5000), rb = await b.next('ranked_result', 5000);
    check(ra.saved === true && rb.saved === true && rb.pl_change === 15, 'servidor: 2 falhas transitórias → resultado chega com saved=true');
    const sb = await ranked3(b), sa = await ranked3(a);
    check(sb.pl === 15 && sb.matches === 1 && sa.matches === 1, 'servidor: PL +15 aplicado UMA vez (1 partida para cada)');
    check((s.log().match(/FLAKY call/g) || []).length === 3, 'servidor: exatamente 3 chamadas de gravação');
    b.send({ type: 'ranked_queue', mode: 'ranked_3min' }); check((await b.next(m => m.type === 'ranked_queued' || m.type === 'ranked_error', 3000)).type === 'ranked_queued', 'servidor: depois de gravado, volta a entrar na fila normalmente');
    a.close(); b.close(); s.stop(); }
  // resposta perdida após o commit → sem PL duplicado
  { const s = await startFlaky({ FLAKY_MODE: 'lost', FLAKY_N: '1', FRAIHA_RANKED_PERSIST_RETRY_MS: '100,100,100' });
    const { a, b } = await playAndResign(s.port, 'lostA', 'lostB');
    const rb = await b.next('ranked_result', 5000);
    const sb = await ranked3(b);
    check(rb.saved === true && sb.pl === 15 && sb.matches === 1, 'servidor: gravou e a resposta se perdeu → saved=true e PL NÃO duplicado (15, 1 partida)');
    check((s.log().match(/FLAKY call/g) || []).length === 1, 'servidor: nenhuma segunda gravação depois do commit');
    a.close(); b.close(); s.stop(); }
  // banco fora do ar: desiste com saved=false e registra a partida para reconciliação
  { const s = await startFlaky({ FLAKY_MODE: 'down', FRAIHA_RANKED_PERSIST_RETRY_MS: '100,100' });
    const { a, b, id } = await playAndResign(s.port, 'downA', 'downB');
    const rb = await b.next('ranked_result', 5000);
    check(rb.saved === false, 'servidor: banco fora do ar o tempo todo → saved=false (cliente avisa)');
    await sleep(100);
    check(s.log().includes('RANKED_PERSIST_GAVE_UP') && s.log().includes(id), 'servidor: partida completa registrada no log (RANKED_PERSIST_GAVE_UP)');
    a.close(); b.close(); s.stop(); }
}

(async () => {
  await unit();
  await server();
  summary('ranked_persist_retry');
})().catch(e => { console.error(e); process.exit(1); });
