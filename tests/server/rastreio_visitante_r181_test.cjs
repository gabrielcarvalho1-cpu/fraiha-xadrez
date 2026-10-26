'use strict';
// R181 · RASTREAMENTO SEM LOGIN (POST /t): visitante anônimo desde o carregamento, telas ▸ e cliques ★, carregamento,
// login escolhido, saída; só nomes conhecidos (texto digitado é descartado); limites; ligação com o convidado/conta;
// funil por dia (anúncio / esconder apelidos de teste); Meta Conversions API (consentimento, dedup, token fora do log).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { AdminService } = require('../../online_v021/admin/service');
const { GRACE_MS } = require('../../online_v021/admin/sessions');
const { knownName, parseUA, MAX_BODY } = require('../../online_v021/admin/visit_http');
const { MetaCapi } = require('../../online_v021/admin/meta_capi');

const A = '11111111-1111-4111-a111-111111111111';
const BOSS = '44444444-4444-4444-a444-444444444444';
const flush = async () => { for (let i = 0; i < 50; i++) await Promise.resolve(); };
const hex = c => c.repeat(32).slice(0, 32);
const UA_IG = 'Mozilla/5.0 (Linux; Android 10; SM-A105M) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/129.0 Mobile Safari/537.36 Instagram 352.0.0.0 Android';

