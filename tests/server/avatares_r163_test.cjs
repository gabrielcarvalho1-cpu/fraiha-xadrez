'use strict';
// R163 · 34 avatares novos: grátis, Loja de Coroas, Passe (nível 25, faixas grátis e Club), Club e Fundador (+Lendário).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs'), path = require('path');
const C = require('../../online_v021/accounts/cosmetics');
const Shop = require('../../online_v021/economy/store_catalog');
const { rewards, seasonAvatars, AVATAR_LEVEL } = require('../../online_v021/economy/season_pass');

test('cada avatar novo tem arte e um dono certo', () => {
  const novos = fs.readdirSync(path.join(__dirname, '../../profile/avatars')).filter(f => /^av_.*\.webp$/.test(f)).map(f => f.replace('.webp', ''));
  assert.equal(novos.length, 74);   // R163 34 + R164 30 + R166 10
  for (const id of novos) assert.ok(C.ALL_AVATARS.includes(id), id + ' no servidor');
  const groups = [C.FREE_AVATARS, C.CLUB_AVATARS, C.FOUNDER_AVATARS, C.LEGEND_AVATARS, C.OWNED_AVATARS];
  for (const id of novos) assert.equal(groups.filter(g => g.includes(id)).length, 1, id + ' em um grupo só');
  assert.equal(Shop.ofKind('avatar').length, 24);
  assert.equal(Shop.PASS_AVATARS.length, 17);
});

test('regras de uso', () => {
  const none = { is_founder: false, club_active: false };
  assert.ok(C.validate({ avatar_id: 'av_heroi' }, none, [], []).ok, 'grátis');
  assert.equal(C.validate({ avatar_id: 'av_rei_rubi' }, none, [], []).code, 'cosmetic_locked', 'loja sem comprar');
  assert.ok(C.validate({ avatar_id: 'av_rei_rubi' }, none, [], ['av_rei_rubi']).ok, 'loja comprado');
  assert.equal(C.validate({ avatar_id: 'av_rei_onix' }, none, [], []).code, 'cosmetic_locked', 'passe sem ganhar');
  assert.ok(C.validate({ avatar_id: 'av_rei_onix' }, none, [], ['av_rei_onix']).ok, 'passe ganho');
  assert.equal(C.validate({ avatar_id: 'av_rainha_neon' }, none, [], []).code, 'cosmetic_locked', 'club');
  assert.ok(C.validate({ avatar_id: 'av_rainha_neon' }, { club_active: true }, [], []).ok);
  assert.equal(C.validate({ avatar_id: 'av_lenda_mistica' }, { is_founder: true, founder_tier: 'founder' }, [], []).code, 'cosmetic_locked', 'só Lendário');
  assert.ok(C.validate({ avatar_id: 'av_lenda_mistica' }, { is_founder: true, founder_tier: 'legend' }, [], []).ok);
  assert.equal(C.effective({ avatar_id: 'av_rainha_neon' }, { club_active: false }).avatar_id, 'warrior', 'Club venceu: volta ao Guerreiro');
});

test('passe: avatar no nível 25 nas duas faixas, girando por temporada', () => {
  const r = rewards('2026-10')[AVATAR_LEVEL - 1];
  assert.equal(r.free.kind, 'avatar'); assert.equal(r.club.kind, 'avatar');
  const a = seasonAvatars('2026-10'), b = seasonAvatars('2026-11');
  assert.notEqual(a.free.id, b.free.id); assert.notEqual(a.club.id, b.club.id);
});
