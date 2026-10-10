// FRAIHA R55.5 · mede carga fria / reload / nova aba / hard reload / troca de versão no Chromium
// contra o simulador (tests/web/cache/sim_server.mjs). Só local, nada é publicado.
//
//   NODE_PATH=<node_modules com playwright-core> node tests/web/cache/measure_cache.cjs \
//       <modo legado|worker> <bucket_v1> <bucket_v2> <saida.json> [mbps=50] [rtt_ms=80]
//
// "Tela utilizável" = o Godot terminou de iniciar e removeu a tela de carregamento (#status).
// Bytes = corpo realmente enviado pelo servidor (log do simulador) + origem de cada resposta no navegador
// (rede / cache HTTP do disco / Cache Storage do index.html).
const { chromium } = require("playwright-core");
const { spawn } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const [mode, b1, b2, outFile, mbpsArg, rttArg] = process.argv.slice(2);
const MBPS = Number(mbpsArg || 50), RTT = Number(rttArg || 80);
const PORT = 8900 + (mode === "legado" ? 1 : 2);
const BASE = `http://127.0.0.1:${PORT}/`;
const LOG = path.join(os.tmpdir(), `fraiha_sim_${mode}_${process.pid}.jsonl`);
const CHROME = process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome";

function serverLog() {
  try { return fs.readFileSync(LOG, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse); } catch { return []; }
}

async function throttle(page) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Network.enable");
  if (MBPS > 0) {
    await cdp.send("Network.emulateNetworkConditions", {
      offline: false, latency: RTT, downloadThroughput: (MBPS * 1e6) / 8, uploadThroughput: (10 * 1e6) / 8,
    });
  }
  const seen = [];
  cdp.on("Network.responseReceived", (e) => {
    const u = e.response.url.replace(BASE, "/");
    seen.push({ url: u, status: e.response.status, disk: !!e.response.fromDiskCache, mem: !!e.response.fromMemoryCache,
      sw: !!e.response.fromServiceWorker, cc: e.response.headers["cache-control"] || e.response.headers["Cache-Control"] || null });
  });
  return { cdp, seen };
}

async function usable(page, t0) {
  await page.waitForFunction(() => typeof engine !== "undefined" && document.getElementById("canvas") && !document.getElementById("status"), null, { timeout: 600000, polling: 100 });
  return Date.now() - t0;
}

async function info(page) {
  return page.evaluate(() => ({
    exe: typeof GODOT_CONFIG !== "undefined" ? GODOT_CONFIG.executable : null,
    pack: typeof GODOT_CONFIG !== "undefined" ? (GODOT_CONFIG.mainPack || GODOT_CONFIG.executable + ".pck") : null,
    cache: window.__fraihaCache ? JSON.parse(JSON.stringify(window.__fraihaCache)) : null,
  }));
}

async function waitStored(page) {
  for (let i = 0; i < 240; i++) {
    const c = await page.evaluate(() => { const s = window.__fraihaCache; return s ? (s.misses.length === 0 ? 1 : s.stored.length + s.errors.length) : -1; });
    if (c !== 0) return;               // sem cache local (legado), acerto, ou cópia gravada/falhou
    await page.waitForTimeout(500);
  }
}

function summarize(name, t0, t1, ms, seen, inf) {
  const reqs = serverLog().filter((r) => r.t >= t0 && r.t <= t1);
  const bytes = reqs.reduce((a, r) => a + r.bytes, 0);
  const big = reqs.filter((r) => /\.(pck|wasm)(\?|$)/.test(r.path)).map((r) => `${r.path} ${r.status} ${(r.bytes / 1e6).toFixed(2)}MB${r.ce ? " " + r.ce : ""}${r.inm ? " (If-None-Match)" : ""}`);
  const st = {};
  for (const r of reqs) st[r.status] = (st[r.status] || 0) + 1;
  const browser = { rede: 0, disco: 0, memoria: 0 };
  for (const s of seen) { if (s.disk) browser.disco++; else if (s.mem) browser.memoria++; else browser.rede++; }
  // nunca misturar release: todo pedido de motor/pacote tem que ser o que ESTE index.html cita
  const engineReqs = reqs.filter((x) => /\.(pck|wasm)(\?|$)|^\/index[^/]*\.js(\?|$)/.test(x.path) && !/reload_diag/.test(x.path));
  const misturou = engineReqs.filter((x) => { const n = x.path.split("?")[0].slice(1); return !(n === inf.pack || n.startsWith(inf.exe + ".")); }).map((x) => x.path);
  const r = { cenario: name, misturou, ms_tela_utilizavel: ms, bytes_servidor: bytes, mb_servidor: +(bytes / 1e6).toFixed(2), pedidos_servidor: reqs.length,
    status: st, grandes: big, navegador: browser, exe: inf.exe, pack: inf.pack, cache_local: inf.cache,
    respostas: seen.map((s) => `${s.status} ${s.disk ? "disco" : s.mem ? "memória" : "rede"} ${s.url}${s.cc ? " [" + s.cc + "]" : ""}`) };
  console.log(`${name}: ${(ms / 1000).toFixed(1)} s · ${r.mb_servidor} MB do servidor · ${reqs.length} pedidos ${JSON.stringify(st)} · ${big.join(" | ")} · cache local ${JSON.stringify(inf.cache && { hits: inf.cache.hits, misses: inf.cache.misses })}`);
  return r;
}

