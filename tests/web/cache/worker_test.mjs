// FRAIHA R55.5 · teste do Worker do site (web/cdn/fraiha-web-worker.mjs) sobre um R2 falso.
// Uso: node tests/web/cache/worker_test.mjs   (sem dependências)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const mod = await import(path.join(here, "../../../web/cdn/fraiha-web-worker.mjs"));
const worker = mod.default;
const { FakeR2 } = await import(path.join(here, "fake_r2.mjs"));
let failures = 0;
const check = (ok, label) => { console.log((ok ? "PASS " : "FAIL ") + label); if (!ok) failures++; };

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "fraiha_r2_"));
const put = (k, data) => { fs.mkdirSync(path.dirname(path.join(dir, k)), { recursive: true }); fs.writeFileSync(path.join(dir, k), data); };
const PCK = "index-p0123456789abcdef.pck", WASM = "index-e0123456789abcdef.wasm", JS = "index-e0123456789abcdef.js";
put("index.html", "<html>v1</html>");
put(PCK, Buffer.alloc(1000, 7));
put(WASM, Buffer.alloc(500, 1));
put(JS, "console.log(1)");
put("engines/stockfish-19-lite-single.wasm", Buffer.alloc(50, 2));
put("index.pck", Buffer.alloc(10, 3));
const env = { BUCKET: new FakeR2(dir) };
const go = (p, init = {}) => worker.fetch(new Request("https://jogar.fraihaxadrez.com" + p, init), env);

let r = await go("/");
check(r.status === 200 && (await r.text()) === "<html>v1</html>", "/ serve o index.html");
check(r.headers.get("cache-control") === "no-cache" && r.headers.get("etag"), "index.html: no-cache + ETag");
check(r.headers.get("content-type").startsWith("text/html"), "index.html: text/html");
const et = r.headers.get("etag");
r = await go("/index.html", { headers: { "if-none-match": et } });
check(r.status === 304 && r.body === null, "index.html igual: 304 sem corpo");
r = await go("/index.html", { headers: { "if-none-match": '"outro"' } });
check(r.status === 200, "index.html mudou (ETag diferente): 200");

r = await go("/" + PCK);
check(r.status === 200 && r.headers.get("cache-control") === "public, max-age=31536000, immutable", "PCK com SHA no nome: immutable 1 ano");
check(r.headers.get("content-length") === "1000" && (await r.arrayBuffer()).byteLength === 1000, "PCK: Content-Length exato");
check(r.headers.get("content-type") === "application/octet-stream" && r.headers.get("accept-ranges") === "bytes", "PCK: tipo e Accept-Ranges");
r = await go("/" + WASM);
check(r.headers.get("content-type") === "application/wasm" && /immutable/.test(r.headers.get("cache-control")), "WASM: application/wasm + immutable");
r = await go("/" + JS);
check(r.headers.get("content-type").startsWith("text/javascript") && /immutable/.test(r.headers.get("cache-control")), "JS do motor: immutable");

r = await go("/" + PCK, { headers: { range: "bytes=100-199" } });
check(r.status === 206 && r.headers.get("content-range") === "bytes 100-199/1000" && r.headers.get("content-length") === "100" && (await r.arrayBuffer()).byteLength === 100, "Range: 206 com Content-Range");
r = await go("/" + PCK, { headers: { range: "bytes=-10" } });
check(r.status === 206 && r.headers.get("content-range") === "bytes 990-999/1000", "Range sufixo: 206");
const pe = (await go("/" + PCK, { method: "HEAD" })).headers.get("etag");
r = await go("/" + PCK, { headers: { "if-none-match": pe } });
check(r.status === 304, "PCK com If-None-Match igual: 304");

r = await go("/engines/stockfish-19-lite-single.wasm");
check(r.status === 200 && r.headers.get("cache-control") === "no-cache", "engines/: nome fixo → no-cache (revalida com ETag)");
r = await go("/index.pck");
check(r.headers.get("cache-control") === "no-cache", "index.pck legado: nunca immutable (nome não identifica conteúdo)");
r = await go("/sub/" + PCK.replace("index-p", "index-p"));
check(r.status === 404 && r.headers.get("cache-control") === "no-store", "arquivo inexistente: 404 no-store");
r = await go("/index-pffffffffffffffff.pck");
check(r.status === 404 && r.headers.get("cache-control") === "no-store", "PCK ainda não enviado: 404 no-store (não fica em cache)");
r = await go("/" + PCK, { method: "HEAD" });
check(r.status === 200 && r.body === null && r.headers.get("content-length") === "1000", "HEAD: tamanho sem corpo");
r = await go("/index.html", { method: "POST" });
check(r.status === 405, "POST: 405");
r = await go("/%2e%2e/segredo");
check(r.status === 400 || r.status === 404, "caminho com .. não sai do bucket");

check(mod.cachePolicy("index-e0123456789abcdef.audio.worklet.js") === mod.CC_IMMUTABLE, "worklet do motor: immutable");
check(mod.cachePolicy("index-s0123456789abcdef.png") === mod.CC_IMMUTABLE, "splash: immutable");
check(mod.cachePolicy("index-p0123.pck") === mod.CC_REVALIDATE, "hash curto não conta como impressão digital");
check(mod.cachePolicy("voice/index-p0123456789abcdef.pck") === mod.CC_REVALIDATE, "só a raiz do bucket tem nomes immutable");

fs.rmSync(dir, { recursive: true, force: true });
console.log("RESULT", failures === 0 ? "OK" : "FALHAS=" + failures);
process.exit(failures ? 1 : 0);
