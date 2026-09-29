'use strict';
// Mock mínimo do Supabase Auth para testes locais do cliente (NÃO é produção).
const http = require('http'), crypto = require('crypto');
const users = new Map(), tokens = new Map(), refresh = new Map(); const log = [];
const PORT = Number(process.env.MOCK_PORT || 8130);
function session(u) { const at = 'at_' + crypto.randomBytes(16).toString('hex'), rt = 'rt_' + crypto.randomBytes(8).toString('hex'); tokens.set(at, u); refresh.set(rt, u);
  return { access_token: at, refresh_token: rt, expires_in: 3600, token_type: 'bearer', user: { id: u.id, email: u.email, app_metadata: { provider: u.provider } } }; }
function body(req) { return new Promise(r => { let d = ''; req.on('data', c => d += c); req.on('end', () => { try { r(JSON.parse(d || '{}')); } catch { r({}); } }); }); }
http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*'); res.setHeader('Access-Control-Allow-Headers', '*'); res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,OPTIONS');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
  const url = new URL(req.url, 'http://x'); const json = (code, o) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
  const b = req.method === 'GET' ? {} : await body(req); log.push(req.method + ' ' + url.pathname + url.search);
  if (url.pathname === '/__log') return json(200, log);
  if (req.headers.apikey !== 'sb_publishable_test' && url.pathname !== '/auth/v1/authorize') return json(401, { message: 'no apikey' });
  const bearer = (req.headers.authorization || '').replace('Bearer ', '');
  if (url.pathname === '/auth/v1/signup') {
    if (users.has(b.email)) return json(422, { error_code: 'user_already_exists', msg: 'User already registered' });
    if (String(b.password || '').length < 8) return json(422, { error_code: 'weak_password', msg: 'Password should be at least 8' });
    const u = { id: crypto.randomUUID(), email: b.email, password: b.password, provider: 'email' }; users.set(b.email, u); return json(200, session(u));
  }
  if (url.pathname === '/auth/v1/token') {
    if (url.searchParams.get('grant_type') === 'password') { const u = users.get(b.email); if (!u || u.password !== b.password) return json(400, { error_code: 'invalid_credentials', msg: 'Invalid login credentials' }); return json(200, session(u)); }
    const u = refresh.get(b.refresh_token); if (!u) return json(400, { error_code: 'refresh_token_not_found' }); refresh.delete(b.refresh_token); return json(200, session(u));
  }
  if (url.pathname === '/auth/v1/user') { const u = tokens.get(bearer); if (!u) return json(401, { msg: 'invalid JWT' }); if (req.method === 'PUT' && b.password) u.password = b.password; return json(200, { id: u.id, email: u.email, app_metadata: { provider: u.provider } }); }
  if (url.pathname === '/auth/v1/logout') { tokens.delete(bearer); res.writeHead(204); return res.end(); }
  if (url.pathname === '/auth/v1/recover') return json(200, {});
  if (url.pathname === '/auth/v1/authorize') {
    const email = 'google.user@gmail.com'; let u = users.get(email); if (!u) { u = { id: crypto.randomUUID(), email, provider: 'google' }; users.set(email, u); }
    const s = session(u); res.writeHead(302, { Location: url.searchParams.get('redirect_to') + '#access_token=' + s.access_token + '&refresh_token=' + s.refresh_token + '&expires_in=3600&token_type=bearer' }); return res.end();
  }
  json(404, { msg: 'not found' });
}).listen(PORT, '127.0.0.1', () => console.log('gotrue mock on ' + PORT));
