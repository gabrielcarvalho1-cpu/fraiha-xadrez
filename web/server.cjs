// Local static preview only. No game backend or public listener.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = __dirname;
const mime = {'.html':'text/html; charset=utf-8','.js':'application/javascript','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.svg':'image/svg+xml'};
http.createServer((req,res) => {
  res.setHeader('Cross-Origin-Opener-Policy','same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy','require-corp');
  res.setHeader('Cache-Control','no-store');
  try {
    const name = decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname);
    const file = path.resolve(root,'.'+(name === '/' ? '/index.html' : name));
    if (!file.startsWith(root+path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404);res.end();return; }
    res.setHeader('Content-Type',mime[path.extname(file)] || 'application/octet-stream');
    res.setHeader('Content-Length',fs.statSync(file).size);
    fs.createReadStream(file).pipe(res);
  } catch { res.writeHead(400);res.end(); }
}).listen(8129,'127.0.0.1',()=>console.log('FRAIHA Web Alpha: http://127.0.0.1:8129 — mantenha esta janela aberta. Ctrl+C encerra.'));
