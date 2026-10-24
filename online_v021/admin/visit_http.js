'use strict';
// R181 · RASTREAMENTO SEM LOGIN (rota HTTP POST /t). O site do jogo manda, desde o 1º segundo (antes de qualquer
// login), o que a pessoa VÊ e TOCA: tela, botão, carregamento, login escolhido, saída. Só para o Admin → Sessões/Funil.
//
// PRIVACIDADE / SEGURANÇA (pedido do dono):
//   · nada digitado: nome de tela/botão só entra se EXISTIR no código do jogo (admin/ui_names.json, gerado por
//     tools/gerar_nomes_ui.py). E-mail, senha, chat e apelido nunca estão lá → são descartados;
//   · só campos conhecidos, com formato fixo (ids aleatórios hex, números com faixa, códigos curtos); o resto cai fora;
//   · limites: corpo até 8 KB, até 40 eventos por envio, por IP 120 envios/min, por visitante 60/min, no máximo
//     30 visitantes novos por IP por hora e 5000 visitas abertas na memória; acima disso, descarta em silêncio (204).
//   · CORS só para os endereços do jogo (FRAIHA_TRACK_ORIGINS acrescenta outros).
const NAMES = require('./ui_names.json');

const MAX_BODY = 8 * 1024;
const MAX_EVENTS = 40;
const IP_PER_MIN = 120, VID_PER_MIN = 60, NEW_PER_IP_HOUR = 30;
const HEX32 = /^[0-9a-f]{32}$/;
const KINDS = new Set(['screen', 'click', 'load', 'login', 'exit', 'match', 'px', 'hb', 'back']);
const LOGIN_METHODS = { guest: 'convidado', email: 'e-mail', google: 'Google', signup: 'criar conta (e-mail)' };
const LOGIN_RESULTS = new Set(['start', 'ok', 'error']);
const MATCH_MODES = { bot: 'Contra o computador', local: 'Local (2 no aparelho)', online: 'Online (sala)', ranked: 'Ranqueada', casual: 'Casual', xeque: 'Xeque', marcha: 'Marcha Real' };
const RESULTS = { win: 'VITÓRIA', loss: 'derrota', draw: 'empate' };
const PX_EVENTS = new Set(['JogoCarregado', 'EntrouConvidado', 'CompleteRegistration', 'PrimeiraPartida', 'PartidaConcluida']);
const DEFAULT_ORIGINS = ['https://jogar.fraihaxadrez.com', 'https://fraihaxadrez.com', 'https://www.fraihaxadrez.com'];

