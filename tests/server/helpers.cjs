'use strict';
// Test helpers: start the real server.js on a free port and talk JSON over ws.
const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');
async function startServer(env = {}) {
  const port = 20000 + Math.floor(Math.random() * 20000);
  const proc = spawn(process.execPath, [path.join(__dirname, '../../online_v021/server.js')], { env: { ...process.env, PORT: String(port), ...env }, stdio: ['ignore', 'pipe', 'pipe'] });
  let log = ''; proc.stdout.on('data', d => log += d); proc.stderr.on('data', d => log += d);
  for (let i = 0; i < 100 && !log.includes('listening'); i++) await new Promise(r => setTimeout(r, 50));
  return { port, proc, log: () => log, stop: () => proc.kill() };
}
function client(port) {
  const ws = new WebSocket('ws://127.0.0.1:' + port);
  const inbox = []; const waiters = [];
  ws.on('message', raw => { const m = JSON.parse(raw); const i = waiters.findIndex(w => w.pred(m)); if (i >= 0) { const w = waiters.splice(i, 1)[0]; w.resolve(m); } else inbox.push(m); });
  const api = {
    ws, inbox,
    open: () => new Promise(r => ws.readyState === 1 ? r() : ws.once('open', r)),
    send: o => ws.send(JSON.stringify(o)),
    next(pred, ms = 3000) {
      const p = typeof pred === 'string' ? (m => m.type === pred) : pred;
      const i = inbox.findIndex(p); if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
      return new Promise((resolve, reject) => { const w = { pred: p, resolve }; waiters.push(w); setTimeout(() => { const k = waiters.indexOf(w); if (k >= 0) { waiters.splice(k, 1); reject(new Error('timeout waiting for ' + (typeof pred === 'string' ? pred : 'predicate'))); } }, ms); });
    },
    close: () => ws.close(),
  };
  return api;
}
let failures = 0, checks = 0;
function check(ok, label) { checks++; if (!ok) failures++; console.log((ok ? 'PASS ' : 'FAIL ') + label); }
function summary(name) { console.log(`${name} CHECKS=${checks} FAILURES=${failures}`); process.exitCode = failures ? 1 : 0; }
module.exports = { startServer, client, check, summary };
