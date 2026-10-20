'use strict';
// R171 · SEC-009 — corrida REAL no Postgres 16 (funções da migração 0023): várias conexões ao mesmo tempo.
// Opcional: roda só com FRAIHA_PG_TEST=1 e um Postgres local em /tmp:55432 com as migrations aplicadas
//   MIGDIR=<repo>/supabase/migrations bash /tmp/claude-0/pgtest171.sh   (ou /tmp/pgtest.sh apontando para este repo)
// Invariante conferida em TODOS os cenários: Fundadores entregues por pagamento <= limite.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawn, execFileSync } = require('child_process');
const crypto = require('crypto');
const ON = process.env.FRAIHA_PG_TEST === '1';
const PSQL = ['-h', '/tmp', '-p', '55432', '-U', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1'];
const q = sql => execFileSync('psql', [...PSQL, '-c', sql], { encoding: 'utf8' }).trim();
const qAsync = sql => new Promise((resolve, reject) => {
  const p = spawn('psql', [...PSQL, '-c', sql]); let out = '', err = '';
  p.stdout.on('data', d => { out += d; }); p.stderr.on('data', d => { err += d; });
  p.on('close', code => code === 0 ? resolve(out.trim()) : reject(new Error(err)));
});
const uuid = () => crypto.randomUUID();

function reset(limit) {
  q(`truncate public.payments, public.entitlements cascade; delete from public.profiles where nickname like 'fx_%';
     update public.founder_capacity set seat_limit = ${limit}, configured = true`);
}
function users(n) {
  const ids = [];
  for (let i = 0; i < n; i++) {
    const id = uuid(); ids.push(id);
    q(`insert into auth.users(id) values ('${id}'); insert into public.profiles(user_id, nickname) values ('${id}', 'fx_${id.slice(0, 8)}')`);
  }
  return ids;
}
// pedido aberto ANTES da corrida (vaga já reservada ou reserva vencida: o pior caso para o limite)
function order(user, product = 'founder', holdSql = "now() - interval '1 minute'") {
  const ref = uuid();
  q(`insert into public.payments(user_id, product_id, method, provider, provider_ref, amount_cents, status, seat_hold_until)
     values ('${user}', '${product}', 'pix', 'mp', '${ref}', 4490, 'pending', ${holdSql})`);
  return ref;
}
const pay = ref => qAsync(`select coalesce(public.fraiha_pay_and_grant('mp', '${ref}', 'mp')->>'status', 'null')`);
const reserve = (user, limit) => qAsync(`select public.fraiha_founder_reserve('${user}', 'founder', 'pix', 'mp', '${uuid()}', 4490, ${limit}, 1800)->>'ok'`);
const founders = () => Number(q('select count(*) from public.entitlements where is_founder'));
const statusCount = st => Number(q(`select count(*) from public.payments where status = '${st}'`));

test('SEC-009 (Postgres real): corrida de pagamentos nunca passa do limite', { skip: !ON && 'FRAIHA_PG_TEST=1 para rodar' }, async t => {
  for (const [limit, buyers] of [[1, 2], [1, 10], [2, 10], [3, 25]]) {
    await t.test(`${limit} vaga(s) / ${buyers} compradores pagando ao mesmo tempo`, async () => {
      reset(limit);
      const refs = users(buyers).map(u => order(u));
      const res = await Promise.all(refs.map(pay));
      assert.equal(founders(), limit, 'Fundadores = limite');
      assert.equal(res.filter(r => r === 'paid').length, limit);
      assert.equal(res.filter(r => r === 'sold_out').length, buyers - limit, 'os outros ficam sold_out (pagos, sem vantagem, para reembolso)');
      assert.equal(statusCount('pending'), 0, 'nenhum pagamento fica pendurado');
    });
  }
  await t.test('reservas ao mesmo tempo: só cabem as vagas; quem reservou recebe mesmo pagando por último', async () => {
    reset(2);
    const us = users(10);
    const ok = await Promise.all(us.map(u => reserve(u, 2)));
    assert.equal(ok.filter(x => x === 'true').length, 2, '2 reservas de 10');
    const refs = q("select provider_ref from public.payments where status = 'pending'").split('\n');
    const late = users(3).map(u => order(u));   // pedidos antigos com reserva vencida tentando passar na frente
    const res = await Promise.all([...late.map(pay), ...refs.map(pay)]);
    assert.equal(founders(), 2);
    assert.equal(res.filter(r => r === 'paid').length, 2);
    for (const r of refs) assert.equal(q(`select status from public.payments where provider_ref = '${r}'`), 'paid', 'quem tinha reserva viva recebeu');
  });
  await t.test('webhook duplicado / JÁ PAGUEI / reconciliação ao mesmo tempo: a mesma compra entrega 1 vez', async () => {
    reset(1);
    const [u] = users(1);
    const ref = order(u, 'founder', "now() + interval '10 minutes'");
    const res = await Promise.all(Array.from({ length: 12 }, () => pay(ref)).concat([qAsync('select public.fraiha_grant_paid_missing()')]));
    assert.equal(res.filter(r => r === 'paid').length, 1);
    assert.equal(founders(), 1);
    assert.equal(q(`select count(*) from public.entitlements where founder_number is not null`), '1');
  });
  await t.test('upgrade Fundador → Lendário com vagas esgotadas não ocupa vaga nova', async () => {
    reset(1);
    const [a, b] = users(2);
    assert.equal(await pay(order(a)), 'paid');
    assert.equal(await pay(order(a, 'founder_legend')), 'paid', 'Fundador vira Lendário');
    assert.equal(await pay(order(b)), 'sold_out', 'outra pessoa não passa do limite');
    assert.equal(founders(), 1);
  });
  await t.test('R172 · limite 0 / nulo / negativo = FECHADO (não existe "sem limite"): nada é entregue nem reservado', async () => {
    reset(0);
    const refs = users(6).map(u => order(u));
    const res = await Promise.allSettled(refs.map(pay));
    assert.equal(res.filter(r => r.status === 'rejected' && /founder_capacity_not_configured/.test(String(r.reason))).length, 6);
    assert.equal(founders(), 0);
    for (const v of ['0', 'null', '-3']) {
      assert.equal(q(`select public.fraiha_founder_set_limit(${v})`), '0');
      assert.equal(q('select configured from public.founder_capacity'), 'f', 'set_limit(' + v + ') deixa fechado');
      const [u] = users(1);
      assert.equal(await qAsync(`select public.fraiha_founder_reserve('${u}', 'founder', 'pix', 'mp', '${uuid()}', 4490, ${v}, 1800)->>'reason'`), 'closed');
    }
    assert.equal(statusCount('pending'), 6, 'pendentes, sem perda');
    assert.equal(q('select public.fraiha_founder_set_limit(5)'), '5');
    assert.equal(q('select configured from public.founder_capacity'), 't', 'inteiro positivo configura');
  });
});

// R171b · bloqueador do reteste Orca: janela de INICIALIZAÇÃO. A 0023 nasce FECHADA (configured=false).
test('SEC-009 (Postgres real): banco recém-migrado nasce fechado; corrida no boot nunca passa do limite', { skip: !ON && 'FRAIHA_PG_TEST=1 para rodar' }, async t => {
  await t.test('migração nova: capacidade não configurada → nenhuma entrega de Fundador, reconciliação pula, pedidos seguem pendentes', async () => {
    q(`truncate public.payments, public.entitlements cascade; delete from public.profiles where nickname like 'fx_%';
       update public.founder_capacity set seat_limit = 0, configured = false`);
    const refs = users(5).map(u => order(u));
    const res = await Promise.allSettled(refs.map(pay));
    assert.equal(res.filter(r => r.status === 'rejected' && /founder_capacity_not_configured/.test(String(r.reason))).length, 5, 'todas recusadas com erro (o aviso é repetido depois)');
    assert.equal(founders(), 0);
    assert.equal(statusCount('pending'), 5, 'nada se perde: continuam pendentes');
    q(`update public.payments set status = 'paid' where provider_ref = '${refs[0]}'`);
    const g = JSON.parse(q('select public.fraiha_grant_paid_missing()'));
    assert.equal(g.granted, 0, 'reconciliação não entrega Fundador sem limite configurado');
    assert.equal(founders(), 0);
  });
  for (const [limit, buyers] of [[1, 2], [1, 10], [2, 10]]) {
    await t.test(`boot: pagamentos chegando ANTES, DURANTE e DEPOIS de o servidor gravar o limite ${limit} (${buyers} compradores)`, async () => {
      q(`truncate public.payments, public.entitlements cascade; delete from public.profiles where nickname like 'fx_%';
         update public.founder_capacity set seat_limit = 0, configured = false`);
      const refs = users(buyers).map(u => order(u));
      const first = await Promise.allSettled(refs.map(pay));   // antes: tudo recusado
      assert.equal(founders(), 0);
      // durante: o servidor grava o limite AO MESMO TEMPO que os avisos são repetidos
      const during = await Promise.allSettled([qAsync(`select public.fraiha_founder_set_limit(${limit})`), ...refs.map(pay), ...refs.map(pay)]);
      assert.ok(founders() <= limit, `durante: ${founders()} <= ${limit}`);
      const after = await Promise.allSettled([...refs.map(pay), qAsync('select public.fraiha_grant_paid_missing()')]);
      assert.equal(founders(), limit, `Fundadores = ${limit}`);
      assert.equal(statusCount('sold_out'), buyers - limit);
      assert.equal(statusCount('pending'), 0);
      void first; void during; void after;
    });
  }
});

test('SEC-008 (Postgres real, migração 0024): a mesma partida contra bot só fica gravada para UMA conta', { skip: !ON && 'FRAIHA_PG_TEST=1 para rodar' }, async () => {
  q("delete from public.profiles where nickname like 'fx_%'");
  const [a, b, c] = users(3);
  const h = 'ab'.repeat(32);
  const ins = (u, bot) => qAsync(`insert into public.bot_progress(user_id, bot_id, game_hash) values ('${u}', '${bot}', '${h}')`);
  const res = await Promise.allSettled([ins(a, 'platina'), ins(b, 'platina'), ins(c, 'platina')]);
  assert.equal(res.filter(r => r.status === 'fulfilled').length, 1, 'só uma conta grava a partida');
  assert.ok(res.filter(r => r.status === 'rejected').every(r => /bot_progress_game_hash_uq|duplicate key/.test(String(r.reason))));
  assert.equal(q(`select count(*) from public.bot_progress where game_hash = '${h}'`), '1');
  q(`insert into public.bot_progress(user_id, bot_id) values ('${a}', 'madeira'), ('${b}', 'madeira')`);   // linhas sem partida (antigas) continuam livres
});