async function fixture(t, env = {}) {
  let clock = Date.parse('2026-10-24T15:00:00Z');
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1', ...env }, send: () => {}, now: () => clock, trackTimers: false });
  backend.auth = { verify: async tok => { const m = /^tok-(.+)$/.exec(tok); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  backend.attachRanked(new Ranked({ send: backend.send })); backend.attachCasual(new Ranked({ send: backend.send, kind: 'casual' }));
  backend.ranked.stop(); backend.casual.stop(); clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  await backend.store.createProfile(BOSS, 'Gabriel', 'warrior');
  await backend.store.createProfile(A, 'AliceTest', 'warrior');
  const admin = new AdminService({ backend, env: { FRAIHA_ADMIN_USERS: `${BOSS}=viewer`, FRAIHA_ENV: 'dev' }, autostart: false });
  const server = http.createServer((req, res) => (req.url === '/t' ? backend.visitHttp.handle(req, res, '10.0.0.1') : admin.handle(req, res)));
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const socks = [];
  t.after(() => { server.close(); for (const s of socks) backend.onClose(s); backend.party.stop(); backend.track.stop(); });
  const port = server.address().port;
  const get = async p => { const r = await fetch(`http://127.0.0.1:${port}${p}`, { headers: { Authorization: 'Bearer tok-' + BOSS } }); return { status: r.status, body: await r.json() }; };
  const post = (body, headers = {}) => fetch(`http://127.0.0.1:${port}/t`, { method: 'POST', headers: { 'content-type': 'text/plain', 'user-agent': UA_IG, ...headers }, body: typeof body === 'string' ? body : JSON.stringify(body) });
  const sock = () => { const s = { readyState: 1 }; socks.push(s); return s; };
  return { backend, get, post, sock, port, tick: ms => { clock += ms; }, now: () => clock };
}
const ingest = (h, body, ua = UA_IG, ip = '10.0.0.9') => h.backend.visitHttp.ingest(JSON.stringify(body), { ip, ua });

test('visitante anônimo: abre, carrega, telas ▸ e cliques ★, aparelho e anúncio — sem login', async t => {
  const h = await fixture(t);
  const sid = hex('a1'), vid = hex('b2');
  assert.ok(ingest(h, { sid, vid, st: 300, u: { s: 'instagram', c: 'teste_23_10', fb: true }, d: { w: 412, h: 915, lang: 'pt-BR', v: '0.38' },
    e: [{ k: 'load', n: 'start', t: 0 }, { k: 'load', n: 'done', t: 280, v: 6.4 }] }));
  h.tick(5e3);
  ingest(h, { sid, vid, st: 5300, e: [{ k: 'screen', n: 'Entrada / Login', t: 400 }, { k: 'click', n: 'Jogar como convidado', id: 'GuestButton', s: 'Entrada / Login', t: 5000 }] });
  const l = (await h.get('/admin/api/sessions')).body;
  const it = l.items.find(i => i.kind === 'visitor');
  assert.ok(it, 'visitante aparece em Visitas');
  assert.equal(it.utm.ad, true); assert.equal(it.utm.source, 'instagram');
  assert.equal(it.device.device, 'Android'); assert.equal(it.device.inapp, 'Instagram'); assert.equal(it.device.os, 'Android 10');
  assert.ok(/Instagram \(navegador do app\)/.test(it.device.browser));
  const d = (await h.get('/admin/api/sessions/' + it.sid)).body;
  const labels = d.events.map(e => e.k + ':' + e.l);
  assert.ok(labels.some(x => x.startsWith('sys:Abriu o jogo (veio do ANÚNCIO: instagram · teste_23_10)')), JSON.stringify(labels));
  assert.ok(labels.includes('sys:Começou a carregar o jogo'));
  assert.ok(labels.includes('sys:Carregou 100% (6,4 s)'));
  assert.ok(labels.includes('screen:Entrada / Login'));
  assert.ok(labels.includes('click:Jogar como convidado — Entrada / Login'));
  assert.equal(d.flags.loaded, true);
});

test('privacidade: texto digitado / nome desconhecido / campos fora do formato são descartados', async t => {
  const h = await fixture(t);
  assert.equal(knownName('fulano@gmail.com'), '');
  assert.equal(knownName('minhasenha123'), '');
  assert.equal(knownName('Oi tudo bem quer jogar'), '');
  assert.equal(knownName('Configurações'), 'Configurações');
  assert.equal(knownName('Partida Ranqueada · Resultado da partida'), 'Partida Ranqueada · Resultado da partida');
  assert.equal(knownName('Partida Ranqueada · fulano@x.com'), '');
  const sid = hex('c3'), vid = hex('d4');
  ingest(h, { sid, vid, st: 10, e: [
    { k: 'screen', n: 'fulano@gmail.com', t: 1 }, { k: 'click', n: 'senha: 12345678', id: 'x', t: 2 }, { k: 'chat', n: 'oi', t: 3 },
    { k: 'login', n: 'google', r: 'error', c: 'bad_oauth_state OAuth state not found or expired', t: 4 },
    { k: 'login', n: 'email', r: 'ok', t: 5, c: 'x' }, { k: 'screen', n: 'Configurações', t: 6, extra: 'ignorado' }] });
  const s = h.backend.track.bySid.get([...h.backend.track.visits.keys()][0]);
  const ls = s.events.map(e => e.l);
  assert.ok(!ls.some(l => /fulano|senha|oi$|12345678/.test(l)), JSON.stringify(ls));
  assert.ok(ls.includes('Login: Google — ERRO (bad_oauth_state OAuth state not found or expired)'));
  assert.ok(ls.includes('Configurações'));
  assert.equal(ingest(h, { sid: 'xyz', vid, e: [] }), false, 'sid inválido');
  assert.equal(ingest(h, { sid, vid: 'NAO-HEX', e: [] }), false, 'vid inválido');
  assert.equal(h.backend.visitHttp.ingest('não é json', {}), false);
  // até 40 eventos por envio
  const sid2 = hex('e5');
  ingest(h, { sid: sid2, vid: hex('f6'), st: 500, e: Array.from({ length: 80 }, (_, i) => ({ k: 'click', n: i % 2 ? 'Configurações' : 'Voltar', t: i })) });
  const s2 = h.backend.track.bySid.get(`${sid2.slice(0, 8)}-${sid2.slice(8, 12)}-${sid2.slice(12, 16)}-${sid2.slice(16, 20)}-${sid2.slice(20)}`);
  assert.ok(s2.events.filter(e => e.k === 'click').length <= 40);
});

test('limites: corpo grande, muitos envios por visitante e muitos visitantes novos por IP são descartados', async t => {
  const h = await fixture(t);
  const big = await h.post('x'.repeat(MAX_BODY + 10), { origin: 'https://jogar.fraihaxadrez.com' });
  assert.equal(big.status, 204);
  assert.equal(h.backend.track.visits.size, 0);
  const vid = hex('77');
  let ok = 0; for (let i = 0; i < 70; i++) if (ingest(h, { sid: hex('78'), vid, st: i, e: [{ k: 'hb', t: i }] })) ok++;
  assert.equal(ok, 60, 'no máximo 60 envios por minuto por visitante');
  let made = 0; for (let i = 0; i < 40; i++) { const x = (i + 16).toString(16).padStart(2, '0'); if (ingest(h, { sid: hex(x + 'a'), vid: hex(x + 'b'), e: [] }, UA_IG, '10.9.9.9')) made++; }
  assert.equal(made, 30, 'no máximo 30 visitantes novos por IP por hora');
  // CORS: só os endereços do jogo
  const bad = await h.post({ sid: hex('11'), vid: hex('12'), e: [] }, { origin: 'https://site-estranho.com' });
  assert.equal(bad.status, 403);
  const pre = await fetch(`http://127.0.0.1:${h.port}/t`, { method: 'OPTIONS', headers: { origin: 'https://jogar.fraihaxadrez.com' } });
  assert.equal(pre.status, 204); assert.equal(pre.headers.get('access-control-allow-origin'), 'https://jogar.fraihaxadrez.com');
  const good = await h.post({ sid: hex('21'), vid: hex('22'), e: [{ k: 'load', n: 'start', t: 0 }] }, { origin: 'https://jogar.fraihaxadrez.com' });
  assert.equal(good.status, 204);
  await new Promise(r => setTimeout(r, 30));
  assert.ok(h.backend.track.hasVisit(hex('21')));
});

test('convidado: a visita vira a sessão do convidado no clique (mesma linha do tempo, telas e cliques seguem)', async t => {
  const h = await fixture(t);
  const sid = hex('31'), vid = hex('32');
  ingest(h, { sid, vid, st: 100, e: [{ k: 'screen', n: 'Entrada / Login', t: 50 }] });
  h.tick(4e3);
  ingest(h, { sid, vid, st: 4100, e: [{ k: 'click', n: 'Jogar como convidado', t: 4000 }] });
  const ws = h.sock();
  await h.backend.handle(ws, { type: 'ui_link', sid });
  await h.backend.handle(ws, { type: 'guest_auth' }); await flush();
  h.tick(2e3);
  ingest(h, { sid, vid, st: 6100, e: [{ k: 'screen', n: 'Início', t: 6000 }, { k: 'match', n: 'start', m: 'bot', b: 'madeira', t: 6050 }] });
  const l = (await h.get('/admin/api/sessions')).body;
  assert.equal(l.items.length, 1, 'uma sessão só (visitante + convidado)');
  const it = l.items[0];
  assert.ok(it.kind.startsWith('guest')); assert.equal(it.flags.passed, true); assert.equal(it.flags.played, true);
  const d = (await h.get('/admin/api/sessions/' + it.sid)).body;
  const ls = d.events.map(e => e.l);
  assert.ok(ls.includes('Entrada / Login') && ls.includes('Início'));
  assert.ok(ls.some(l => /^Entrou como (NOVO )?convidado/.test(l)));
  assert.ok(ls.includes('Começou partida: Contra o computador · BOT MADEIRA'));
  assert.deepEqual(d.time_by_screen.map(x => x.screen).sort(), ['Entrada / Login', 'Início']);
});

test('saída: beacon de saída + sem voltar = sessão fechada com última tela e último botão; sem sinal por 4 min também', async t => {
  const h = await fixture(t);
  const sid = hex('41'), vid = hex('42');
  ingest(h, { sid, vid, st: 10, e: [{ k: 'screen', n: 'Entrada / Login', t: 5 }] });
  h.tick(3e3);
  ingest(h, { sid, vid, st: 3010, e: [{ k: 'click', n: 'Criar conta', t: 2900 }, { k: 'exit', s: 'Entrada / Login', b: 'Criar conta', t: 3000 }] });
  h.tick(GRACE_MS + 1000); h.backend.track.sweepVisits();
  const d = (await h.get('/admin/api/sessions')).body.items[0];
  assert.equal(d.state, 'ended');
  const det = (await h.get('/admin/api/sessions/' + d.sid)).body;
  assert.ok(det.events.some(e => e.l === 'Saiu / fechou o jogo · última tela: Entrada / Login · último botão: Criar conta'));
  ingest(h, { sid: hex('43'), vid: hex('44'), e: [{ k: 'screen', n: 'Entrada / Login', t: 0 }] });
  h.tick(5 * 60e3); h.backend.track.sweepVisits();
  assert.equal(h.backend.track.visits.size, 0);
});

test('funil por dia: abriu → carregou → passou da entrada → jogou → voltou outro dia; anúncio; esconder testes', async t => {
  const h = await fixture(t);
  // dia 1: 3 navegadores (2 do anúncio); um deles volta no dia 2
  ingest(h, { sid: hex('51'), vid: hex('61'), u: { s: 'instagram' }, e: [{ k: 'load', n: 'done', t: 1, v: 3 }, { k: 'login', n: 'guest', r: 'ok', t: 2 }, { k: 'match', n: 'start', m: 'bot', t: 3 }] });
  ingest(h, { sid: hex('52'), vid: hex('62'), u: { s: 'instagram' }, e: [{ k: 'load', n: 'done', t: 1, v: 3 }] });
  ingest(h, { sid: hex('53'), vid: hex('63'), e: [{ k: 'load', n: 'start', t: 0 }] });
  h.tick(26 * 3600e3);
  ingest(h, { sid: hex('54'), vid: hex('61'), e: [{ k: 'load', n: 'done', t: 1, v: 2 }] });
  // apelido de teste (SextoSentro) num navegador: some com "esconder testes"
  ingest(h, { sid: hex('55'), vid: hex('65'), e: [{ k: 'load', n: 'done', t: 1 }] });
  const ws = h.sock();
  await h.backend.store.createProfile('55555555-5555-4555-a555-555555555555', 'SextoSentro', 'warrior');
  await h.backend.handle(ws, { type: 'ui_link', sid: hex('55') });
  await h.backend.handle(ws, { type: 'acct_auth', access_token: 'tok-55555555-5555-4555-a555-555555555555' }); await flush();
  const f = (await h.get('/admin/api/funnel?days=7')).body;
  const d1 = f.days.find(d => d.day === '2026-10-24'), d2 = f.days.find(d => d.day === '2026-10-25');
  assert.deepEqual(d1, { day: '2026-10-24', opened: 3, loaded: 2, passed: 1, played: 1, returned: 1 });
  assert.deepEqual(d2, { day: '2026-10-25', opened: 1, loaded: 1, passed: 0, played: 0, returned: 0 }, JSON.stringify(f.days));
  const fa = (await h.get('/admin/api/funnel?days=7&ads=1')).body;
  assert.equal(fa.days.find(d => d.day === '2026-10-24').opened, 2, 'só anúncio');
  const fall = (await h.get('/admin/api/funnel?days=7&hide_test=0')).body;
  assert.equal(fall.days.find(d => d.day === '2026-10-25').opened, 2, 'sem esconder: o navegador de teste conta');
  const la = (await h.get('/admin/api/sessions?ads=1')).body;
  assert.ok(la.items.every(i => i.utm.ad));
  const lt = (await h.get('/admin/api/sessions?hide_test=1')).body;
  assert.ok(!lt.items.some(i => i.nickname === 'SextoSentro'));
});

test('aparelho pelo navegador: Android antigo, iPhone, Instagram/Facebook, PC', () => {
  assert.deepEqual(parseUA('Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36'), { device: 'Android', os: 'Android 10', mobile: true, browser: 'Chrome 120' });
  const ip = parseUA('Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 352.0');
  assert.equal(ip.device, 'iPhone'); assert.equal(ip.inapp, 'Instagram'); assert.equal(ip.os, 'iOS 17.5');
  assert.equal(parseUA('Mozilla/5.0 (Linux; Android 12) Chrome/128 Mobile [FB_IAB/FB4A;FBAV/470.0;]').inapp, 'Facebook');
  assert.equal(parseUA('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/129.0 Safari/537.36').device, 'PC');
});

test('Meta Conversions API: desligada sem token; só com consentimento; dedup por event_id; token fora do log', async () => {
  const calls = [], logs = [];
  const fake = async (url, opt) => { calls.push({ url, body: JSON.parse(opt.body) }); return { ok: true, status: 200 }; };
  const off = new MetaCapi({ env: {}, fetchImpl: fake });
  assert.equal(await off.send({ name: 'JogoCarregado', id: 'a'.repeat(20), consent: true }), false);
  const on = new MetaCapi({ env: { META_CAPI_TOKEN: 'SEGREDO123', META_CAPI_TEST_CODE: 'TEST999' }, fetchImpl: fake, log: { error: (...a) => logs.push(a.join(' ')) } });
  assert.equal(await on.send({ name: 'JogoCarregado', id: 'b'.repeat(20), consent: false, ip: '1.2.3.4', ua: 'x' }), false, 'sem consentimento: não manda');
  assert.equal(await on.send({ name: 'PrimeiraPartida', id: 'c'.repeat(20), consent: true, ip: '1.2.3.4', ua: 'UA', params: { modo: 'bot' }, fbp: 'fb.1.1700000000000.123' }), true);
  assert.equal(await on.send({ name: 'PrimeiraPartida', id: 'c'.repeat(20), consent: true, ip: '1.2.3.4', ua: 'UA' }), false, 'mesmo event_id: uma vez só');
  assert.equal(await on.send({ name: 'Purchase', id: 'd'.repeat(20), consent: true }), false, 'evento fora da lista');
  assert.equal(calls.length, 1);
  const ev = calls[0].body.data[0];
  assert.equal(ev.event_name, 'PrimeiraPartida'); assert.equal(ev.event_id, 'c'.repeat(20)); assert.equal(ev.action_source, 'website');
  assert.deepEqual(ev.custom_data, { modo: 'bot' }); assert.equal(ev.user_data.fbp, 'fb.1.1700000000000.123');
  assert.equal(calls[0].body.test_event_code, 'TEST999');
  assert.ok(!JSON.stringify(calls[0].body).includes('SEGREDO123'), 'token só na URL, nunca no corpo');
  const bad = new MetaCapi({ env: { META_CAPI_TOKEN: 'SEGREDO123' }, fetchImpl: async () => ({ ok: false, status: 400 }), log: { error: (...a) => logs.push(a.join(' ')) } });
  await bad.send({ name: 'JogoCarregado', id: 'e'.repeat(20), consent: true, ip: '1', ua: 'u' });
  assert.ok(logs.length && !logs.some(l => l.includes('SEGREDO123')), 'token nunca no log');
});

test('R182 · app Android: sem Origin, com x-fraiha-app=android → aceito, aparelho "APP Android" (versão do Android)', async t => {
  const h = await fixture(t);
  const site = await h.post({ sid: hex('33'), vid: hex('34'), e: [] }, { origin: 'https://site-estranho.com', 'x-fraiha-app': 'android' });
  assert.equal(site.status, 403, 'navegador de outro site não vira "app" só pelo cabeçalho');
  const ok = await h.post({ sid: hex('35'), vid: hex('36'), st: 100, d: { w: 1080, h: 2400, lang: 'pt', app: 'android', os: '14', v: '' },
    e: [{ k: 'load', n: 'start', t: 0 }, { k: 'screen', n: 'Entrada / Login', t: 50 }, { k: 'click', n: 'Jogar como convidado', id: 'GuestButton', s: 'Entrada / Login', t: 90 }] },
    { 'user-agent': 'GodotEngine/4.5.1.stable (Android)', 'x-fraiha-app': 'android' });
  assert.equal(ok.status, 204);
  await flush();
  const l = (await h.get('/admin/api/sessions')).body;
  const it = l.items.find(i => i.kind === 'visitor');
  assert.ok(it, 'visita do app aparece');
  assert.equal(it.device.device, 'Android'); assert.equal(it.device.os, 'Android 14'); assert.equal(it.device.browser, 'APP Android');
  const d = (await h.get('/admin/api/sessions/' + it.sid)).body;
  const labels = d.events.map(e => e.k + ':' + e.l);
  assert.ok(labels.includes('screen:Entrada / Login'), JSON.stringify(labels));
  assert.ok(labels.includes('click:Jogar como convidado — Entrada / Login'), JSON.stringify(labels));
});

test('R184 · executável do PC: x-fraiha-app=windows → aparelho "APP PC (Windows)"', async t => {
  const h = await fixture(t);
  const ok = await h.post({ sid: hex('45'), vid: hex('46'), st: 100, d: { w: 1920, h: 1080, lang: 'pt', app: 'windows', os: '10' },
    e: [{ k: 'load', n: 'start', t: 0 }, { k: 'screen', n: 'Entrada / Login', t: 50 }] }, { 'user-agent': 'GodotEngine/4.5.1.stable (Windows)', 'x-fraiha-app': 'windows' });
  assert.equal(ok.status, 204);
  await flush();
  const it = (await h.get('/admin/api/sessions')).body.items.find(i => i.kind === 'visitor');
  assert.equal(it.device.device, 'PC'); assert.equal(it.device.browser, 'APP PC (Windows)'); assert.equal(it.device.os, 'Windows');
});

test('R193 · app de iPhone: x-fraiha-app=ios → aparelho "APP iPhone" (versão do iOS); de outro site não vale', async t => {
  const h = await fixture(t);
  const site = await h.post({ sid: hex('53'), vid: hex('54'), e: [] }, { origin: 'https://site-estranho.com', 'x-fraiha-app': 'ios' });
  assert.equal(site.status, 403);
  const ok = await h.post({ sid: hex('55'), vid: hex('56'), st: 100, d: { w: 1179, h: 2556, lang: 'pt', app: 'ios', os: '18.5' },
    e: [{ k: 'load', n: 'start', t: 0 }, { k: 'screen', n: 'Entrada / Login', t: 50 }] }, { 'user-agent': 'GodotEngine/4.5.1.stable (iOS)', 'x-fraiha-app': 'ios' });
  assert.equal(ok.status, 204);
  await flush();
  const it = (await h.get('/admin/api/sessions')).body.items.find(i => i.kind === 'visitor');
  assert.equal(it.device.device, 'iPhone'); assert.equal(it.device.browser, 'APP iPhone'); assert.equal(it.device.os, 'iOS 18.5');
});
