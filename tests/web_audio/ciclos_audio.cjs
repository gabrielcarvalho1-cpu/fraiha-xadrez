'use strict';
// R99 · Ciclos de memória do áudio Web no export REAL (Chromium headless, SwiftShader, celular 390x844 DPR 2).
// Uso: node tests/web_audio/ciclos_audio.cjs <pasta_do_export> <ciclos> <saida.json> [rotulo]
// A instrumentação existe só na resposta deste servidor local (o export não é alterado):
//   · GodotAudio e o tamanho do heap WASM ficam visíveis para medir;
//   · cada start_sample confere se a amostra existe (amostra ausente = som quebrado → falha).
// Mede por ciclo: GodotAudio.samples (quantidade e bytes PCM), SampleNode ativos, heap JS (após GC), WASM,
// memória privada do processo renderer e partition_alloc/array_buffer (dump memory-infra do Chrome).
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const [dir, cyclesArg, outPath, label = 'run'] = process.argv.slice(2);
const cycles = Number(cyclesArg || 20);
const driver = fs.readFileSync(path.join(__dirname, 'ciclo_driver.gd'));
const html0 = fs.readFileSync(path.join(dir, 'index.html'), 'utf8');
const js0 = fs.readFileSync(path.join(dir, 'index.js'), 'utf8');
const need = (s, k) => { if (s.split(k).length !== 2) throw Error('instrumentação: trecho não encontrado uma vez: ' + k); };
need(html0, 'engine.startGame({'); need(js0, 'var GodotAudio={'); need(js0, 'var GL={');
const html = html0.replace('engine.startGame({', "(async function t(o){window.__total=" + cycles + ";await engine.preloadFile('/ciclo_driver.gd','/ciclo_driver.gd');return engine.startGame({...o,args:['--script','/ciclo_driver.gd']});})({");
const js = js0.replace('var GodotAudio={', 'var GodotAudio=globalThis.__ga={').replace('var GL={', 'globalThis.__wasmBytes=()=>HEAPU8.byteLength;var GL={');
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
const MiB = n => +(n / 1048576).toFixed(2);

