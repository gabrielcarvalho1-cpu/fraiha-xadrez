/* FRAIHA R55.6 · recuperação de perda do contexto WebGL (Web, principalmente celular).
 * Entra INLINE no index.html pelo empacotador (tools/web_release/pack_web_release.py). Ver docs/web/R55_6_WEBGL_CONTEXT_LOSS.md.
 *
 * Problema: o navegador pode derrubar o contexto WebGL (memória da GPU, aba em segundo plano, driver). O Godot 4.5 Web
 * não sabe recriar texturas/shaders: só mostrava um alert() (que trava a página) e o canvas ficava vazio para sempre,
 * com o jogo rodando por baixo.
 *
 * O que faz:
 *  1. Pega o evento ANTES do Godot (captura no document), cancela o alert() bloqueante e cobre o canvas vazio com
 *     uma tela clara de recuperação.
 *  2. Restaurar no lugar NÃO é um caminho suportado (o Godot não recria os recursos da GPU): mesmo que o navegador
 *     devolva o contexto (webglcontextrestored), a recuperação é um reload controlado. O restored só serve de sinal
 *     de que a GPU voltou.
 *  3. Reload controlado: espera a aba ficar visível e a internet estar disponível (offline → espera o evento online),
 *     dá até 3 s para o navegador devolver o contexto e recarrega a MESMA URL. Sessão de conta e preferências ficam
 *     no armazenamento do jogo (user://) e partidas online voltam pela reconexão normal do servidor.
 *  4. Anti-loop: no máximo 2 reloads automáticos em 5 min nesta aba (sessionStorage). Depois disso, ou sem
 *     sessionStorage, NÃO recarrega sozinho: mostra o botão "Recarregar".
 *  5. Registra cada passo no diagnóstico de reload (reload_diag.js, ?diag=1) quando ele estiver ligado.
 */
(function () {
  "use strict";
  var KEY = "fraiha_gl_reload_v1", MAX_AUTO = 2, WINDOW_MS = 5 * 60 * 1000, GRACE_MS = 3000, SHOW_MS = 1200;
  var lost = false, restored = false, leaving = false, done = false, box = null, msg = null, btn = null, timer = 0;
  var api = window.__fraihaGl = { state: "ok", reloads: 0, events: [] };

  function diag(k, extra) {
    api.events.push(k);
    try { if (typeof window.fraihaDiagLog === "function") window.fraihaDiagLog(k, extra || null); } catch (e) {}
  }
  function history() {          // reloads automáticos recentes nesta aba; null = sem sessionStorage
    try {
      var now = Date.now(), a = JSON.parse(window.sessionStorage.getItem(KEY) || "[]");
      if (!Array.isArray(a)) a = [];
      return a.filter(function (t) { return typeof t === "number" && now - t >= 0 && now - t < WINDOW_MS; });
    } catch (e) { return null; }
  }
  function isGameCanvas(ev) { return !!(ev && ev.target && ev.target.id === "canvas"); }

  function ui(text, withButton) {
    if (!box) {
      box = document.createElement("div");
      box.id = "fraiha-gl-tela";
      box.setAttribute("role", "alert");
      box.style.cssText = "position:fixed;inset:0;z-index:100000;display:flex;align-items:center;justify-content:center;" +
        "padding:16px;box-sizing:border-box;background:#111a13;color:#f3ede0;font:16px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;text-align:center";
      var card = document.createElement("div");
      card.style.cssText = "max-width:420px;width:100%;padding:22px 18px;border:2px solid #b8893a;border-radius:12px;background:#17241a;box-shadow:0 8px 30px rgba(0,0,0,.5)";
      var title = document.createElement("div");
      title.textContent = "FRAIHA Xadrez";
      title.style.cssText = "font-weight:700;font-size:20px;color:#f4ce7f;margin-bottom:10px";
      msg = document.createElement("div");
      btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = "Recarregar";
      btn.style.cssText = "margin-top:16px;padding:12px 26px;font:700 16px system-ui,sans-serif;color:#111a13;background:#f4ce7f;border:0;border-radius:8px;cursor:pointer";
      btn.onclick = function () { diag("gl_reload_manual"); reloadNow(true); };
      card.appendChild(title); card.appendChild(msg); card.appendChild(btn);
      box.appendChild(card);
      (document.body || document.documentElement).appendChild(box);
    }
    msg.textContent = text;
    btn.style.display = withButton ? "inline-block" : "none";
  }

  function reloadNow(manual) {
    if (done) return;
    if (!manual) {
      var h = history();
      if (h === null) { api.state = "manual"; diag("gl_no_storage"); ui("Os gráficos do jogo foram interrompidos pelo navegador. Toque em Recarregar para voltar.", true); return; }
      if (h.length >= MAX_AUTO) {
        api.state = "loop"; diag("gl_loop_blocked", { n: h.length });
        ui("Os gráficos falharam de novo. Feche outras abas ou apps pesados e toque em Recarregar.", true);
        return;
      }
      h.push(Date.now());
      try { window.sessionStorage.setItem(KEY, JSON.stringify(h)); } catch (e) {}
      api.reloads = h.length;
    }
    done = true; api.state = "reloading";
    diag(manual ? "gl_reload_go_manual" : "gl_reload_go", { restored: restored });
    ui("Recarregando o jogo…", false);
    setTimeout(function () { window.location.reload(); }, 50);
  }

  function step() {
    clearTimeout(timer);
    if (!lost || done || leaving) return;
    if (document.visibilityState === "hidden") { api.state = "wait_visible"; return; }   // volta no visibilitychange
    if (navigator.onLine === false) {
      api.state = "wait_online"; diag("gl_wait_online");
      ui("Os gráficos do jogo foram interrompidos e você está sem internet. O jogo recarrega sozinho quando a conexão voltar.", false);
      return;
    }
    api.state = "recovering";
    ui("Os gráficos do jogo foram interrompidos pelo navegador. Recarregando para voltar ao jogo…", false);
    timer = setTimeout(function () { reloadNow(false); }, restored ? SHOW_MS : GRACE_MS);
  }

  document.addEventListener("webglcontextlost", function (ev) {
    if (!isGameCanvas(ev) || leaving) return;
    ev.preventDefault();          // permite ao navegador devolver o contexto (sinal de GPU disponível)
    ev.stopPropagation();         // não deixa chegar ao alert() bloqueante do Godot
    if (lost) return;
    lost = true; restored = false;
    diag("gl_lost_handled", { hidden: document.visibilityState === "hidden", online: navigator.onLine !== false });
    step();
  }, true);
  document.addEventListener("webglcontextrestored", function (ev) {
    if (!isGameCanvas(ev) || !lost) return;
    restored = true; diag("gl_restored_signal");
    step();
  }, true);
  document.addEventListener("visibilitychange", function () { if (lost && document.visibilityState === "visible") step(); });
  window.addEventListener("online", function () { if (lost) { diag("gl_online"); step(); } });
  window.addEventListener("offline", function () { if (lost) step(); });
  // saindo da página (reload/navegação do próprio usuário): perdas de contexto no descarregamento não contam
  window.addEventListener("pagehide", function () { leaving = true; }, true);
  window.addEventListener("beforeunload", function () { leaving = true; }, true);
  window.addEventListener("pageshow", function (ev) { if (ev && ev.persisted) leaving = false; }, true);
})();
