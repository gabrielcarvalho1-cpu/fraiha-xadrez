'use strict';
// S01: exercise the real WebSocket dispatcher without external services.
const { startServer, client, check, summary } = require('./helpers.cjs');

(async () => {
  const s = await startServer({ FRAIHA_DEV_AUTH: '', SUPABASE_URL: '', SUPABASE_SERVICE_ROLE_KEY: '', SUPABASE_SECRET_KEY: '' });
  const clients = [];
  const connect = async () => {
    const c = client(s.port); clients.push(c); await c.open(); return c;
  };
  try {
    check(s.log().includes('backend: disabled'), 'external account backend disabled');
    const other = await connect();
    const invalid = [null, [], [{ type: 'create' }], 'ping', 0, 42, true, false,
      {}, { type: null }, { type: 1 }, { type: true }, { type: [] }, { type: {} }];
    for (const payload of invalid) {
      const c = await connect();
      c.send(payload);
      const error = await c.next('error');
      check(error.message === 'Mensagem inválida.', 'reject ' + JSON.stringify(payload));
      c.send({ type: 'ping' });
      check((await c.next('pong')).type === 'pong', 'same connection remains usable');
      other.send({ type: 'ping' });
      check((await other.next('pong')).type === 'pong' && s.proc.exitCode === null,
        'process and other connection survive');
      c.close();
    }
    other.send({ type: 'create' });
    const welcome = await other.next('welcome');
    const initial = await other.next('state');
    check(welcome.color === 'w' && initial.board.length === 32, 'valid create returns welcome and board');
    const joiner = await connect();
    joiner.send({ type: 'join', room: welcome.room });
    check((await joiner.next('welcome')).color === 'b', 'valid join still works');
    const joined = await joiner.next('state');
    other.send({ type: 'move', revision: joined.revision, from: [4, 6], to: [4, 4] });
    const moved = await joiner.next(m => m.type === 'state' && m.move_count === 1);
    check(moved.turn === 'b' && moved.last_to.join() === '4,4', 'valid move reaches the other connection');
    joiner.send({ type: 'acct_refresh' });
    check((await joiner.next('acct_error')).code === 'accounts_disabled', 'valid backend message still dispatches');
    check(!s.log().includes('TypeError'), 'no uncaught TypeError in server log');
    summary('WS_INPUT');
  } catch (e) {
    console.error(s.log());
    throw e;
  } finally {
    for (const c of clients) c.ws.terminate();
    s.stop();
  }
})().catch(e => { console.error(e); process.exitCode = 1; });