const server = http.createServer((q, r) => {
  const rel = decodeURIComponent(q.url.split('?')[0]).replace(/^\//, '') || 'index.html';
  r.setHeader('Cross-Origin-Opener-Policy', 'same-origin'); r.setHeader('Cross-Origin-Embedder-Policy', 'require-corp'); r.setHeader('Cache-Control', 'no-store');
  if (rel === 'index.html') { r.setHeader('Content-Type', 'text/html'); return r.end(html); }
  if (rel === 'index.js') { r.setHeader('Content-Type', 'application/javascript'); return r.end(js); }
  if (rel === 'ciclo_driver.gd') return r.end(driver);
  const f = path.join(dir, rel);
  if (rel.includes('..') || !fs.existsSync(f)) { r.writeHead(404); return r.end(); }
  r.setHeader('Content-Type', types[path.extname(f)] || 'application/octet-stream');
  fs.createReadStream(f).pipe(r);
});

function privateMiB(pid) {
  try {
    const t = fs.readFileSync(`/proc/${pid}/smaps_rollup`, 'utf8');
    const kb = k => Number((t.match(new RegExp('^' + k + ':\\s+(\\d+)', 'm')) || [0, 0])[1]);
    return MiB((kb('Private_Clean') + kb('Private_Dirty')) * 1024);
  } catch (e) { return null; }
}

(async () => {
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--autoplay-policy=no-user-gesture-required', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--enable-precise-memory-info'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1' });
  await ctx.route('**/*', rt => { const u = new URL(rt.request().url()); return u.hostname === '127.0.0.1' || ['blob:', 'data:'].includes(u.protocol) ? rt.continue() : rt.abort(); });
  const page = await ctx.newPage();
  const events = [];
  page.on('pageerror', e => events.push({ type: 'pageerror', message: e.message.slice(0, 300) }));
  page.on('console', m => { if (m.type() === 'error') events.push({ type: 'console_error', message: m.text().slice(0, 300) }); });
  page.on('crash', () => events.push({ type: 'crash' }));
  if (process.env.DEBUG_CONSOLE) page.on('console', m => console.log('C', m.text().slice(0, 200)));
  const cdp = await ctx.newCDPSession(page);
  const bcdp = await browser.newBrowserCDPSession();
  await cdp.send('HeapProfiler.enable');
  const dumps = [];
  bcdp.on('Tracing.dataCollected', e => { for (const it of e.value || []) if (it.ph === 'v' && it.args && it.args.dumps) dumps.push(it); });
  await bcdp.send('Tracing.start', { categories: 'memory-infra,disabled-by-default-memory-infra', options: 'recordContinuously', transferMode: 'ReportEvents' });
  // boot: o SwiftShader às vezes perde o contexto WebGL na 1ª compilação de shaders → nova tentativa (até 4)
  for (let t = 1; ; t++) {
    await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
    try { await page.waitForFunction(() => window.__ciclo && window.__ciclo.ciclo === 0, null, { timeout: Number(process.env.BOOT_MS || 90000) }); break; }
    catch (e) { events.push({ type: 'boot_retry', t }); console.log(JSON.stringify({ label, boot_retry: t })); if (t >= 4) throw e; }
  }
  await page.mouse.click(195, 589); await page.waitForTimeout(500);   // gesto do usuário (libera o áudio)
  await page.evaluate(() => {
    const G = window.__ga; window.__aud = { starts: 0, missing: 0, byId: {} };
    const orig = G.start_sample;
    G.start_sample = function (playbackObjectId, streamObjectId, ...rest) {
      window.__aud.starts++; if (!G.samples.has(String(streamObjectId))) window.__aud.missing++;
      return orig.call(this, playbackObjectId, streamObjectId, ...rest);
    };
  });
  const renderer = async () => {
    const { processInfo } = await bcdp.send('SystemInfo.getProcessInfo');
    const r = processInfo.filter(p => p.type === 'renderer').map(p => privateMiB(p.id)).filter(x => x != null);
    return r.length ? Math.max(...r) : null;
  };
  const points = [];
  const measure = async (i, deep) => {
    await page.waitForTimeout(400);
    await cdp.send('HeapProfiler.collectGarbage');
    const heap = await cdp.send('Runtime.getHeapUsage');
    const o = await page.evaluate(() => {
      const G = window.__ga; let bytes = 0;
      for (const s of G.samples.values()) { const b = s._audioBuffer; if (b) bytes += b.length * b.numberOfChannels * 4; }
      const m = window.fraihaMusic;
      return { godot: window.__ciclo, samples: G.samples.size, sampleBytes: bytes, sampleNodes: G.sampleNodes ? G.sampleNodes.size : null,
        released: G.fraihaReleased || 0, releasedBytes: G.fraihaReleasedBytes || 0, pending: G.fraihaPending ? G.fraihaPending.size : 0,
        aud: window.__aud, wasm: window.__wasmBytes(), music: m ? { src: !!m.el.src, paused: m.el.paused } : null };
    });
    let guid = null;
    if (deep) {
      try { guid = (await bcdp.send('Tracing.requestMemoryDump', { deterministic: true, levelOfDetail: 'detailed' })).dumpGuid; } catch (e) { events.push({ type: 'dump_error', message: e.message }); }
    }
    const p = { ciclo: i, samples: o.samples, sampleMiB: MiB(o.sampleBytes), sampleNodes: o.sampleNodes, pending: o.pending, released: o.released, releasedMiB: MiB(o.releasedBytes),
      starts: o.aud.starts, missing: o.aud.missing, jsMiB: MiB(heap.usedSize), wasmMiB: MiB(o.wasm), rendererMiB: await renderer(),
      guid, music: o.music, godot: o.godot };
    points.push(p);
    console.log(JSON.stringify({ label, ...p, godot: undefined, music: undefined }));
  };
  await measure(0, true);
  for (let i = 1; i <= cycles; i++) {
    await page.evaluate(n => { window.__seguir = n - 1; }, i);
    await page.waitForFunction(n => window.__ciclo && window.__ciclo.ciclo === n, i, { timeout: 120000 });
    if (i % 5 === 0) { await page.setViewportSize({ width: 844, height: 390 }); await page.waitForTimeout(700); await page.setViewportSize({ width: 390, height: 844 }); await page.waitForTimeout(700); }
    const deep = [1, 5, 10, 20, 30, 40].includes(i);
    if (deep || i % 5 === 0) await measure(i, deep);
  }
  await page.evaluate(n => { window.__seguir = n; }, cycles);
  // CTX_LOSS=1: perde o contexto WebGL (como o iPhone faz), recarrega como a recuperação do FRAIHA e joga de novo:
  // o áudio tem de voltar a tocar (amostras registradas de novo, nenhuma reprodução sem amostra).
  if (process.env.CTX_LOSS) {
    await page.evaluate(() => { const c = document.querySelector('canvas'); const g = c && (c.getContext('webgl2') || c.getContext('webgl')); const x = g && g.getExtension('WEBGL_lose_context'); if (x) x.loseContext(); window.__perdeu = !!x; });
    await page.waitForTimeout(1500);
    await page.reload();
    await page.waitForFunction(() => window.__ciclo && window.__ciclo.ciclo === 0, null, { timeout: 120000 });
    await page.mouse.click(195, 589); await page.waitForTimeout(500);
    await page.evaluate(() => {
      const G = window.__ga; window.__aud = { starts: 0, missing: 0 };
      const orig = G.start_sample;
      G.start_sample = function (a, id, ...rest) { window.__aud.starts++; if (!G.samples.has(String(id))) window.__aud.missing++; return orig.call(this, a, id, ...rest); };
    });
    for (let i = 1; i <= cycles; i++) {
      await page.evaluate(n => { window.__seguir = n - 1; }, i);
      await page.waitForFunction(n => window.__ciclo && window.__ciclo.ciclo === n, i, { timeout: 120000 });
    }
    await measure(cycles + 100, false);
    await page.evaluate(n => { window.__seguir = n; }, cycles);
  }
  // dumps memory-infra chegam ao encerrar o trace: partition_alloc array_buffer / buffer do renderer por ciclo
  const done = new Promise(r => { const t = setTimeout(r, 30000); bcdp.once('Tracing.tracingComplete', () => { clearTimeout(t); r(); }); });
  await bcdp.send('Tracing.end').catch(() => {});
  await done;
  if (process.env.DEBUG_DUMPS) console.log('DUMPS', dumps.length, JSON.stringify([...new Set(dumps.map(d => d.id))]), JSON.stringify(dumps.filter(d => d.args.dumps.allocators).slice(0, 4).map(d => ({ id: d.id, pid: d.pid, keys: Object.keys(d.args.dumps), alloc: Object.keys(d.args.dumps.allocators || {}).filter(k => /partition/.test(k)).slice(0, 12) }))));
  // os IDs dos eventos não batem com o dumpGuid devolvido: casa pela ordem dos pedidos
  const ids = [...new Set(dumps.filter(d => d.args.dumps.allocators).map(d => String(d.id)))].sort((a, b) => parseInt(a, 16) - parseInt(b, 16));
  let n = 0;
  for (const p of points) {
    if (!p.guid) continue;
    p.dumpId = ids[n++];
    let ab = null, bf = null;
    for (const d of dumps) {
      if (String(d.id) !== p.dumpId) continue;
      for (const [k, v] of Object.entries(d.args.dumps.allocators || {})) {
        const a = v.attrs || {}, sz = a.allocated_objects_size || a.size;
        if (!sz) continue;
        const val = parseInt(sz.value, 16);
        if (/partition_alloc\/partitions\/array_buffer$/.test(k)) ab = Math.max(ab || 0, val);
        if (/partition_alloc\/partitions\/buffer$/.test(k)) bf = Math.max(bf || 0, val);
      }
    }
    p.arrayBufferMiB = ab == null ? null : MiB(ab); p.bufferMiB = bf == null ? null : MiB(bf);
    console.log(JSON.stringify({ label, ciclo: p.ciclo, arrayBufferMiB: p.arrayBufferMiB, bufferMiB: p.bufferMiB }));
  }
  fs.writeFileSync(outPath, JSON.stringify({ label, dir, cycles, points, events }, null, 1));
  console.log(JSON.stringify({ label, fim: true, erros: events.filter(e => e.type !== 'console_error' || /sample|audio|Uncaught/i.test(e.message)).length, events: events.slice(0, 8) }));
  await browser.close(); server.close();
})().catch(e => { console.error(e); process.exit(1); });
