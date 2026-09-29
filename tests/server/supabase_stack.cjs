'use strict';
// Teste OPCIONAL contra Postgres + PostgREST reais (simula o Supabase localmente; nada de produção).
// Requer: Postgres 16 local (/tmp/pgtest.sh aplica as migrations) e o binário PostgREST em /tmp/postgrest.
// Uso: node tests/server/supabase_stack.cjs tests/server/social_test.cjs
const http = require('http'), crypto = require('crypto'), { spawn, execSync } = require('child_process');
const path = require('path'), fs = require('fs');
const SECRET = crypto.randomBytes(32).toString('hex');
const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
const jwt = claims => { const h = b64({ alg: 'HS256', typ: 'JWT' }), p = b64(claims); return h + '.' + p + '.' + crypto.createHmac('sha256', SECRET).update(h + '.' + p).digest('base64url'); };
const PSQL = 'psql -h /tmp -p 55432 -U postgres -q -v ON_ERROR_STOP=1';
const uidOf = name => { const h = crypto.createHash('sha256').update('stack:' + name).digest('hex'); return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`; };
(async () => {
  execSync('bash /tmp/pgtest.sh', { stdio: 'inherit' });
  const cfg = '/tmp/postgrest.conf', restPort = 30000 + Math.floor(Math.random() * 5000);
  fs.writeFileSync(cfg, `db-uri = "postgres://postgres@/postgres?host=/tmp&port=55432"\ndb-schemas = "public"\ndb-anon-role = "anon"\njwt-secret = "${SECRET}"\nserver-port = ${restPort}\n`);
  const rest = spawn('/tmp/postgrest', [cfg], { stdio: 'ignore' });
  await new Promise(r => setTimeout(r, 1500));
  const seen = new Set();
  const front = http.createServer((req, res) => {
    if (req.url.startsWith('/auth/v1/user')) {
      const m = /dev:([A-Za-z0-9_.-]+)$/.exec(String(req.headers.authorization || ''));
      if (!m) { res.writeHead(401); return res.end('{}'); }
      const id = uidOf(m[1]);
      if (!seen.has(id)) { execSync(`${PSQL} -c "insert into auth.users(id) values ('${id}') on conflict do nothing"`); seen.add(id); }
      res.writeHead(200, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ id, email: m[1] + '@stack.local', app_metadata: { provider: 'email' } }));
    }
    if (!req.url.startsWith('/rest/v1/')) { res.writeHead(404); return res.end(); }
    const headers = { ...req.headers }; delete headers.host; delete headers.apikey;
    const up = http.request({ host: '127.0.0.1', port: restPort, path: req.url.slice(8), method: req.method, headers }, r2 => { res.writeHead(r2.statusCode, r2.headers); r2.pipe(res); });
    req.pipe(up);
  });
  await new Promise(r => front.listen(0, '127.0.0.1', r));
  const env = { SUPABASE_URL: 'http://127.0.0.1:' + front.address().port, SUPABASE_SECRET_KEY: jwt({ role: 'service_role' }), SUPABASE_ANON_KEY: 'anon' };
  const code = await new Promise(r => {
    const t = spawn(process.execPath, [path.resolve(process.argv[2])], { stdio: 'inherit', env: { ...process.env, SOCIAL_STACK_ENV: JSON.stringify(env), SOCIAL_TOKEN_PAD: 'stack-token-padding-' } });
    t.on('exit', r);
  });
  // RLS: com JWT de usuário comum, só lê as próprias linhas e não escreve.
  const out = execSync(`${PSQL} -At -c "select count(*) from public.friendships; select count(*) from public.blocks; select count(*) from public.friend_requests"`).toString().trim().split('\n');
  console.log('STACK linhas no banco (friendships, blocks, requests):', out.join(', '));
  rest.kill(); front.close();
  execSync("su postgres -c '/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgdata stop -m fast' >/dev/null");
  process.exit(code);
})().catch(e => { console.error(e); process.exit(1); });
