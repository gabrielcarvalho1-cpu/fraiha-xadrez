'use strict';
// FRAIHA Admin · serve o FRONTEND do Admin (pasta admin/ do repositório) em /admin/ no MESMO servidor Node.
// Só arquivos estáticos; a API continua em /admin/api/* (AdminService, tratada ANTES deste módulo).
//
// Segurança:
// - os arquivos são lidos UMA vez na inicialização para um mapa em memória (caminho exato → conteúdo);
//   a requisição só faz lookup nesse mapa: não há acesso ao disco por request, nem path traversal,
//   nem listagem de diretório, nem symlink seguido;
// - só entram .html/.css/.js da pasta admin/ (fora: package.json, .gdignore, arquivos ocultos);
// - desligado (404) quando o Admin está desligado (sem FRAIHA_ADMIN_USERS): produção sem a variável
//   não mostra nem a tela;
// - só GET/HEAD; cabeçalhos de segurança (CSP, nosniff, sem iframe, sem referrer).
// O Admin usa rotas por hash (#/filas), então recarregar qualquer tela sempre pede /admin/ (sem fallback).
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..', 'admin');
const TYPES = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8' };
const CSP = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; " +
  "connect-src 'self' http://127.0.0.1:8140 https://fraiha-xadrez-staging.onrender.com https://fraiha-xadrez.onrender.com https://*.supabase.co; " +
  "base-uri 'none'; form-action 'none'; frame-ancestors 'none'; object-src 'none'";

function loadFiles(root = ROOT) {
  const files = new Map();
  const walk = (dir, rel) => {
    let entries = [];
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (e.name.startsWith('.')) continue;                       // .gdignore e ocultos
      const abs = path.join(dir, e.name), r = rel + '/' + e.name;
      if (e.isSymbolicLink()) continue;                            // nunca segue symlink
      if (e.isDirectory()) { walk(abs, r); continue; }
      const type = TYPES[path.extname(e.name).toLowerCase()];
      if (!e.isFile() || !type) continue;                          // package.json etc. ficam de fora
      files.set('/admin' + r, { body: fs.readFileSync(abs), type });
    }
  };
  walk(root, '');
  const index = files.get('/admin/index.html');
  if (index) files.set('/admin/', index);
  return files;
}

class AdminStatic {
  constructor({ enabled, root = ROOT } = {}) {
    this.enabled = typeof enabled === 'function' ? enabled : () => false;
    this.files = loadFiles(root);
  }
  // /admin e /admin/* — exceto a API (/admin/api…), que o servidor entrega ao AdminService antes.
  owns(req) {
    const u = String(req.url || '');
    if (u === '/admin/api' || u.startsWith('/admin/api/') || u.startsWith('/admin/api?')) return false;
    return u === '/admin' || u.startsWith('/admin/') || u.startsWith('/admin?');
  }
  handle(req, res) {
    const headers = { 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'X-Frame-Options': 'DENY', 'Cache-Control': 'no-cache' };
    const text = (status, msg, extra = {}) => { res.writeHead(status, { ...headers, 'Content-Type': 'text/plain; charset=utf-8', ...extra }); res.end(req.method === 'HEAD' ? undefined : msg); };
    if (!this.enabled()) return text(404, 'Not found\n');
    if (req.method !== 'GET' && req.method !== 'HEAD') return text(405, 'Method not allowed\n', { Allow: 'GET, HEAD' });
    const raw = String(req.url || '');
    const q = raw.indexOf('?');
    const p = q >= 0 ? raw.slice(0, q) : raw;
    if (p === '/admin') return text(301, 'Moved\n', { Location: '/admin/' + (q >= 0 ? raw.slice(q) : '') });
    const f = this.files.get(p);   // caminho EXATO; "..", "%2e", "//", "\" etc. simplesmente não existem no mapa
    if (!f) return text(404, 'Not found\n');
    res.writeHead(200, { ...headers, 'Content-Type': f.type, 'Content-Length': f.body.length, ...(f.type.startsWith('text/html') ? { 'Content-Security-Policy': CSP } : {}) });
    res.end(req.method === 'HEAD' ? undefined : f.body);
  }
}

module.exports = { AdminStatic, loadFiles };
