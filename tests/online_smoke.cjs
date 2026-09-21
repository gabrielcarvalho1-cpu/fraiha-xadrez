// Two independent protocol clients; never prints reconnect credentials.
// Run with Node 22+: node tests/online_smoke.cjs [wss endpoint]
const assert = require('node:assert/strict');
const endpoint = process.argv[2] || 'wss://fraiha-xadrez.onrender.com';
if (!endpoint.startsWith('wss://') && !endpoint.startsWith('ws://127.0.0.1:')) throw Error('Use WSS or local test server');
let passed = 0;
const clients = [];
const pause = ms => new Promise(r => setTimeout(r, ms));
function check(ok, name) { assert.ok(ok, name); passed++; console.log('PASS ' + name); }
async function until(fn, label, timeout = 15000) {
  const deadline = Date.now() + timeout;
  while (!fn()) { if (Date.now() > deadline) throw Error('Timeout: ' + label); await pause(40); }
}
async function connect() {
  const c = { ws: new WebSocket(endpoint), messages: [], state: null, welcome: null, errors: [] };
  clients.push(c);
  c.ws.addEventListener('message', ev => {
    const m = JSON.parse(ev.data);
    c.messages.push(m);
    if (m.type === 'state') c.state = m;
    if (m.type === 'welcome') c.welcome = m;
    if (m.type === 'error') c.errors.push(m.message);
  });
  await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(Error('WebSocket connect timeout')), 150000);
    c.ws.addEventListener('open', () => { clearTimeout(t); resolve(); }, { once: true });
    c.ws.addEventListener('error', () => { clearTimeout(t); reject(Error('WebSocket connection failed')); }, { once: true });
  });
  c.send = data => c.ws.send(JSON.stringify(data));
  return c;
}
const canonical = board => JSON.stringify([...board].sort((a,b) => a[0]-b[0] || a[1]-b[1]));
async function move(c, other, from, to) {
  const revision = c.state.revision;
  c.send({type:'move',from,to,revision});
  await until(() => c.state.revision === revision+1 && other.state.revision === revision+1, 'move sync');
  check(canonical(c.state.board) === canonical(other.state.board), 'identical boards after ' + from + ' -> ' + to);
}
(async () => {
  const a = await connect();
  a.send({type:'create'});
  await until(() => a.welcome && a.state, 'create');
  check(a.welcome.color === 'w' && /^[A-Z0-9]{6}$/.test(a.welcome.room), 'room creation and six-character code');
  let b = await connect();
  b.send({type:'join',room:a.welcome.room});
  await until(() => b.welcome && a.state.started && b.state?.started, 'join');
  check(b.welcome.color === 'b' && a.state.white_connected && a.state.black_connected, 'two clients in same room with opposite colors');
  const firstRevision = b.state.revision;
  b.send({type:'move',from:[4,1],to:[4,3],revision:firstRevision});
  await until(() => b.errors.length > 0, 'wrong-turn rejection');
  check(b.state.revision === firstRevision, 'wrong-turn move rejected without altering state');
  await move(a,b,[4,6],[4,4]);
  await move(b,a,[3,1],[3,3]);
  await move(a,b,[4,4],[3,3]);
  check(b.state.board.length === 31 && b.state.captured_black.includes('bP'), 'capture synchronized');
  await move(b,a,[6,0],[5,2]);
  const reconnect = {...b.welcome};
  const before = canonical(a.state.board);
  b.ws.close();
  await until(() => !a.state.black_connected, 'disconnect');
  b = await connect();
  b.send({type:'resume',room:reconnect.room,token:reconnect.token});
  await until(() => b.welcome && b.state?.black_connected && a.state.black_connected, 'resume');
  check(canonical(b.state.board) === before && b.welcome.color === 'b', 'reconnect restores original board and color');
  a.send({type:'restart',revision:a.state.revision});
  await until(() => a.state.restart_votes.length === 1, 'first vote');
  check(a.state.move_count === 4, 'one rematch vote does not reset game');
  b.send({type:'restart',revision:b.state.revision});
  await until(() => a.state.move_count === 0 && b.state.move_count === 0, 'rematch');
  check(a.state.board.length === 32 && canonical(a.state.board) === canonical(b.state.board), 'consensual rematch resets both boards');
  b.send({type:'resign',revision:b.state.revision});
  await until(() => a.state.game_over && b.state.game_over, 'resign');
  check(a.state.status.includes('BRANCAS VENCEM'), 'resignation synchronized');
  console.log(JSON.stringify({endpoint,checks:passed,failures:0,test:'two independent WSS protocol clients'}));
})().catch(e => { console.error('FAIL ' + e.message); process.exitCode = 1; }).finally(async () => {
  for (const c of clients) {
    if (c.ws.readyState === WebSocket.OPEN) { c.send({type:'leave'}); c.ws.close(); }
  }
  await pause(200);
});
