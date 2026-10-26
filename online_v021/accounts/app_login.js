'use strict';
// R182 · LOGIN COM GOOGLE NO APP ANDROID (fluxo PKCE do Supabase; o servidor NUNCA vê senha nem token).
//
//   1. O app gera um código de pareamento aleatório (c, 32 hex) e um code_verifier secreto (fica só no app).
//   2. Abre o navegador do celular em  SUPABASE/auth/v1/authorize?provider=google&code_challenge=…&redirect_to=
//      https://<este servidor>/app-login/done?c=<c>
//   3. O Google/Supabase devolve o navegador para  /app-login/done?c=<c>&code=<auth_code>. Esta rota guarda o
//      auth_code (NÃO é um token: sem o code_verifier, que só o app tem, ele não serve para nada) por 10 min e
//      mostra "Pronto! Volte para o app".
//   4. O app pergunta  GET /app-login/claim?c=<c>  → recebe o auth_code UMA vez e troca direto com o Supabase
//      (grant_type=pkce + code_verifier) pela sessão.
//
// Pré-requisito (painel do Supabase → Authentication → URL Configuration → Redirect URLs):
//   https://<servidor>/app-login/done**   (sem isso o Supabase manda o navegador para o site do jogo e o app não recebe)
//
// Limites: c/code em formato fixo; 1ª gravação vale (ninguém troca o código depois); 10 min; até 5000 pendentes;
// por IP 30 pedidos/min. Sem log de c/code.
const { Window } = require('../net_guard');

const TTL_MS = 10 * 60e3;
const MAX_PENDING = 5000;
const HEX32 = /^[0-9a-f]{32}$/;
const AUTH_CODE = /^[A-Za-z0-9_-]{8,200}$/;   // uuid do Supabase (com hífens) ou formatos parecidos
const ERR_CODE = /^[a-z_]{2,60}$/;

// R184d · Android: depois do Google o navegador volta SOZINHO para o app (fraihaxadrez://login, intent-filter no APK
// 1.0.2+). Se o app não abrir (APK antigo, outro navegador), o Chrome cai em /app-login/pronto, que mostra o aviso
// e um botão VOLTAR PARA O APP. PC (Windows) e outros: a página de sempre.
const APP_PACKAGE = 'com.fraihaxadrez.app';
const isAndroid = req => /Android/i.test(String((req.headers && req.headers['user-agent']) || ''));
// R193 · app de iPhone: o Safari não abre o app sozinho por redirecionamento; a página mostra o botão VOLTAR PARA O APP
const isIOS = req => /iPhone|iPad|iPod/i.test(String((req.headers && req.headers['user-agent']) || ''));
const IOS_BTN = `<p style="margin-top:22px"><a href="fraihaxadrez://login" style="display:inline-block;padding:14px 22px;border-radius:10px;background:#e9b23a;color:#2a1a04;font-weight:bold;text-decoration:none;letter-spacing:1px">VOLTAR PARA O APP</a></p>`;
const hostOf = req => { const h = String((req.headers && (req.headers['x-forwarded-host'] || req.headers.host)) || '').split(',')[0].trim(); return /^[a-z0-9.-]+(:\d+)?$/i.test(h) ? h : ''; };
const intentUrl = fallback => 'intent://login#Intent;scheme=fraihaxadrez;package=' + APP_PACKAGE + ';' + (fallback ? 'S.browser_fallback_url=' + encodeURIComponent(fallback) + ';' : '') + 'end';
const BACK_BTN = `<p style="margin-top:22px"><a href="${intentUrl('')}" style="display:inline-block;padding:14px 22px;border-radius:10px;background:#e9b23a;color:#2a1a04;font-weight:bold;text-decoration:none;letter-spacing:1px">VOLTAR PARA O APP</a></p>`;

const PAGE = (title, text) => `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>FRAIHA Xadrez</title><style>
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0b0907;color:#efe3c4;
font-family:Georgia,'Times New Roman',serif;text-align:center}
.c{max-width:420px;padding:32px 24px;border:2px solid #b8913f;border-radius:14px;background:#17110b;margin:16px}
h1{color:#f4ce7f;font-size:26px;letter-spacing:1px;margin:0 0 14px}p{font-size:18px;line-height:1.45;margin:0}
</style></head><body><div class="c"><h1>${title}</h1><p>${text}</p></div></body></html>`;

