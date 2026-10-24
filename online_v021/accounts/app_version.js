'use strict';
// R183 · VERSÃO DO APP ANDROID (aviso de atualização). GET /app-version (público, sem dado pessoal):
//   { android: { latest, min, name, url } }
//   latest = versionCode do APK mais novo; min = mais antigo que ainda funciona (abaixo disso o app pede para
//   atualizar e não deixa fechar o aviso); url = link do APK novo (https).
// Configurável no Render sem novo deploy: FRAIHA_ANDROID_LATEST_CODE, FRAIHA_ANDROID_MIN_CODE,
// FRAIHA_ANDROID_LATEST_NAME, FRAIHA_ANDROID_APK_URL. Sem variável: os padrões abaixo.
const DEFAULTS = { latest: 2, min: 1, name: '1.0.1', url: 'https://jogar.fraihaxadrez.com/app/FRAIHA-Xadrez.apk' };

function info(env = process.env) {
  const int = (k, d) => { const v = parseInt(String(env[k] || ''), 10); return Number.isFinite(v) && v > 0 && v < 1e9 ? v : d; };
  const url = String(env.FRAIHA_ANDROID_APK_URL || '').trim();
  const name = String(env.FRAIHA_ANDROID_LATEST_NAME || '').trim();
  return { android: {
    latest: int('FRAIHA_ANDROID_LATEST_CODE', DEFAULTS.latest),
    min: int('FRAIHA_ANDROID_MIN_CODE', DEFAULTS.min),
    name: /^[0-9A-Za-z.\- ]{1,30}$/.test(name) ? name : DEFAULTS.name,
    url: /^https:\/\/[^\s"<>]{4,300}$/.test(url) ? url : DEFAULTS.url,
  } };
}

function owns(req) { const u = String(req.url || ''); return req.method === 'GET' && (u === '/app-version' || u.startsWith('/app-version?')); }

function handle(req, res, env = process.env) {
  res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'public, max-age=60', 'access-control-allow-origin': '*', 'x-content-type-options': 'nosniff' });
  res.end(JSON.stringify(info(env)));
}

module.exports = { info, owns, handle, DEFAULTS };
