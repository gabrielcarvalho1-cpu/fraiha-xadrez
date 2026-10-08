/* FRAIHA · diagnóstico TEMPORÁRIO de reload no celular (R52e; robustecido no R52f após a auditoria Orca).
 * Entra na build só via tools/diag/inject_reload_diag.py. Sem ativação, não faz NADA (nenhum evento, badge ou caixa).
 *
 * ATIVAÇÃO (decisão R52f): ?diag=1 liga por 24 h NESTE navegador, mesmo que a query some depois (o jogo reescreve a
 * URL e o iOS pode reabrir a aba sem ela) — é justamente o reload que se quer registrar. ?diag=0 desliga na hora;
 * depois de 24 h desliga sozinho. Enquanto ligado, um selo "DIAG" fica no canto (o usuário sabe que está ativo).
 *
 * O QUE GRAVA (localStorage, só neste aparelho): eventos de ciclo de vida da página, perda/recuperação do contexto
 * WebGL (uma vez cada), erros JS e promessas rejeitadas (texto curto e REDIGIDO: sem query/hash de URL, sem e-mails,
 * sem tokens), memória JS quando o navegador expõe e um batimento a cada 2 s.
 *
 * NA ABERTURA SEGUINTE mostra o fim da sessão ANTERIOR, classificado como:
 *   SAÍDA REGISTRADA  — houve pagehide/beforeunload (reload, navegação ou fechamento normais);
 *   DESCONHECIDO      — o registro para sem pagehide. NÃO é prova de falta de memória: pode ser o iOS encerrando a
 *                       aba (memória, segundo plano), crash do processo, fechamento forçado ou bateria. */
