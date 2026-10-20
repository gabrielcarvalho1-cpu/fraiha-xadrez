'use strict';
// R171 · SEC-010 — denúncias do chat global: a mesma pessoa denunciando a MESMA mensagem gera 1 registro só
// (chave: denunciante + id da mensagem + tipo), há teto por pessoa e por IP, e denúncias legítimas de pessoas
// diferentes (ou de mensagens diferentes) nunca se perdem.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { GlobalChat } = require('../../online_v021/social/global_chat');

function setup() {
  const sent = [], logs = [], filed = [];
  let t = 1_000_000;
  const backend = { reports: { file: async r => { filed.push(r); } } };
  const gc = new GlobalChat({ send: (ws, m) => sent.push({ to: ws.user ? ws.user.id : '?', ...m }), backend, now: () => t, log: (...a) => logs.push(a.join(' ')) });
  const user = (id, ip = '10.0.0.' + id.length) => ({ readyState: 1, ip, user: { id }, profile: { nickname: id } });
  const post = (ws, text) => { t += 3000; gc.handle(ws, { type: 'gchat_send', text }); return gc.messages.at(-1).id; };
  const report = async (ws, id) => { await gc.handle(ws, { type: 'gchat_report', id }); return sent.at(-1); };
  return { gc, sent, logs, filed, user, post, report, tick: ms => { t += ms; } };
}

test('SEC-010: 1 denúncia → 1 registro (log + fila do Admin)', async () => {
  const s = setup();
  const autor = s.user('autor'), ana = s.user('ana');
  const id = s.post(autor, 'mensagem ruim');
  const r = await s.report(ana, id);
  assert.equal(r.type, 'gchat_reported'); assert.equal(r.duplicate, undefined);
  assert.equal(s.filed.length, 1); assert.equal(s.logs.filter(l => l.startsWith('[gchat-report]')).length, 1);
});

for (const n of [3, 10]) {
  test(`SEC-010: ${n} denúncias iguais (mesma pessoa, mesma mensagem) → 1 registro, as outras confirmadas como repetidas`, async () => {
    const s = setup();
    const autor = s.user('autor'), ana = s.user('ana');
    const id = s.post(autor, 'mensagem ruim');
    const res = await Promise.all(Array.from({ length: n }, () => s.report(ana, id)));
    assert.equal(s.filed.length, 1, 'só 1 entra na fila');
    assert.equal(s.logs.filter(l => l.startsWith('[gchat-report]')).length, 1, 'só 1 linha de log');
    assert.equal(s.sent.filter(m => m.type === 'gchat_reported' && m.duplicate).length, n - 1, 'as repetidas respondem "já denunciada" (sem erro)');
    assert.equal(s.sent.filter(m => m.type === 'gchat_error').length, 0);
    void res;
  });
}

test('SEC-010: duas pessoas denunciando a MESMA mensagem → 2 registros (nenhuma denúncia legítima se perde)', async () => {
  const s = setup();
  const autor = s.user('autor');
  const id = s.post(autor, 'mensagem ruim');
  await s.report(s.user('ana', '1.1.1.1'), id);
  await s.report(s.user('bia', '1.1.1.1'), id);   // mesmo IP (ex.: mesma casa) não junta pessoas diferentes
  await s.report(s.user('caio', '2.2.2.2'), id);
  assert.deepEqual(s.filed.map(f => f.reporter), ['ana', 'bia', 'caio']);
});

test('SEC-010: mesma pessoa denunciando mensagens DIFERENTES → cada uma registrada; teto 10 por pessoa / 10 min', async () => {
  const s = setup();
  const autor = s.user('autor'), ana = s.user('ana');
  const ids = Array.from({ length: 12 }, (_, i) => s.post(autor, 'msg ' + i));
  for (const id of ids.slice(0, 10)) assert.equal((await s.report(ana, id)).type, 'gchat_reported');
  assert.equal(s.filed.length, 10);
  const r = await s.report(ana, ids[10]);
  assert.equal(r.type, 'gchat_error'); assert.equal(r.code, 'rate_limited');
  assert.equal(s.filed.length, 10, 'a 11ª em 10 min é recusada com aviso (não some calada)');
  s.tick(10 * 60e3 + 1);
  assert.equal((await s.report(ana, ids[10])).type, 'gchat_reported', 'passada a janela, volta a aceitar');
  assert.equal(s.filed.length, 11);
  assert.equal((await s.report(s.user('bia'), ids[11])).type, 'gchat_reported', 'o teto de uma pessoa não afeta outra');
});

test('SEC-010: teto por IP (30 / 10 min) contra muitas contas no mesmo IP; repetida não consome teto', async () => {
  const s = setup();
  const autor = s.user('autor');
  const id = s.post(autor, 'alvo');
  for (let i = 0; i < 30; i++) await s.report(s.user('c' + i, '9.9.9.9'), id);
  assert.equal(s.filed.length, 30);
  assert.equal((await s.report(s.user('c30', '9.9.9.9'), id)).code, 'rate_limited');
  assert.equal((await s.report(s.user('fora', '8.8.8.8'), id)).type, 'gchat_reported', 'outro IP segue normal');
  const s2 = setup();
  const id2 = s2.post(s2.user('autor'), 'x'), ana = s2.user('ana');
  for (let i = 0; i < 25; i++) await s2.report(ana, id2);
  assert.equal(s2.filed.length, 1);
  const other = s2.post(s2.user('autor'), 'y');
  assert.equal((await s2.report(ana, other)).type, 'gchat_reported', 'repetições não esgotaram o teto da pessoa');
});

test('SEC-010: mensagem inexistente não registra nada', async () => {
  const s = setup();
  const r = await s.report(s.user('ana'), 999);
  assert.equal(r.code, 'not_found'); assert.equal(s.filed.length, 0);
});
