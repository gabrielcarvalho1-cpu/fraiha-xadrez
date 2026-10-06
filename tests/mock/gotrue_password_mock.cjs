'use strict';
// Mock do Supabase Auth (GoTrue) para o teste "DEFINIR SENHA" (NÃO é produção, NÃO toca o Supabase real).
// Reproduz o comportamento oficial relevante:
//  - usuário criado pelo Google NÃO tem senha; login por senha falha (invalid_credentials);
//  - PUT /auth/v1/user {password} com o token da PRÓPRIA sessão grava a senha NO MESMO usuário (mesmo id);
//    nenhum usuário/identidade novo é criado; senha < 8 → 422 weak_password; igual à atual → 422 same_password;
//  - depois disso, grant_type=password com e-mail + nova senha devolve o MESMO id; Google continua igual.
// Também sobe um WebSocket "servidor FRAIHA" que só REGISTRA o que o cliente envia (prova que a senha não vai pra lá).
// Endpoints de inspeção: /__google (sessão Google nova), /__state (usuários sem senha, contagem), /__bodies, /__fail.
const http = require('http'), crypto = require('crypto');
const { WebSocketServer } = require('ws');
const PORT = Number(process.argv[2] || 8131), WS_PORT = Number(process.argv[3] || 8132);
const users = new Map();          // id -> {id, email, provider, password|null}
const tokens = new Map(), refresh = new Map();
const bodies = [];                // {method, path, body} — para conferir ONDE a senha aparece
let failNext = '';
const GOOGLE_ID = '9249a3f2-bc90-45ea-b95b-a5b376421e0f';   // simula a conta real (só o id; nada real é tocado)
users.set(GOOGLE_ID, { id: GOOGLE_ID, email: 'dono.google@teste.local', provider: 'google', password: null });
users.set('11111111-2222-4333-8444-555555555555', { id: '11111111-2222-4333-8444-555555555555', email: 'outro@teste.local', provider: 'email', password: 'SenhaDoOutro1' });
const byEmail = e => [...users.values()].find(u => u.email === e);
const pub = u => ({ id: u.id, email: u.email, aud: 'authenticated', app_metadata: { provider: u.provider, providers: [u.provider] } });
function session(u) {
  const at = 'at_' + crypto.randomBytes(16).toString('hex'), rt = 'rt_' + crypto.randomBytes(8).toString('hex');
  tokens.set(at, u.id); refresh.set(rt, u.id);
  return { access_token: at, refresh_token: rt, expires_in: 3600, token_type: 'bearer', user: pub(u) };
}
const readBody = req => new Promise(r => { let d = ''; req.on('data', c => d += c); req.on('end', () => r(d)); });
http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const json = (code, o) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
  const raw = req.method === 'GET' ? '' : await readBody(req);
  let b = {}; try { b = JSON.parse(raw || '{}'); } catch { b = {}; }
  if (!url.pathname.startsWith('/__')) bodies.push({ method: req.method, path: url.pathname + url.search, body: raw });
  if (url.pathname === '/__google') { const u = users.get(GOOGLE_ID); const s = session(u); delete s.user; return json(200, s); }   // como o retorno #access_token do Google
  if (url.pathname === '/__state') return json(200, { count: users.size, users: [...users.values()].map(u => ({ id: u.id, email: u.email, provider: u.provider, has_password: !!u.password })) });
  if (url.pathname === '/__bodies') return json(200, bodies);
  if (url.pathname === '/__fail') { failNext = url.searchParams.get('mode') || ''; return json(200, { ok: true }); }
  if (url.pathname === '/__expire') { tokens.clear(); return json(200, { ok: true }); }
  if (req.headers.apikey !== 'sb_publishable_test') return json(401, { message: 'no apikey' });
  const bearer = String(req.headers.authorization || '').replace(/^Bearer /, '');
  if (url.pathname === '/auth/v1/token' && url.searchParams.get('grant_type') === 'password') {
    const u = byEmail(String(b.email || ''));
    if (!u || !u.password || u.password !== b.password) return json(400, { error_code: 'invalid_credentials', msg: 'Invalid login credentials' });
    return json(200, session(u));
  }
  if (url.pathname === '/auth/v1/user') {
    const id = tokens.get(bearer); const u = id && users.get(id);
    if (!u) return json(401, { error_code: 'bad_jwt', msg: 'invalid JWT' });
    if (req.method === 'PUT') {
      if (failNext) { const m = failNext; failNext = ''; return json(422, { error_code: m, msg: m }); }
      if (typeof b.password === 'string') {
        if (b.password.length < 8) return json(422, { error_code: 'weak_password', msg: 'Password should be at least 8 characters.' });
        if (u.password && u.password === b.password) return json(422, { error_code: 'same_password', msg: 'New password should be different from the old password.' });
        u.password = b.password;   // MESMO registro: id, e-mail e provedor Google intactos
      }
    }
    return json(200, pub(u));
  }
  if (url.pathname === '/auth/v1/logout') { tokens.delete(bearer); res.writeHead(204); return res.end(); }
  json(404, { msg: 'not found' });
}).listen(PORT, '127.0.0.1', () => console.log('gotrue password mock on ' + PORT));

// "Servidor FRAIHA" que só registra mensagens recebidas.
const received = [];
const wss = new WebSocketServer({ port: WS_PORT, host: '127.0.0.1' });
wss.on('connection', ws => ws.on('message', m => received.push(String(m))));
http.createServer((req, res) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(received)); }).listen(WS_PORT + 1, '127.0.0.1');
