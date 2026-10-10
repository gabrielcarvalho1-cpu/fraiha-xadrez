// FRAIHA R55.6 · teste da recuperação de perda de contexto WebGL no Chromium (build Web real + simulador local).
//
//   NODE_PATH=<node_modules com playwright-core> node tests/web/gl/gl_recovery_test.cjs <pasta_bucket> [saida_png_dir]
//
// O bucket precisa ser um site montado pelo empacotador (index.html com o script fraiha-gl-recovery) e, para o
// teste do diagnóstico, com reload_diag.js injetado (tools/diag/inject_reload_diag.py antes de empacotar).
// Perda de contexto provocada com WEBGL_lose_context (loseContext / restoreContext), igual ao teste do Orca.
const { chromium } = require("playwright-core");
const { spawn } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const [bucket, shotDir] = process.argv.slice(2);
const PORT = 8931, BASE = `http://127.0.0.1:${PORT}/`;
const CHROME = process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome";
let failures = 0;
const check = (ok, label) => { console.log((ok ? "PASS " : "FAIL ") + label); if (!ok) failures++; };

async function booted(page, timeout = 240000) {
  await page.waitForFunction(() => typeof engine !== "undefined" && document.getElementById("canvas") && !document.getElementById("status"), null, { timeout, polling: 100 });
  await page.waitForTimeout(2500);
}
async function lose(page, restoreAfterMs) {
  return page.evaluate((ms) => {
    const gl = document.getElementById("canvas").getContext("webgl2");
    const ext = gl && gl.getExtension("WEBGL_lose_context");
    if (!ext) return "sem WEBGL_lose_context";
    window.__marker = "antes-do-reload";
    ext.loseContext();
    if (ms >= 0) setTimeout(() => { try { ext.restoreContext(); } catch (e) {} }, ms);
    return "ok";
  }, restoreAfterMs === undefined ? -1 : restoreAfterMs);
}
const glState = (page) => page.evaluate(() => (window.__fraihaGl ? { state: window.__fraihaGl.state, ev: window.__fraihaGl.events.slice() } : null));
const overlay = (page) => page.evaluate(() => { const b = document.getElementById("fraiha-gl-tela"); return b ? b.innerText.replace(/\s+/g, " ").trim() : null; });
const counter = (page) => page.evaluate(() => { try { return JSON.parse(sessionStorage.getItem("fraiha_gl_reload_v1") || "[]").length; } catch (e) { return -1; } });
const reloaded = (page) => page.evaluate(() => window.__marker !== "antes-do-reload");
async function canvasNotBlank(page, name) {
  const png = await page.screenshot();
  if (shotDir) fs.writeFileSync(path.join(shotDir, name + ".png"), png);
  // tela vazia (uma cor só) vira um PNG de poucos KB; a Home do jogo passa de 300 KB
  return png.length;
}
async function waitReload(page, ms) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    try { if (await reloaded(page)) return Date.now() - t0; } catch (e) { /* navegando */ }
    await page.waitForTimeout(200);
  }
  return -1;
}

