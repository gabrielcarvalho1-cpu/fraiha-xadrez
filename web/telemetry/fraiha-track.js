/* FRAIHA · RASTREAMENTO DA VISITA (R181) — Admin → Sessões / Funil.
   Roda no <head> do jogo (antes do Godot), então registra MESMO quem sai na tela de entrada sem clicar em nada.
   - Visitante = código ALEATÓRIO deste navegador (localStorage), sem dado pessoal. Visita = esta aba (sessionStorage;
     depois de 30 min parada, começa outra).
   - Guarda utm_source / utm_campaign / utm_medium (e se veio com fbclid) da URL de entrada.
   - Manda para o servidor (POST /t) só: nome de tela, nome de botão, tempos, carregamento, login escolhido, saída e
     códigos de erro. Nunca texto digitado. O servidor ainda confere tudo contra a lista de nomes do jogo.
   - Envia em lotes (a cada 4 s) e, ao sair/fechar (visibilitychange/pagehide), com sendBeacon para não perder.
   - window.__fraihaT: API para o Godot (push / px / sid / vid). window.FRAIHA_TRACK_URL define o servidor (por preset).
   - Pixel (eventos de conversão): mesmo event_id no pixel do navegador e no servidor (Conversions API) → a Meta deduplica.
     Só vai para a Meta se a pessoa ACEITOU os cookies (o pixel respeita a mesma escolha). */