class AppLogin {
  constructor({ now = () => Date.now() } = {}) {
    this.now = now;
    this.map = new Map();   // c -> { code, err, at }
    this.lim = new Window({ windowMs: 60e3, max: 30, maxKeys: 20000, now });
    this.stats = { done: 0, claimed: 0, limited: 0 };
  }
  owns(req) {
    const u = String(req.url || '');
    return req.method === 'GET' && (u.startsWith('/app-login/done') || u.startsWith('/app-login/claim') || u.startsWith('/app-login/pronto'));
  }
  prune(t = this.now()) {
    for (const [k, v] of this.map) if (t - v.at > TTL_MS) this.map.delete(k);
  }
  // guarda o resultado do Google para o pareamento c (a 1ª gravação vale)
  store(c, code, err) {
    if (!HEX32.test(c)) return false;
    if (code && !AUTH_CODE.test(code)) return false;
    if (err && !ERR_CODE.test(err)) err = 'erro';
    if (!code && !err) return false;
    const t = this.now();
    this.prune(t);
    if (this.map.has(c)) return false;
    if (this.map.size >= MAX_PENDING) return false;
    this.map.set(c, { code: code || '', err: err || '', at: t });
    this.stats.done++;
    return true;
  }
  // o app busca (uma vez só)
  claim(c) {
    if (!HEX32.test(c)) return { error: 'bad_request' };
    const t = this.now();
    const v = this.map.get(c);
    if (!v || t - v.at > TTL_MS) { if (v) this.map.delete(c); return { pending: true }; }
    this.map.delete(c);
    this.stats.claimed++;
    return v.code ? { code: v.code } : { error: v.err || 'erro' };
  }
  handle(req, res, ip = '?') {
    const head = { 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer' };
    if (!this.lim.hit('ip:' + ip)) { this.stats.limited++; res.writeHead(429, { ...head, 'content-type': 'text/plain' }); return res.end('slow down'); }
    let q;
    try { q = new URL(String(req.url), 'http://x').searchParams; } catch { res.writeHead(400, head); return res.end(); }
    const c = String(q.get('c') || '');
    if (String(req.url).startsWith('/app-login/claim')) {
      const r = this.claim(c);
      res.writeHead(r.error === 'bad_request' ? 400 : 200, { ...head, 'content-type': 'application/json' });
      return res.end(JSON.stringify(r));
    }
    if (String(req.url).startsWith('/app-login/pronto')) {
      res.writeHead(200, { ...head, 'content-type': 'text/html; charset=utf-8', 'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'" });
      return res.end(PAGE('PRONTO!', 'Login com Google feito.<br><br><b>Volte para o app FRAIHA Xadrez</b> — ele entra sozinho na sua conta.' + BACK_BTN));
    }
    const code = String(q.get('code') || '');
    const err = String(q.get('error') || '');
    const ok = this.store(c, code, code ? '' : (err || 'sem_codigo'));
    const host = hostOf(req);
    if (ok && code && isAndroid(req) && host) {
      res.writeHead(302, { ...head, location: intentUrl('https://' + host + '/app-login/pronto') });
      return res.end();
    }
    res.writeHead(200, { ...head, 'content-type': 'text/html; charset=utf-8', 'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'" });
    if (ok && code) return res.end(PAGE('PRONTO!', 'Login com Google feito.<br><br><b>Volte para o app FRAIHA Xadrez</b> — ele entra sozinho na sua conta.' + (isIOS(req) ? IOS_BTN : '')));
    if (ok) return res.end(PAGE('NÃO DEU CERTO', 'O Google não completou o login.<br><br>Volte para o app FRAIHA Xadrez e tente de novo.'));
    return res.end(PAGE('LINK EXPIRADO', 'Este link de login já foi usado ou expirou.<br><br>Volte para o app FRAIHA Xadrez e toque em Google de novo.'));
  }
}

module.exports = { AppLogin, TTL_MS, intentUrl };