(async () => {
  const log = path.join(os.tmpdir(), "fraiha_gl_sim_" + process.pid + ".jsonl");
  const sim = spawn(process.execPath, [path.join(__dirname, "../cache/sim_server.mjs"), bucket, String(PORT), "worker", log], { stdio: "ignore" });
  await new Promise((r) => setTimeout(r, 1500));
  const profile = fs.mkdtempSync(path.join(process.env.PROFILE_DIR || os.tmpdir(), "fraiha_gl_prof_"));
  const ctx = await chromium.launchPersistentContext(profile, {
    executablePath: CHROME, headless: true, viewport: { width: 1280, height: 720 },
    args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
  });
  const page = ctx.pages()[0];
  const dialogs = [];
  page.on("dialog", (d) => { dialogs.push(d.message()); d.dismiss().catch(() => {}); });

  // A · Web desktop normal (com ?diag=1 para o teste do diagnóstico)
  await page.goto(BASE + "?diag=1", { waitUntil: "commit" });
  await booted(page);
  let st = await glState(page);
  check(st && st.state === "ok" && (await overlay(page)) === null, "A · carga normal: sem tela de recuperação, estado ok");
  check((await canvasNotBlank(page, "A_normal")) > 100000, "A · canvas desenhando");

  // B · perda de contexto → tela de recuperação → reload controlado → jogo volta
  check((await lose(page)) === "ok", "B · WEBGL_lose_context disponível");
  await page.waitForTimeout(300);
  const ov = await overlay(page);
  st = await glState(page);
  check(ov !== null && /interrompidos/.test(ov) && st.state === "recovering", "B · tela de recuperação na hora: " + ov);
  check(dialogs.length === 0, "B · sem alert() bloqueante do Godot");
  let ms = await waitReload(page, 15000);
  check(ms > 0 && ms < 8000, "B · reload controlado em " + ms + " ms");
  await booted(page);
  check((await counter(page)) === 1 && (await overlay(page)) === null && (await glState(page)).state === "ok", "B · depois do reload: jogo de volta, 1 reload automático contado");
  check((await canvasNotBlank(page, "B_depois")) > 100000, "B · canvas desenhando de novo (sem tela vazia permanente)");
  // diagnóstico: a sessão anterior registrou a perda e o reload automático
  const diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem("fraiha_diag_v1")); } catch (e) { return null; } });
  const prevK = diag && diag.prev ? diag.prev.ev.map((e) => e.k) : [];
  check(["webgl_lost", "gl_lost_handled", "gl_reload_go"].every((k) => prevK.includes(k)), "B · reload_diag registrou webgl_lost + gl_lost_handled + gl_reload_go");
  const diagBox = await page.evaluate(() => { const p = [...document.querySelectorAll("pre")].find((x) => /FRAIHA DIAG/.test(x.textContent)); return p ? p.textContent : ""; });
  check(/reload AUTOMÁTICO da recuperação de gráficos/.test(diagBox), "B · caixa do diagnóstico explica o reload automático");

  // C · navegador devolve o contexto (restoreContext): mesmo assim reload (o Godot não recria a GPU), mais rápido
  await lose(page, 400);
  ms = await waitReload(page, 15000);
  await booted(page);
  const prevC = await page.evaluate(() => JSON.parse(localStorage.getItem("fraiha_diag_v1")).prev.ev.map((e) => e.k));
  check(ms > 0 && prevC.includes("webgl_restored") && prevC.includes("gl_restored_signal") && prevC.includes("gl_reload_go"), "C · restaurado: sinal registrado e reload em " + ms + " ms");
  check((await counter(page)) === 2, "C · 2 reloads automáticos contados");

  // D · anti-loop: 3ª perda em menos de 5 min NÃO recarrega sozinha; botão manual funciona
  await lose(page);
  await page.waitForTimeout(6000);
  st = await glState(page);
  check(!(await reloaded(page)) && st.state === "loop" && /falharam de novo/.test(await overlay(page)), "D · 3ª perda: sem reload automático (anti-loop), botão Recarregar");
  check(dialogs.length === 0, "D · ainda sem alert()");
  await page.click("#fraiha-gl-tela button");
  ms = await waitReload(page, 10000);
  await booted(page);
  check(ms > 0 && (await counter(page)) === 2 && (await glState(page)).state === "ok", "D · Recarregar manual funciona e não soma no contador");

  // E · offline: espera a internet voltar, sem reload em página de erro
  await page.evaluate(() => sessionStorage.removeItem("fraiha_gl_reload_v1"));
  await ctx.setOffline(true);
  await lose(page);
  await page.waitForTimeout(5000);
  st = await glState(page);
  check(!(await reloaded(page)) && st.state === "wait_online" && /sem internet/.test(await overlay(page)), "E · offline: espera a conexão (não recarrega para página de erro)");
  await ctx.setOffline(false);
  ms = await waitReload(page, 15000);
  await booted(page);
  check(ms > 0 && (await glState(page)).state === "ok", "E · internet voltou: reload em " + ms + " ms e jogo de volta");

  // F · aba em segundo plano: só recarrega quando volta a ficar visível
  await page.evaluate(() => sessionStorage.removeItem("fraiha_gl_reload_v1"));
  await page.evaluate(() => { Object.defineProperty(document, "visibilityState", { configurable: true, get: () => window.__vis || "visible" }); window.__vis = "hidden"; });
  await lose(page);
  await page.waitForTimeout(5000);
  check(!(await reloaded(page)) && (await glState(page)).state === "wait_visible", "F · aba escondida: espera ficar visível");
  await page.evaluate(() => { window.__vis = "visible"; document.dispatchEvent(new Event("visibilitychange")); });
  ms = await waitReload(page, 15000);
  await booted(page);
  check(ms > 0, "F · aba visível de novo: reload em " + ms + " ms");

  // G · reload normal do usuário: nada de tela de recuperação, nada contado
  await page.evaluate(() => sessionStorage.removeItem("fraiha_gl_reload_v1"));
  await page.reload({ waitUntil: "commit" });
  await booted(page);
  check((await overlay(page)) === null && (await counter(page)) === 0 && (await glState(page)).state === "ok", "G · reload normal: sem recuperação e sem contagem");
  check((await canvasNotBlank(page, "G_reload_normal")) > 100000, "G · canvas desenhando");
  check(dialogs.length === 0, "nenhum alert() em todo o teste");

  await ctx.close(); sim.kill();
  try { fs.rmSync(profile, { recursive: true, force: true }); fs.rmSync(log, { force: true }); } catch (e) {}
  console.log("RESULT", failures === 0 ? "OK" : "FALHAS=" + failures);
  process.exit(failures ? 1 : 0);
})().catch((e) => { console.error("ERRO", e); process.exit(1); });
