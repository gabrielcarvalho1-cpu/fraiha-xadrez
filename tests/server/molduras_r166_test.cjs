'use strict';
// R166 · molduras novas: de ELO (liberadas ao alcançar a liga no Ranked) e da Loja (compradas); as antigas desenhadas saíram.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs'), path = require('path');
const C = require('../../online_v021/accounts/cosmetics');
const Shop = require('../../online_v021/economy/store_catalog');

test('molduras de elo e da loja', () => {
  assert.equal(C.ELO_FRAMES.length, 11, 'Madeira a Challenger');
  for (const id of [...C.ELO_FRAMES, ...Shop.ofKind('frame')]) assert.ok(fs.existsSync(path.join(__dirname, '../../monetization/frames', id + '.png')), id + ' tem arte');
  assert.equal(Shop.ofKind('frame').length, 2);
  for (const i of Shop.ITEMS.filter(i => i.kind === 'frame')) assert.equal(i.price, 10000);
  assert.ok(!C.FRAMES.includes('m_safira_real'), 'guardadas: ninguém usa');
  for (const old of ['prata', 'rubi', 'safira', 'jade', 'ametista', 'obsidiana']) { assert.ok(!C.FRAMES.includes(old)); assert.equal(C.look({ frame: old }).frame, 'liga', 'antiga vira a da liga'); }
  assert.ok(C.validate({ frame: 'elo_madeira' }, {}, [], [], 0).ok, 'Madeira já começa liberada');
  assert.equal(C.validate({ frame: 'elo_ouro' }, {}, [], [], 3).code, 'cosmetic_locked', 'Prata não usa a de Ouro');
  assert.ok(C.validate({ frame: 'elo_ouro' }, {}, [], [], 6).ok, 'quem já passou do Ouro usa');
  assert.equal(C.validate({ frame: 'm_chama_eterna' }, {}, [], []).code, 'cosmetic_locked');
  assert.ok(C.validate({ frame: 'm_chama_eterna' }, {}, [], ['m_chama_eterna']).ok);
});