(function () {
  "use strict";
  var KEY = "fraiha_diag_v1", ON = KEY + "_on", VER = 2, TTL = 24 * 3600 * 1000, MAXEV = 120;
  var ls;
  try { ls = window.localStorage; ls.getItem(ON); } catch (e) { return; }   // sem localStorage: não faz nada
  var q = String(location.search || "");
  try {
    if (/[?&]diag=0(&|$)/.test(q)) { ls.removeItem(ON); ls.removeItem(KEY); return; }
    if (/[?&]diag=1(&|$)/.test(q)) ls.setItem(ON, String(Date.now() + TTL));
    var until = parseInt(ls.getItem(ON) || "", 10);
    if (!(until > Date.now())) { if (ls.getItem(ON) !== null) ls.removeItem(ON); return; }   // inativo ou vencido
  } catch (e) { return; }

  // ---------- redação: nada de query/hash de URL, e-mails, tokens ou textos longos no registro
  function redact(v, max) {
    var s = String(v == null ? "" : v);
    s = s.replace(/https?:\/\/[^\s"'<>]+/gi, function (u) { return u.replace(/[?#].*$/, ""); });
    s = s.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "<email>");
    s = s.replace(/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}/g, "<jwt>");
    s = s.replace(/\b(sb_[a-z]+_[A-Za-z0-9_-]{8,}|[A-Za-z0-9_-]{32,})\b/g, "<token>");
    s = s.replace(/(access_token|refresh_token|token|password|senha|key)\s*[=:]\s*[^\s&,;]+/gi, "$1=<redigido>");
    return s.length > max ? s.slice(0, max) + "…" : s;
  }

  // ---------- leitura com validação de schema (dado velho/corrompido/de outra versão = recomeça do zero)
  function validSession(x) {
    return x && typeof x === "object" && typeof x.boot === "string" && Array.isArray(x.ev) && x.ev.length <= MAXEV * 2;
  }
  var store = null;
  try { store = JSON.parse(ls.getItem(KEY) || "null"); } catch (e) { store = null; }
  if (!store || typeof store !== "object" || store.v !== VER) store = { v: VER };
  var prev = validSession(store.cur) ? store.cur : null;
  var boot = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 6);
  var t0 = performance.now();
  var nav = "?";
  try { var ne = performance.getEntriesByType && performance.getEntriesByType("navigation")[0]; nav = ne && ne.type ? String(ne.type) : "?"; } catch (e) {}
  store = { v: VER, prev: prev, cur: { boot: boot, start: new Date().toISOString(), ua: redact(navigator.userAgent, 160), nav: nav, discarded: !!document.wasDiscarded, ev: [], last_beat: 0 } };

  function save() { try { ls.setItem(KEY, JSON.stringify(store)); } catch (e) {} }
  function mem() {
    var o = {};
    try { var m = performance.memory; if (m && m.usedJSHeapSize) o.js = Math.round(m.usedJSHeapSize / 1048576) + "MB"; } catch (e) {}
    return o;
  }
  function log(k, extra) {
    var e = { t: Math.round((performance.now() - t0) / 100) / 10, k: k };
    if (extra) for (var x in extra) if (Object.prototype.hasOwnProperty.call(extra, x)) e[x] = extra[x];
    var m = mem(); for (var y in m) e[y] = m[y];
    var ev = store.cur.ev; ev.push(e); if (ev.length > MAXEV) ev.splice(0, ev.length - MAXEV);
    save();
  }
  log("boot");
  ["pagehide", "pageshow", "beforeunload", "freeze", "resume"].forEach(function (n) {
    window.addEventListener(n, function (ev) { log(n, ev && ev.persisted !== undefined ? { persisted: !!ev.persisted } : null); }, true);
  });
  document.addEventListener("visibilitychange", function () { log("vis_" + document.visibilityState); }, true);
  window.addEventListener("orientationchange", function () { log("orient", { w: innerWidth, h: innerHeight }); });
  window.addEventListener("error", function (ev) {
    var src = String(ev && ev.filename || "").split(/[?#]/)[0].split("/").pop();
    log("error", { msg: redact(ev && (ev.message || ev.type), 120), src: redact(src, 40) + ":" + (ev && ev.lineno || 0) });
  }, true);
  window.addEventListener("unhandledrejection", function (ev) {
    var r = ev && ev.reason;
    log("rejection", { msg: redact(r && (r.message || r), 120) });
  });
  // WebGL: o evento nasce no <canvas> e não borbulha; um ÚNICO ouvinte em captura no document pega todos.
  // (o R52e ouvia também no canvas e registrava cada perda em dobro)
  document.addEventListener("webglcontextlost", function () { log("webgl_lost"); }, true);
  document.addEventListener("webglcontextrestored", function () { log("webgl_restored"); }, true);
  var beat = 0;
  setInterval(function () {
    beat++;
    store.cur.last_beat = Math.round((performance.now() - t0) / 1000);
    if (beat % 5 === 0) log("hb"); else save();
  }, 2000);

  function classify(s) {
    var ev = s.ev || [];
    var clean = ev.some(function (e) { return e && (e.k === "pagehide" || e.k === "beforeunload"); });
    var notes = [];
    if (ev.some(function (e) { return e && e.k === "webgl_lost"; })) notes.push("houve perda de contexto WebGL");
    if (ev.some(function (e) { return e && (e.k === "error" || e.k === "rejection"); })) notes.push("houve erro JS");
    return {
      verdict: clean ? "SAÍDA REGISTRADA (pagehide/beforeunload: reload, navegação ou fechamento normais)"
                     : "DESCONHECIDO — terminou sem pagehide. Não prova falta de memória: pode ser o iOS encerrando a aba, crash, fechamento forçado.",
      notes: notes
    };
  }
  function line(e) {
    var s = e.t + "s " + e.k;
    for (var x in e) if (x !== "t" && x !== "k") s += " " + x + "=" + e[x];
    return s;
  }
  function ui() {
    var badge = document.createElement("div");
    badge.textContent = "DIAG ativo";
    badge.style.cssText = "position:fixed;left:4px;top:4px;z-index:99998;pointer-events:none;font:10px monospace;color:#9f9;background:rgba(0,0,0,.55);padding:1px 4px;border-radius:3px";
    document.body.appendChild(badge);
    if (!prev) return;
    var c = classify(prev);
    var ev = prev.ev || [];
    var d = document.createElement("pre");
    d.style.cssText = "position:fixed;left:6px;right:6px;bottom:6px;max-height:45%;overflow:auto;z-index:99999;margin:0;padding:8px;" +
      "background:rgba(0,0,0,.85);color:#9f9;font:11px/1.35 monospace;border:1px solid #4a4;white-space:pre-wrap";
    d.textContent = "FRAIHA DIAG · sessão anterior " + prev.boot + " (" + String(prev.start || "?") + ", nav=" + String(prev.nav || "?") + ")\n" +
      "durou ~" + (prev.last_beat || 0) + "s · último evento: " + (ev.length ? ev[ev.length - 1].k : "?") + "\n" +
      "ENCERRAMENTO: " + c.verdict + (c.notes.length ? "\n" + c.notes.join(" · ") : "") + "\n\n" +
      ev.slice(-14).map(line).join("\n") +
      "\n\nNesta abertura: nav=" + nav + (store.cur.discarded ? " · wasDiscarded=SIM" : "") +
      "\n(toque para fechar · tire um print desta caixa)";
    d.onclick = function () { d.remove(); };
    document.body.appendChild(d);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ui); else ui();
})();
