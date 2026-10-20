'use strict';
// R168 · CHAT GLOBAL com abas: GERAL / PROCURANDO PARCEIROS / DÚVIDAS E AJUDA (canal na mensagem; histórico por canal)
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { GlobalChat, HISTORY, CHANNELS } = require('../../online_v021/social/global_chat');

test('canais: mensagem leva o canal; canal inválido vira geral; histórico por canal', () => {
  const out = [];
  let t = 0;
  const g = new GlobalChat({ send: (ws, m) => out.push({ ws, m }), backend: null, now: () => (t += 3000), log: () => {} });
  const ws = { user: { id: 'u1' }, profile: { nickname: 'Gabriel' }, readyState: 1 };
  g.handle(ws, { type: 'gchat_join' });
  assert.deepEqual(out[0].m.channels, CHANNELS);
  g.handle(ws, { type: 'gchat_send', text: 'alguém pra jogar?', channel: 'parceiros' });
  g.handle(ws, { type: 'gchat_send', text: 'como faz roque?', channel: 'ajuda' });
  g.handle(ws, { type: 'gchat_send', text: 'oi', channel: 'xyz' });
  g.handle(ws, { type: 'gchat_send', text: 'oi geral' });
  const sent = out.filter(x => x.m.type === 'gchat_msg').map(x => x.m.channel);
  assert.deepEqual(sent, ['parceiros', 'ajuda', 'geral', 'geral']);
  for (let i = 0; i < HISTORY + 5; i++) g.handle(ws, { type: 'gchat_send', text: 'flood ' + i, channel: 'geral' });
  assert.equal(g.messages.filter(x => x.channel === 'geral').length, HISTORY);
  assert.equal(g.messages.filter(x => x.channel === 'ajuda').length, 1, 'geral movimentado não apaga a ajuda');
});
