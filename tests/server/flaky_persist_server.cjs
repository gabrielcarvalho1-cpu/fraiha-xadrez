'use strict';
// H03 · servidor de teste com a gravação Ranked INSTÁVEL (falhas transitórias da RPC do Supabase).
//   FLAKY_MODE=transient  → as FLAKY_N primeiras chamadas falham ANTES de gravar (rede/5xx)
//   FLAKY_MODE=lost       → as FLAKY_N primeiras chamadas GRAVAM e depois falham (resposta perdida após o commit)
//   FLAKY_MODE=down       → todas falham (banco fora do ar)
// Uso: PORT=… FRAIHA_DEV_AUTH=1 FRAIHA_RANKED_PERSIST_RETRY_MS=100,100,100 FLAKY_MODE=… node tests/server/flaky_persist_server.cjs
const { MemoryStore } = require('../../online_v021/accounts/store');
const mode = process.env.FLAKY_MODE || 'transient', n = Number(process.env.FLAKY_N || 2);
const orig = MemoryStore.prototype.recordRankedMatch;
let calls = 0;
MemoryStore.prototype.recordRankedMatch = async function (r) {
  calls++;
  console.log('FLAKY call ' + calls);
  if (mode === 'down' || (mode === 'transient' && calls <= n)) { const e = new Error('fetch failed (ECONNRESET)'); throw e; }
  const out = await orig.call(this, r);
  if (mode === 'lost' && calls <= n) throw new Error('HTTP 504');
  return out;
};
require('../../online_v021/server.js');
