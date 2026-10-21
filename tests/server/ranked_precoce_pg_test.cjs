'use strict';
// R173 · migração 0025 no Postgres 16 REAL (função fraiha_record_ranked_match com "count_stats").
// Opcional: roda só com FRAIHA_PG_TEST=1 e um Postgres local em /tmp:55432 com as migrations aplicadas
//   MIGDIR=<repo>/supabase/migrations bash /tmp/claude-0/pgtest171.sh
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('child_process');
const crypto = require('crypto');
const path = require('path');
const ON = process.env.FRAIHA_PG_TEST === '1';
const PSQL = ['-h', '/tmp', '-p', '55432', '-U', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1'];
const q = sql => execFileSync('psql', [...PSQL, '-c', sql], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const uuid = () => crypto.randomUUID();
const MIG = path.join(__dirname, '../../supabase/migrations/0025_fraiha_ranked_precoce.sql');

function pair(plW = 50, plB = 50) {
  const ids = [uuid(), uuid()];
  for (const id of ids) q(`insert into auth.users(id) values ('${id}'); insert into public.profiles(user_id, nickname) values ('${id}', 'p${id.slice(0, 8)}')`);
  q(`update public.ranked_stats set pl = ${plW}, forca = 1234.5, forca_rd = 77, matches = 3, wins = 2, losses = 1 where user_id = '${ids[0]}' and mode = 'ranked_5min';
     update public.ranked_stats set pl = ${plB}, forca = 1111, forca_rd = 88, matches = 5, wins = 1, losses = 3, draws = 1 where user_id = '${ids[1]}' and mode = 'ranked_5min'`);
  return ids;
}
const row = id => { const [league, pl, matches, wins, losses, draws, forca, rd] = q(`select league, pl, matches, wins, losses, draws, forca, forca_rd from public.ranked_stats where user_id = '${id}' and mode = 'ranked_5min'`).split('|').map(Number); return { league, pl, matches, wins, losses, draws, forca, rd }; };
// Brancas desistem: perdem 4, Pretas ganham 4 (o que o servidor R173 manda num resultado precoce)
function payload(w, b, extra = {}, mid = uuid()) {
  return { match_id: mid, mode: 'ranked_5min', white_user_id: w, black_user_id: b, started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
    result: 'black', result_reason: 'resign', white_pl_before: 50, black_pl_before: 50, white_pl_change: -4, black_pl_change: 4,
    white_pl_after: 46, black_pl_after: 54, white_league_before: 0, black_league_before: 0, white_league_after: 0, black_league_after: 0,
    moves: '', white_forca_after: null, white_forca_rd_after: null, black_forca_after: null, black_forca_rd_after: null, ...extra };
}
const call = p => q(`select public.fraiha_record_ranked_match('${JSON.stringify(p).replace(/'/g, "''")}'::jsonb)`);

test('0025 · precoce (count_stats=false): PL muda; Força, partidas e V/D/E NÃO mudam', { skip: !ON }, () => {
  const [w, b] = pair();
  const p = payload(w, b, { count_stats: false });
  assert.equal(call(p), p.match_id);
  assert.deepEqual(row(w), { league: 0, pl: 46, matches: 3, wins: 2, losses: 1, draws: 0, forca: 1234.5, rd: 77 });
  assert.deepEqual(row(b), { league: 0, pl: 54, matches: 5, wins: 1, losses: 3, draws: 1, forca: 1111, rd: 88 });
  assert.equal(q(`select counts_stats from public.matches where match_id = '${p.match_id}'`), 'f');
});

test('0025 · normal (10+ meios-lances, count_stats=true): soma tudo e grava a Força', { skip: !ON }, () => {
  const [w, b] = pair();
  const p = payload(w, b, { count_stats: true, result_reason: 'resign', white_pl_change: -4, black_pl_change: 36, black_pl_after: 86,
    white_forca_after: 1200, white_forca_rd_after: 70, black_forca_after: 1150, black_forca_rd_after: 80 });
  call(p);
  assert.deepEqual(row(w), { league: 0, pl: 46, matches: 4, wins: 2, losses: 2, draws: 0, forca: 1200, rd: 70 });
  assert.deepEqual(row(b), { league: 0, pl: 86, matches: 6, wins: 2, losses: 3, draws: 1, forca: 1150, rd: 80 });
  assert.equal(q(`select counts_stats from public.matches where match_id = '${p.match_id}'`), 't');
});

test('0025 · servidor antigo (sem o campo): conta normalmente (compatível)', { skip: !ON }, () => {
  const [w, b] = pair();
  call(payload(w, b));
  assert.equal(row(w).matches, 4); assert.equal(row(b).wins, 2);
});

test('0025 · replay da MESMA partida não aplica de novo (precoce e normal; inclusive com PL 0 → 0)', { skip: !ON }, () => {
  const [w, b] = pair();
  const p = payload(w, b, { count_stats: false });
  call(p);
  assert.throws(() => call(p), /estado Ranked mudou/);
  assert.equal(row(w).pl, 46); assert.equal(row(b).pl, 54);
  // caso em que o "antes" não muda (perdedor no piso, vencedor +0): a chave da partida barra o replay
  const [x, y] = pair(0, 50);
  const z = payload(x, y, { count_stats: false, white_pl_before: 0, white_pl_change: 0, white_pl_after: 0, black_pl_change: 0, black_pl_after: 50 });
  call(z);
  assert.throws(() => call(z), /duplicate key|matches_pkey/);
  assert.deepEqual([row(x).matches, row(y).matches, row(x).pl, row(y).pl], [3, 5, 0, 50]);
  assert.equal(q(`select count(*) from public.matches where match_id = '${z.match_id}'`), '1');
  // normal também: replay barrado, contagem não dobra
  const [c, d] = pair();
  const n = payload(c, d, { count_stats: true });
  call(n);
  assert.throws(() => call(n));
  assert.equal(row(c).matches, 4);
});

test('0025 · não é retroativa: partidas antigas ficam counts_stats=true e o placar antigo não muda; reaplicar é seguro', { skip: !ON }, () => {
  const [w, b] = pair();
  q('alter table public.matches drop column counts_stats');            // volta ao estado "antes da 0025"
  const old = payload(w, b);
  q(`insert into public.matches (match_id, mode, white_user_id, black_user_id, started_at, finished_at, result, result_reason,
      white_pl_before, black_pl_before, white_pl_change, black_pl_change, white_pl_after, black_pl_after,
      white_league_before, black_league_before, white_league_after, black_league_after, moves)
     values ('${old.match_id}', 'ranked_5min', '${w}', '${b}', now(), now(), 'black', 'resign', 50, 50, -4, 4, 46, 54, 0, 0, 0, 0, '')`);
  const before = [row(w), row(b)];
  execFileSync('psql', [...PSQL, '-q', '-f', MIG]);
  execFileSync('psql', [...PSQL, '-q', '-f', MIG]);                    // idempotente
  assert.equal(q(`select counts_stats from public.matches where match_id = '${old.match_id}'`), 't');
  assert.equal(q(`select count(*) from public.matches where counts_stats = false and match_id = '${old.match_id}'`), '0');
  assert.deepEqual([row(w), row(b)], before, 'ranked_stats intactos');
});

test('0025 · cliente logado não chama a função', { skip: !ON }, () => {
  assert.equal(q(`select has_function_privilege('authenticated', 'public.fraiha_record_ranked_match(jsonb)', 'execute')`), 'f');
  assert.equal(q(`select has_function_privilege('service_role', 'public.fraiha_record_ranked_match(jsonb)', 'execute')`), 't');
});
