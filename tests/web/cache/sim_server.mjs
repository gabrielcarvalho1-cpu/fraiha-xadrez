// FRAIHA R55.5 · simulador LOCAL da publicação Web (bucket R2 + Worker + borda Cloudflare).
// Só para teste: não fala com Cloudflare, não publica nada.
//
//   node tests/web/cache/sim_server.mjs <pasta_bucket> <porta> <modo> <log.jsonl>
//
// modo "legado": imita o site atual medido pelo Orca: Cache-Control: no-cache, If-None-Match → 200
//                (nunca 304) e Range ignorado (sempre 200 com o arquivo inteiro).
// modo "worker": roda web/cdn/fraiha-web-worker.mjs de verdade sobre um R2 falso (pasta local).
// Nos dois modos a "borda" comprime em Brotli o que a Cloudflare comprime (html/js/wasm/txt) quando o
// navegador aceita br; .pck (application/octet-stream) não é comprimido, como no site.
// Cada resposta vira uma linha no log: método, caminho, status, bytes de corpo enviados, cabeçalhos.
// POST /__sim/bucket?dir=<pasta> troca a pasta do bucket (simula upload de release novo).
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { Readable } from "node:stream";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const worker = (await import(path.join(here, "../../../web/cdn/fraiha-web-worker.mjs"))).default;
const { FakeR2 } = await import(path.join(here, "fake_r2.mjs"));
let [, , bucketDir, port, mode, logFile] = process.argv;
port = Number(port);
const brCache = new Map();

function legacy(req, bucket) {
  // site atual: sempre 200 inteiro, no-cache, ignora If-None-Match e Range
  let key = decodeURIComponent(new URL(req.url, "http://x").pathname).replace(/^\/+/, "");
  if (key === "" || key.endsWith("/")) key += "index.html";
  const o = bucket._stat(key);
  if (!o) return new Response("Not found", { status: 404 });
  const ext = key.split(".").pop();
  const types = { html: "text/html", js: "application/javascript", wasm: "application/wasm", pck: "application/octet-stream", png: "image/png", txt: "text/plain" };
  const headers = { "cache-control": "no-cache", etag: o.httpEtag, "content-type": types[ext] || "application/octet-stream", "content-length": String(o.size) };
  return new Response(req.method === "HEAD" ? null : Readable.toWeb(fs.createReadStream(o.file)), { status: 200, headers });
}

const COMPRESSIBLE = /^(text\/|application\/(javascript|wasm|json))/;

const server = http.createServer(async (req, res) => {
  const t0 = Date.now();
  if (req.method === "POST" && req.url.startsWith("/__sim/bucket")) {
    bucketDir = new URL(req.url, "http://x").searchParams.get("dir");
    res.end("ok " + bucketDir);
    return;
  }
  const bucket = new FakeR2(bucketDir);
  const headers = new Headers();
  for (const [k, v] of Object.entries(req.headers)) headers.set(k, Array.isArray(v) ? v.join(", ") : v);
  const request = new Request("http://127.0.0.1:" + port + req.url, { method: req.method, headers });
  let resp;
  try {
    resp = mode === "legado" ? legacy(req, bucket) : await worker.fetch(request, { BUCKET: bucket });
  } catch (e) {
    resp = new Response("erro " + e, { status: 500 });
  }
  const out = {};
  resp.headers.forEach((v, k) => { out[k] = v; });
  let body = resp.body;
  const ae = String(req.headers["accept-encoding"] || "");
  if (resp.status === 200 && body && req.method === "GET" && /\bbr\b/.test(ae) && COMPRESSIBLE.test(out["content-type"] || "")) {
    const key = req.url.split("?")[0] + "|" + out.etag;
    if (!brCache.has(key)) {
      const raw = Buffer.from(await resp.arrayBuffer());
      brCache.set(key, zlib.brotliCompressSync(raw, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 5 } }));
    } else { await resp.body.cancel(); }
    const enc = brCache.get(key);
    out["content-encoding"] = "br";
    out["content-length"] = String(enc.length);
    out.vary = "accept-encoding";
    body = Readable.toWeb(Readable.from([enc]));
  }
  res.writeHead(resp.status, out);
  let bytes = 0;
  if (body && req.method !== "HEAD") {
    const node = Readable.fromWeb(body);
    node.on("data", (c) => { bytes += c.length; });
    await new Promise((ok) => { node.pipe(res); res.on("close", ok); });
  } else res.end();
  fs.appendFileSync(logFile, JSON.stringify({
    t: t0, ms: Date.now() - t0, method: req.method, path: req.url, status: resp.status, bytes,
    inm: req.headers["if-none-match"] || null, range: req.headers.range || null,
    cc: out["cache-control"] || null, ce: out["content-encoding"] || null,
  }) + "\n");
});
server.listen(port, "127.0.0.1", () => console.log(`sim ${mode} em http://127.0.0.1:${port}/ bucket=${bucketDir}`));
