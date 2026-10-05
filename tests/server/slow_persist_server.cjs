'use strict';
// R42.1 · servidor de teste com a gravação do resultado Ranked LENTA (como a RPC real do Supabase).
// O estado "finished" chega ao cliente antes do ranked_result — reproduz o atraso de produção.
// Uso: PORT=… FRAIHA_DEV_AUTH=1 PERSIST_DELAY_MS=400 node tests/server/slow_persist_server.cjs
const { MemoryStore } = require('../../online_v021/accounts/store');
const delay = Number(process.env.PERSIST_DELAY_MS || 400);
const orig = MemoryStore.prototype.recordRankedMatch;
MemoryStore.prototype.recordRankedMatch = async function (r) { await new Promise(z => setTimeout(z, delay)); return orig.call(this, r); };
require('../../online_v021/server.js');
