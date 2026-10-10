'use strict';
// H03 · gravação do resultado Ranked com nova tentativa SEGURA (idempotente).
//
// A gravação (RPC fraiha_record_ranked_match) é uma transação só: confere o PL/liga "antes" de cada jogador,
// aplica o PL e insere a partida com match_id como chave primária. Por isso ela nunca aplica PL duas vezes:
// repetir a mesma partida falha (PL "antes" mudou / match_id já existe). O que faltava era tratar a falha:
//   - falha transitória (rede, 5xx, tempo esgotado, Supabase reiniciando) → tenta de novo com espera crescente;
//   - antes de cada nova tentativa e depois de qualquer erro, pergunta ao banco se a partida JÁ está gravada
//     (a resposta da tentativa anterior pode ter se perdido depois do commit) → se estiver, é sucesso, sem
//     reaplicar nada;
//   - erro permanente (estado Ranked mudou, dados inválidos) → para (repetir não muda o resultado).
// Sem migração: usa só a tabela matches (leitura com service role) e a mesma RPC.
const DEFAULT_DELAYS = [1000, 2000, 4000, 8000, 15000, 30000];   // ~60 s no total

function delaysFromEnv(env = process.env) {
  const raw = String(env.FRAIHA_RANKED_PERSIST_RETRY_MS || '').trim();   // ex.: "50,50,50" (testes)
  if (!raw) return DEFAULT_DELAYS;
  const list = raw.split(',').map(x => Number(x.trim())).filter(x => Number.isFinite(x) && x >= 0);
  return list.length ? list : DEFAULT_DELAYS;
}

// Erros em que repetir não adianta: o banco recusou a partida por regra, não por instabilidade.
function permanent(e) {
  const msg = String((e && e.message) || ''), code = String((e && e.code) || '');
  if (/estado Ranked mudou|ranked_stats ausente/i.test(msg)) return true;
  if (/^(22|23|42)/.test(code) && code !== '23505') return true;   // dado/constraint/sintaxe (23505 = já gravada)
  return false;
}

const sleep = ms => new Promise(r => { const t = setTimeout(r, ms); if (t.unref) t.unref(); });

// Devolve { saved: boolean, attempts, already: boolean, error?: string }.
async function persistRanked(store, record, { delays = delaysFromEnv(), log = console, wait = sleep } = {}) {
  const id = record && record.match_id;
  const recorded = async () => {
    if (!store.hasRankedMatch) return false;
    try { return !!(await store.hasRankedMatch(id)); } catch (e) { return null; }   // null = não deu para saber
  };
  let lastError = '';
  for (let attempt = 0; attempt <= delays.length; attempt++) {
    if (attempt > 0) {
      await wait(delays[attempt - 1]);
      const has = await recorded();
      if (has === true) return { saved: true, attempts: attempt, already: true };
    }
    try {
      await store.recordRankedMatch(record);
      return { saved: true, attempts: attempt + 1, already: false };
    } catch (e) {
      lastError = String((e && e.message) || e);
      const has = await recorded();
      if (has === true) return { saved: true, attempts: attempt + 1, already: true };   // commit feito, resposta perdida
      if (String((e && e.code) || '') === '23505') return { saved: true, attempts: attempt + 1, already: true };   // match_id já existe
      if (permanent(e)) {
        log.error('ranked persist failed (permanente)', id, lastError);
        return { saved: false, attempts: attempt + 1, already: false, error: lastError };
      }
      log.error('ranked persist failed (tentativa ' + (attempt + 1) + '/' + (delays.length + 1) + ')', id, lastError);
    }
  }
  // Esgotou: registra a partida inteira no log para reconciliação manual (o resultado não se perde).
  log.error('RANKED_PERSIST_GAVE_UP ' + JSON.stringify(record));
  return { saved: false, attempts: delays.length + 1, already: false, error: lastError };
}

module.exports = { persistRanked, delaysFromEnv, permanent, DEFAULT_DELAYS };