const norm = s => String(s || '').replace(/\s+/g, ' ').trim().toUpperCase();
const NAME_SET = new Set(NAMES.names);
const PATTERNS = NAMES.patterns.map(p => new RegExp('^' + p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  .replace(/%[-0-9.]*S/g, '[A-ZÀ-Ý0-9 ]{1,30}').replace(/%[-0-9.]*D/g, '[0-9]{1,6}').replace(/%[-0-9.]*F/g, '[0-9]{1,6}(?:\\.[0-9]{1,3})?').replace(/%%/g, '%') + '$'));
// texto limpo (o que aparece no painel): só caracteres comuns de rótulo; nunca @ / dígitos longos
const clean = (s, n = 60) => String(s || '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, n);

// Nome conhecido? Aceita composto "Partida Ranqueada · Resultado da partida" e "Janela: Título".
function knownName(raw) {
  const s = clean(raw, 80);
  if (!s || s.length < 2 || /[@<>{}\\]|\d{5,}|https?:/i.test(s)) return '';
  const one = part => {
    const N = norm(part);
    if (!N) return false;
    if (NAME_SET.has(N)) return true;
    if (N.startsWith('JANELA: ')) return one(part.slice(8));
    return PATTERNS.some(r => r.test(N));
  };
  const parts = s.split(' · ');
  return parts.every(one) ? s : '';
}
const num = (v, lo, hi) => { const n = Number(v); return Number.isFinite(n) && n >= lo && n <= hi ? n : null; };
const code = (v, n = 60) => { const s = String(v || '').replace(/[^A-Za-z0-9 _.:\-()/]/g, '').trim().slice(0, n); return s; };

// Aparelho pelo User-Agent do próprio pedido (não precisa o jogo mandar nada)
function parseUA(ua) {
  ua = String(ua || '');
  const d = {};
  let m;
  if ((m = /Android (\d+(?:\.\d+)?)/.exec(ua))) { d.device = 'Android'; d.os = 'Android ' + m[1]; d.mobile = true; }
  else if ((m = /(iPhone|iPad|iPod).*? OS (\d+)[_.](\d+)/.exec(ua))) { d.device = m[1] === 'iPad' ? 'iPad' : 'iPhone'; d.os = 'iOS ' + m[2] + '.' + m[3]; d.mobile = m[1] !== 'iPad'; }
  else if (/Windows NT/.test(ua)) { d.device = 'PC'; d.os = 'Windows'; d.mobile = false; }
  else if (/Mac OS X/.test(ua)) { d.device = 'PC'; d.os = 'Mac'; d.mobile = false; }
  else if (/CrOS/.test(ua)) { d.device = 'PC'; d.os = 'Chromebook'; d.mobile = false; }
  else if (/Linux/.test(ua)) { d.device = 'PC'; d.os = 'Linux'; d.mobile = false; }
  else d.device = '?';
  if (/Instagram/.test(ua)) d.inapp = 'Instagram';
  else if (/FBAN|FBAV|FB_IAB|FBIOS/.test(ua)) d.inapp = 'Facebook';
  else if (/Barcelona/.test(ua)) d.inapp = 'Threads';
  else if (/TikTok|musical_ly|BytedanceWebview/.test(ua)) d.inapp = 'TikTok';
  if ((m = /SamsungBrowser\/(\d+)/.exec(ua))) d.browser = 'Samsung Internet ' + m[1];
  else if ((m = /Edg\/(\d+)/.exec(ua))) d.browser = 'Edge ' + m[1];
  else if ((m = /(?:OPR|Opera)\/(\d+)/.exec(ua))) d.browser = 'Opera ' + m[1];
  else if ((m = /(?:Firefox|FxiOS)\/(\d+)/.exec(ua))) d.browser = 'Firefox ' + m[1];
  else if ((m = /(?:CriOS|Chrome)\/(\d+)/.exec(ua))) d.browser = 'Chrome ' + m[1];
  else if ((m = /Version\/(\d+).*Safari/.exec(ua))) d.browser = 'Safari ' + m[1];
  if (d.inapp) d.browser = d.inapp + ' (navegador do app)' + (d.browser ? ' · ' + d.browser : '');
  return d;
}

// Um evento cru → { k, l (texto do painel), meta } ou null (descartado)
function parseEvent(e) {
  if (!e || typeof e !== 'object' || Array.isArray(e)) return null;
  const k = String(e.k || ''); if (!KINDS.has(k)) return null;
  const t = num(e.t, 0, 86400e3); if (t === null) return null;
  const out = { k, t };
  if (k === 'screen') { const n = knownName(e.n); if (!n) return null; out.screen = n; return out; }
  if (k === 'click') {
    const b = knownName(e.n) || knownName(e.id); if (!b) return null;
    out.button = b; out.screen = knownName(e.s) || ''; return out;
  }
  if (k === 'load') {
    const n = String(e.n || '');
    if (n === 'start') return { ...out, label: 'Começou a carregar o jogo' };
    if (n === 'done') { const v = num(e.v, 0, 600); return { ...out, loaded: true, label: 'Carregou 100%' + (v !== null ? ` (${v.toFixed(1).replace('.', ',')} s)` : '') }; }
    if (n === 'error') return { ...out, label: 'ERRO no carregamento' + (code(e.c) ? ': ' + code(e.c, 80) : '') };
    if (n === 'slow') { const v = num(e.v, 0, 600); return { ...out, label: `Ainda carregando (${v === null ? '?' : Math.round(v)} s)` }; }
    return null;
  }
  if (k === 'login') {
    const m = LOGIN_METHODS[String(e.n || '')], r = String(e.r || '');
    if (!m || !LOGIN_RESULTS.has(r)) return null;
    const c = code(e.c, 60);
    out.label = r === 'start' ? `Login: escolheu ${m}` : r === 'ok' ? `Login: ${m} — SUCESSO` : `Login: ${m} — ERRO` + (c ? ' (' + c + ')' : '');
    if (r === 'ok') out.passed = true;
    return out;
  }
  if (k === 'exit') {
    const s = knownName(e.s), b = knownName(e.b);
    out.label = 'Saiu / fechou o jogo' + (s ? ' · última tela: ' + s : '') + (b ? ' · último botão: ' + b : '');
    out.exit = true; return out;
  }
  if (k === 'back') return { ...out, label: 'Voltou para o jogo' };
  if (k === 'match') {
    const mode = MATCH_MODES[String(e.m || '')]; if (!mode) return null;
    const bot = /^[a-z_]{2,20}$/.test(String(e.b || '')) ? ' · BOT ' + String(e.b).toUpperCase().replace(/_/g, ' ') : '';
    if (e.n === 'start') return { ...out, played: true, label: `Começou partida: ${mode}${bot}` };
    if (e.n === 'end') return { ...out, label: `Terminou partida: ${mode}${bot} — ${RESULTS[String(e.r)] || 'fim'}` };
    return null;
  }
  if (k === 'px') {
    const n = String(e.n || ''); if (!PX_EVENTS.has(n)) return null;
    const id = String(e.id || ''); if (!/^[0-9a-f]{16,40}$/.test(id)) return null;
    const p = {};
    if (MATCH_MODES[String(e.m || '')]) p.modo = String(e.m);
    if (RESULTS[String(e.r || '')]) p.resultado = String(e.r);
    return { ...out, px: { name: n, id, consent: e.c === true, params: p, fbp: /^fb\.\d\.\d{10,14}\.\d{1,20}$/.test(String(e.fbp || '')) ? String(e.fbp) : '', fbc: /^fb\.\d\.\d{10,14}\.[A-Za-z0-9_-]{8,200}$/.test(String(e.fbc || '')) ? String(e.fbc) : '' } };
  }
  if (k === 'hb') return out;
  return null;
}

function parseUtm(u) {
  const out = {};
  if (!u || typeof u !== 'object') return out;
  for (const [k, src] of [['source', 's'], ['campaign', 'c'], ['medium', 'm']]) {
    const v = String(u[src] || '').trim();
    if (/^[A-Za-z0-9_.\-+ |]{1,60}$/.test(v)) out[k] = v;
  }
  if (u.fb === true) out.fbclid = true;
  out.ad = !!(out.source || out.fbclid);
  return out;
}

class Limiter {
  constructor() { this.m = new Map(); this.at = Date.now(); }
  hit(key, max, windowMs, now) {
    if (now - this.at > 60e3 && this.m.size > 20000) { for (const [k, v] of this.m) if (now - v.t > 3600e3) this.m.delete(k); this.at = now; }
    const r = this.m.get(key);
    if (!r || now - r.t > windowMs) { this.m.set(key, { t: now, n: 1 }); return true; }
    return ++r.n <= max;
  }
}

class VisitHttp {
  constructor({ track, env = process.env, now = () => Date.now(), capi = null }) {
    this.track = track; this.now = now; this.capi = capi;
    this.origins = new Set([...DEFAULT_ORIGINS, ...String(env.FRAIHA_TRACK_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean)]);
    this.devOrigins = String(env.FRAIHA_ENV || '').trim() !== 'production';   // localhost só fora de produção
    this.lim = new Limiter();
    this.stats = { ok: 0, dropped: 0, limited: 0 };
  }
  originOk(o) {
    if (!o) return true;   // sendBeacon/keepalive do mesmo site às vezes vai sem Origin
    if (this.origins.has(o)) return true;
    return this.devOrigins && /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(o);
  }
  // http: (req, res) → trata POST/OPTIONS /t
  handle(req, res, ip) {
    const origin = String(req.headers.origin || '');
    // R182 · app Android: não é navegador (sem Origin/CORS) → se identifica pelo cabeçalho x-fraiha-app
    // R184 · executável do PC (Windows) também
    const appHdr = String(req.headers['x-fraiha-app'] || '');
    const app = !origin && (appHdr === 'android' || appHdr === 'windows') ? appHdr : '';
    const ok = app || this.originOk(origin);
    const head = { 'content-type': 'text/plain', 'cache-control': 'no-store' };
    if (ok && origin) { head['access-control-allow-origin'] = origin; head.vary = 'Origin'; head['access-control-allow-methods'] = 'POST, OPTIONS'; head['access-control-allow-headers'] = 'content-type'; head['access-control-max-age'] = '86400'; }
    if (req.method === 'OPTIONS') { res.writeHead(ok ? 204 : 403, head); return res.end(); }
    if (req.method !== 'POST' || !ok) { res.writeHead(ok ? 405 : 403, head); return res.end(); }
    const now = this.now();
    if (!this.lim.hit('ip:' + ip, IP_PER_MIN, 60e3, now)) { this.stats.limited++; req.resume(); res.writeHead(204, head); return res.end(); }
    let raw = '', big = false;
    req.setEncoding('utf8');
    req.on('data', d => { if (big) return; raw += d; if (raw.length > MAX_BODY) { big = true; raw = ''; } });
    req.on('end', () => {
      res.writeHead(204, head); res.end();
      if (big) { this.stats.dropped++; return; }
      try { this.ingest(raw, { ip, ua: req.headers['user-agent'], app }); } catch (e) { this.stats.dropped++; }
    });
    req.on('error', () => {});
  }
  ingest(raw, { ip = '?', ua = '', app = '' } = {}) {
    let b; try { b = JSON.parse(raw); } catch { this.stats.dropped++; return false; }
    if (!b || typeof b !== 'object' || Array.isArray(b)) { this.stats.dropped++; return false; }
    const sid = String(b.sid || ''), vid = String(b.vid || '');
    if (!HEX32.test(sid) || !HEX32.test(vid)) { this.stats.dropped++; return false; }
    const now = this.now();
    if (!this.lim.hit('vid:' + vid, VID_PER_MIN, 60e3, now)) { this.stats.limited++; return false; }
    const evs = Array.isArray(b.e) ? b.e.slice(0, MAX_EVENTS).map(parseEvent).filter(Boolean) : [];
    const known = this.track.hasVisit(sid);
    if (!known && !this.lim.hit('new:' + ip, NEW_PER_IP_HOUR, 3600e3, now)) { this.stats.limited++; return false; }
    const dev = app === 'android' ? { device: 'Android', os: 'Android', mobile: true, browser: 'APP Android' }
      : app === 'windows' ? { device: 'PC', os: 'Windows', mobile: false, browser: 'APP PC (Windows)' } : parseUA(ua);
    if (app === 'android' && b.d && /^[0-9]{1,2}$/.test(String(b.d.os || ''))) dev.os = 'Android ' + String(b.d.os);
    if (b.d && typeof b.d === 'object') {
      for (const k of ['w', 'h']) { const v = num(b.d[k], 1, 20000); if (v !== null) dev[k] = Math.round(v); }
      if (/^[A-Za-z-]{2,10}$/.test(String(b.d.lang || ''))) dev.lang = String(b.d.lang);
      if (/^[0-9.]{1,10}$/.test(String(b.d.v || ''))) dev.version = String(b.d.v);
    }
    const s = this.track.visit(sid, vid, { utm: parseUtm(b.u), device: dev, start: num(b.st, 0, 86400e3) });
    if (!s) return false;
    for (const e of evs) {
      this.track.visitEvent(s, e);
      if (e.px && this.capi) this.capi.send({ ...e.px, ip, ua: String(ua || '').slice(0, 400), sid, vid }).catch(() => {});
    }
    this.stats.ok++;
    return true;
  }
}

module.exports = { VisitHttp, knownName, parseUA, parseEvent, parseUtm, MAX_BODY, MAX_EVENTS };