(async () => {
  const sim = spawn(process.execPath, [path.join(__dirname, "sim_server.mjs"), b1, String(PORT), mode, LOG], { stdio: "inherit" });
  await new Promise((r) => setTimeout(r, 1500));
  // perfil num disco com espaço livre normal (o Chrome reduz cache/armazenamento quando o disco está quase cheio)
  const profile = fs.mkdtempSync(path.join(process.env.PROFILE_DIR || os.tmpdir(), "fraiha_prof_"));
  const ctx = await chromium.launchPersistentContext(profile, {
    executablePath: CHROME, headless: true, viewport: { width: 960, height: 540 },
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--autoplay-policy=no-user-gesture-required"],
  });
  const results = [];
  let page = ctx.pages()[0] || (await ctx.newPage());
  let net = await throttle(page);

  async function run(name, action, after) {
    net.seen.length = 0;
    const t0 = Date.now();
    await action();
    const ms = await usable(page, t0);
    await waitStored(page);
    const inf = await info(page);
    await page.waitForTimeout(1500);
    const r = summarize(name, t0, Date.now(), ms, net.seen.slice(), inf);
    if (after) after(r);
    results.push(r);
  }

  await run("1 carga fria", () => page.goto(BASE + (process.env.URL_SUFFIX || ""), { waitUntil: "commit" }));
  if (process.env.ONLY_COLD === "1") { await ctx.close(); sim.kill(); fs.writeFileSync(outFile, JSON.stringify({ modo: mode, mbps: MBPS, rtt_ms: RTT, resultados: results }, null, 1)); try { fs.rmSync(profile, { recursive: true, force: true }); if (!process.env.KEEP_LOG) fs.rmSync(LOG, { force: true }); else console.log("log", LOG); } catch {} return; }
  await run("2 reload normal", () => page.reload({ waitUntil: "commit" }));
  await page.close();
  page = await ctx.newPage(); net = await throttle(page);
  await run("3 nova aba", () => page.goto(BASE, { waitUntil: "commit" }));
  await run("4 reload com cache aquecido", () => page.reload({ waitUntil: "commit" }));
  await run("5 hard reload (Ctrl+Shift+R)", () => net.cdp.send("Page.reload", { ignoreCache: true }));
  // troca de versão: o bucket passa a ter o release 2 (index.html novo)
  await fetch(BASE + "__sim/bucket?dir=" + encodeURIComponent(b2), { method: "POST" });
  await run("6 versão nova publicada (reload normal)", () => page.reload({ waitUntil: "commit" }));
  await run("7 reload na versão nova", () => page.reload({ waitUntil: "commit" }));
  await page.waitForTimeout(65000);          // limpeza do cache local roda 60 s depois do load
  const chaves = await page.evaluate(async () => (window.caches ? (await (await caches.open("fraiha-assets-v1")).keys()).map((k) => k.url.split("/").pop()) : null));
  console.log("cache local depois da limpeza:", JSON.stringify(chaves));
  results.push({ cenario: "8 limpeza do release antigo", chaves });
  await ctx.close();
  sim.kill();
  const cachePck = results.filter((r) => r.pack).map((r) => r.pack);
  const mix = results.filter((r) => r.misturou && r.misturou.length);
  console.log(mix.length ? "MISTUROU RELEASE: " + JSON.stringify(mix.map((r) => [r.cenario, r.misturou])) : "SEM MISTURA de release em nenhum cenário");
  fs.writeFileSync(outFile, JSON.stringify({ modo: mode, mbps: MBPS, rtt_ms: RTT, b1, b2, resultados: results }, null, 1));
  try { fs.rmSync(profile, { recursive: true, force: true }); if (!process.env.KEEP_LOG) fs.rmSync(LOG, { force: true }); else console.log("log", LOG); } catch {}
  console.log("FIM", mode, cachePck.join(" -> "));
})().catch((e) => { console.error("ERRO", e); process.exit(1); });