(function () {
  try {
    if (window.__fraihaT) return;
    var URL_T = window.FRAIHA_TRACK_URL || '';
    var T0 = (window.performance && performance.now) ? performance.now() : 0;
    var now = function () { return Math.round(((window.performance && performance.now) ? performance.now() : 0) - T0); };
    var hex = function (n) {
      var a = new Uint8Array(n), s = '';
      try { (window.crypto || window.msCrypto).getRandomValues(a); } catch (e) { for (var i = 0; i < n; i++) a[i] = Math.floor(Math.random() * 256); }
      for (var j = 0; j < n; j++) s += ('0' + a[j].toString(16)).slice(-2);
      return s;
    };
    var ls = function (k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } };
    var ss = function (k, v) { try { if (v === undefined) return sessionStorage.getItem(k); sessionStorage.setItem(k, v); } catch (e) { return null; } };
    var vid = ls('fraiha_vid');
    if (!/^[0-9a-f]{32}$/.test(vid || '')) { vid = hex(16); ls('fraiha_vid', vid); }
    var sid = ss('fraiha_sid'), at = Number(ss('fraiha_sid_at') || 0);
    if (!/^[0-9a-f]{32}$/.test(sid || '') || Date.now() - at > 30 * 60e3) { sid = hex(16); ss('fraiha_sid', sid); }
    ss('fraiha_sid_at', String(Date.now()));
    var q = {};
    try { new URLSearchParams(location.search).forEach(function (v, k) { q[k] = v; }); } catch (e) {}
    var utm = { s: q.utm_source || '', c: q.utm_campaign || '', m: q.utm_medium || '', fb: !!q.fbclid };
    if (!utm.s && !utm.fb) { try { var old = JSON.parse(ss('fraiha_utm') || 'null'); if (old) utm = old; } catch (e) {} } else ss('fraiha_utm', JSON.stringify(utm));
    if (q.fbclid) { try { ls('fraiha_fbc', 'fb.1.' + Date.now() + '.' + String(q.fbclid).slice(0, 180)); } catch (e) {} }
    var queue = [], sentFirst = false, lastScreen = '', lastButton = '', timer = null, dead = false;
    var body = function () {
      var b = { sid: sid, vid: vid, st: now(), e: queue.splice(0, 40) };
      if (!sentFirst) { b.u = utm; b.d = { w: window.innerWidth || 0, h: window.innerHeight || 0, lang: navigator.language || '' }; }
      return JSON.stringify(b);
    };
    var send = function (beacon) {
      if (!URL_T || !queue.length || dead) return;
      var data = body(); sentFirst = true;
      ss('fraiha_sid_at', String(Date.now()));
      try {
        if (beacon && navigator.sendBeacon) { if (navigator.sendBeacon(URL_T, new Blob([data], { type: 'text/plain' }))) return; }
        fetch(URL_T, { method: 'POST', body: data, keepalive: true, headers: { 'content-type': 'text/plain' }, credentials: 'omit', mode: 'cors' }).catch(function () {});
      } catch (e) {}
      if (queue.length) send(beacon);
    };
    var push = function (ev) {
      if (!ev || typeof ev !== 'object') return;
      ev.t = now();
      if (ev.k === 'screen') { if (ev.n === lastScreen) return; lastScreen = ev.n; }
      if (ev.k === 'click') { lastButton = ev.n || ev.id || ''; if (!ev.s) ev.s = lastScreen; }
      queue.push(ev);
      if (queue.length > 200) queue.splice(0, queue.length - 200);
      if (!timer) timer = setTimeout(function () { timer = null; send(false); }, ev.k === 'load' || ev.k === 'exit' ? 50 : 4000);
    };
    var consent = function () { var m = document.cookie.match(/(?:^|; )fraiha_cookies=([^;]+)/); return (m ? m[1] : ls('fraiha_cookies')) === 'sim'; };
    var cookie = function (n) { var m = document.cookie.match(new RegExp('(?:^|; )' + n + '=([^;]+)')); return m ? m[1] : ''; };
    var once = {};
    // evento de conversão: pixel do navegador + servidor (mesmo event_id). Uma vez por visita cada.
    var px = function (name, params, std) {
      if (once[name]) return; once[name] = true;
      var id = hex(12), p = params || {};
      try { if (window.fbq) window.fbq(std ? 'track' : 'trackCustom', name, p, { eventID: id }); } catch (e) {}
      push({ k: 'px', n: name, id: id, c: consent(), m: p.modo || '', r: p.resultado || '', fbp: cookie('_fbp'), fbc: cookie('_fbc') || ls('fraiha_fbc') || '' });
    };
    window.__fraihaT = { sid: sid, vid: vid, push: push, px: px, last: function () { return { s: lastScreen, b: lastButton }; }, flush: function () { send(false); } };
    push({ k: 'load', n: 'start' });
    var slow = setTimeout(function () { if (!window.__fraihaT.loaded) push({ k: 'load', n: 'slow', v: now() / 1000 }); }, 20000);
    window.__fraihaT.done = function () {
      if (window.__fraihaT.loaded) return; window.__fraihaT.loaded = true; clearTimeout(slow);
      push({ k: 'load', n: 'done', v: Math.round(now() / 100) / 10 });
      px('JogoCarregado');
    };
    // erro antes do jogo abrir (WebGL, memória, rede…): só a mensagem curta
    var onErr = function (msg) {
      if (window.__fraihaT.loaded) return;
      var m = String(msg || '').replace(/https?:\/\/\S+/g, '').replace(/[^A-Za-z0-9 _.:\-()\/]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 80);
      push({ k: 'load', n: 'error', c: m || 'erro' });
    };
    window.addEventListener('error', function (e) { onErr(e && (e.message || (e.error && e.error.name))); });
    window.addEventListener('unhandledrejection', function (e) { onErr(e && e.reason && (e.reason.message || e.reason)); });
    var gone = false;   // já avisou a saída (segundo plano e depois fechar = uma saída só)
    var bye = function () { if (dead || gone) return; gone = true; push({ k: 'exit', s: lastScreen, b: lastButton }); send(true); };
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'hidden') bye();
      else if (gone) { gone = false; push({ k: 'back' }); }
    });
    window.addEventListener('pagehide', bye);
    setInterval(function () { if (document.visibilityState !== 'hidden') { push({ k: 'hb' }); } }, 60000);
  } catch (e) {}
})();
