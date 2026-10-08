/* FRAIHA · diagnóstico TEMPORÁRIO de reload no celular (R52e / auditoria Orca).
 * NÃO vai para a build pública: só entra numa build de diagnóstico via tools/diag/inject_reload_diag.py.
 * Ativo só com ?diag=1 na URL (fica ligado nas próximas aberturas até ?diag=0).
 * Grava em localStorage um diário curto por sessão de boot: eventos de ciclo de vida da página, perda de
 * contexto WebGL, erros JS, memória JS (quando o navegador expõe) e um "batimento" a cada 2 s.
 * Na abertura seguinte mostra um painel com o fim da sessão ANTERIOR, para distinguir:
 *   - reload limpo (pagehide/beforeunload registrados),
 *   - aba morta pelo sistema / crash do processo (batimento para de repente, sem pagehide),
 *   - perda de contexto WebGL (webglcontextlost antes do fim),
 *   - erro JS / promise rejeitada antes do fim. */
(function () {
  var KEY = "fraiha_diag_v1", MAXEV = 120;
  var q = location.search;
  try {
    if (/[?&]diag=0/.test(q)) { localStorage.removeItem(KEY + "_on"); return; }
    if (/[?&]diag=1/.test(q)) localStorage.setItem(KEY + "_on", "1");
    if (localStorage.getItem(KEY + "_on") !== "1") return;
  } catch (e) { return; }

  var boot = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 6);
  var t0 = performance.now();
  var store;
  try { store = JSON.parse(localStorage.getItem(KEY) || "{}"); } catch (e) { store = {}; }
  var prev = store.cur || null;
  store.prev = prev; store.cur = { boot: boot, start: new Date().toISOString(), ua: navigator.userAgent,
    nav: (performance.getEntriesByType && performance.getEntriesByType("navigation")[0] || {}).type || "?",
    discarded: !!document.wasDiscarded, ev: [] };
  function save() { try { localStorage.setItem(KEY, JSON.stringify(store)); } catch (e) {} }
  function mem() {
    var m = performance.memory; var o = {};
    if (m) o.js = Math.round(m.usedJSHeapSize / 1048576) + "MB";
    try { if (window.Module && Module.HEAP8) o.wasm = Math.round(Module.HEAP8.length / 1048576) + "MB"; } catch (e) {}
    return o;
  }
  function log(k, extra) {
    var e = { t: Math.round((performance.now() - t0) / 100) / 10, k: k };
    if (extra) for (var x in extra) e[x] = extra[x];
    var m = mem(); for (var y in m) e[y] = m[y];
    var ev = store.cur.ev; ev.push(e); if (ev.length > MAXEV) ev.splice(0, ev.length - MAXEV);
    save();
  }
  log("boot");
  ["pagehide", "pageshow", "beforeunload", "freeze", "resume"].forEach(function (n) {
    window.addEventListener(n, function (ev) { log(n, ev.persisted !== undefined ? { persisted: ev.persisted } : null); }, true);
  });
  document.addEventListener("visibilitychange", function () { log("vis_" + document.visibilityState); }, true);
  window.addEventListener("orientationchange", function () { log("orient", { w: innerWidth, h: innerHeight }); });
  window.addEventListener("error", function (ev) { log("error", { msg: String(ev.message || ev.type).slice(0, 160), src: String(ev.filename || "").split("/").pop() + ":" + ev.lineno }); }, true);
  window.addEventListener("unhandledrejection", function (ev) { log("rejection", { msg: String(ev.reason && (ev.reason.message || ev.reason)).slice(0, 160) }); });
  document.addEventListener("webglcontextlost", function () { log("webgl_lost"); }, true);
  document.addEventListener("webglcontextrestored", function () { log("webgl_restored"); }, true);
  var hook = setInterval(function () {
    var c = document.getElementById("canvas");
    if (!c) return;
    clearInterval(hook);
    c.addEventListener("webglcontextlost", function () { log("webgl_lost"); }, true);
    c.addEventListener("webglcontextrestored", function () { log("webgl_restored"); }, true);
  }, 200);
  var beat = 0;
  setInterval(function () { beat++; store.cur.last_beat = Math.round((performance.now() - t0) / 1000); if (beat % 5 === 0) log("hb"); else save(); }, 2000);

  function panel() {
    if (!prev) return;
    var ev = prev.ev || [];
    var tail = ev.slice(-14).map(function (e) {
      var s = e.t + "s " + e.k; for (var x in e) if (x !== "t" && x !== "k") s += " " + x + "=" + e[x]; return s;
    }).join("\n");
    var ended = ev.length ? ev[ev.length - 1].k : "?";
    var clean = ev.some(function (e) { return e.k === "pagehide" || e.k === "beforeunload"; });
    var verdict = clean ? "saída registrada (pagehide/beforeunload)" : "SEM pagehide: a aba provavelmente foi encerrada pelo sistema / processo caiu";
    if (ev.some(function (e) { return e.k === "webgl_lost"; })) verdict += " · houve perda de contexto WebGL";
    if (ev.some(function (e) { return e.k === "error" || e.k === "rejection"; })) verdict += " · houve erro JS";
    var d = document.createElement("pre");
    d.style.cssText = "position:fixed;left:6px;right:6px;bottom:6px;max-height:45%;overflow:auto;z-index:99999;margin:0;padding:8px;" +
      "background:rgba(0,0,0,.85);color:#9f9;font:11px/1.35 monospace;border:1px solid #4a4;white-space:pre-wrap";
    d.textContent = "FRAIHA DIAG · sessão anterior " + prev.boot + " (" + prev.start + ", nav=" + prev.nav + ")\n" +
      "durou ~" + (prev.last_beat || 0) + "s · último evento: " + ended + "\n" + verdict + "\n\n" + tail +
      "\n\nNesta abertura: nav=" + store.cur.nav + (store.cur.discarded ? " · wasDiscarded=SIM" : "") +
      "\n(toque para fechar · tire um print desta caixa)";
    d.onclick = function () { d.remove(); };
    (document.body || document.documentElement).appendChild(d);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", panel); else panel();
})();
