'use strict';
// R183 · /app-version: padrões, configuração pelo Render e valores inválidos ignorados.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { info, owns, DEFAULTS } = require('../../online_v021/accounts/app_version');

test('padrões sem variável', () => {
  assert.deepEqual(info({}).android, { latest: DEFAULTS.latest, min: DEFAULTS.min, name: DEFAULTS.name, url: DEFAULTS.url });
  assert.ok(DEFAULTS.url.startsWith('https://'));
});
test('configurável pelo Render', () => {
  const a = info({ FRAIHA_ANDROID_LATEST_CODE: '5', FRAIHA_ANDROID_MIN_CODE: '3', FRAIHA_ANDROID_LATEST_NAME: '1.2.0', FRAIHA_ANDROID_APK_URL: 'https://x.com/a.apk' }).android;
  assert.deepEqual(a, { latest: 5, min: 3, name: '1.2.0', url: 'https://x.com/a.apk' });
});
test('valores inválidos caem no padrão', () => {
  const a = info({ FRAIHA_ANDROID_LATEST_CODE: 'abc', FRAIHA_ANDROID_MIN_CODE: '-1', FRAIHA_ANDROID_LATEST_NAME: '<b>', FRAIHA_ANDROID_APK_URL: 'http://inseguro/a.apk' }).android;
  assert.deepEqual(a, { latest: DEFAULTS.latest, min: DEFAULTS.min, name: DEFAULTS.name, url: DEFAULTS.url });
});
test('rota', () => {
  assert.ok(owns({ method: 'GET', url: '/app-version' }));
  assert.ok(!owns({ method: 'POST', url: '/app-version' }));
  assert.ok(!owns({ method: 'GET', url: '/app-versionx' }));
});
