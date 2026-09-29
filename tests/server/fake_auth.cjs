'use strict';
// Supabase Auth falso (só /auth/v1/token e /auth/v1/user) para testar renovação de sessão no cliente.
// Conta quantas renovações foram pedidas: GET /count.
const http = require('http');
let refreshes = 0;
const srv = http.createServer((req, res) => {
  let body = ''; req.on('data', d => body += d); req.on('end', () => {
    const out = (code, o) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    if (req.url === '/count') return out(200, { refreshes });
    if (req.url.startsWith('/auth/v1/token')) {
      refreshes++;
      // Token com formato de JWT real: o servidor em FRAIHA_DEV_AUTH não o aceita (invalid_token).
      return out(200, { access_token: 'eyJhbGciOiJIUzI1NiJ9.' + 'x'.repeat(60) + '.' + refreshes, refresh_token: 'refresh-' + refreshes, expires_in: 3600,
        user: { id: '11111111-1111-4111-a111-111111111111', email: 'real@teste.local', app_metadata: { provider: 'email' } } });
    }
    if (req.url.startsWith('/auth/v1/logout')) return out(204, {});
    out(404, {});
  });
});
srv.listen(Number(process.argv[2] || 0), '127.0.0.1', () => console.log('FAKE_AUTH ' + srv.address().port));
