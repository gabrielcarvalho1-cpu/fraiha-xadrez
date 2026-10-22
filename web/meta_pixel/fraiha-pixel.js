/* FRAIHA · Meta Pixel com aviso de cookies (LGPD).
   Fonte única: este arquivo é usado como está na landing (fraihaxadrez.com) e vai minificado
   no html/head_include dos presets Web do jogo (jogar.fraihaxadrez.com).
   - O script da Meta (fbevents.js) SÓ carrega depois que a pessoa clica em ACEITAR.
   - Antes da escolha, os eventos ficam numa fila; ACEITAR envia, RECUSAR descarta.
   - A escolha vale para os dois endereços (cookie no domínio .fraihaxadrez.com) por 1 ano.
   - Nenhum dado pessoal (e-mail, nome, nickname) é enviado por aqui.
   - API para o resto do site/jogo: window.fbq(...) (padrão da Meta),
     window.fraihaTrack(tipo, nome, params) e window.fraihaTrackOnce(tipo, nome, chave). */
(function () {
  try {
    if (window.__fraihaPixel) return;
    window.__fraihaPixel = true;
    var PIXEL_ID = '1131165439457023';
    var KEY = 'fraiha_cookies';

    var read = function () {
      var m = document.cookie.match(/(?:^|; )fraiha_cookies=([^;]+)/);
      if (m) return m[1];
      try { return localStorage.getItem(KEY); } catch (e) { return null; }
    };
    var save = function (v) {
      var dom = /(^|\.)fraihaxadrez\.com$/.test(location.hostname) ? ';domain=.fraihaxadrez.com' : '';
      var sec = location.protocol === 'https:' ? ';Secure' : '';
      document.cookie = KEY + '=' + v + ';path=/;max-age=31536000;SameSite=Lax' + sec + dom;
      try { localStorage.setItem(KEY, v); } catch (e) {}
    };

    // Fila padrão da Meta: guarda as chamadas até o fbevents.js chegar.
    if (!window.fbq) {
      var n = window.fbq = function () { n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments); };
      if (!window._fbq) window._fbq = n;
      n.push = n; n.loaded = true; n.version = '2.0'; n.queue = [];
    }
    var loaded = false;
    var load = function () {
      if (loaded) return; loaded = true;
      var s = document.createElement('script');
      s.async = true; s.src = 'https://connect.facebook.net/en_US/fbevents.js';
      (document.head || document.documentElement).appendChild(s);
    };
    var off = function () {
      try { if (window.fbq && window.fbq.queue) window.fbq.queue.length = 0; } catch (e) {}
      window.fbq = function () {}; window._fbq = window.fbq;
    };

    window.fraihaTrack = function (kind, name, params) {
      try { window.fbq(kind === 'track' ? 'track' : 'trackCustom', name, params || {}); } catch (e) {}
    };
    window.fraihaTrackOnce = function (kind, name, key) {
      try {
        var k = 'fraiha_ev_' + (key || name);
        if (localStorage.getItem(k)) return;
        localStorage.setItem(k, '1');
      } catch (e) {}
      window.fraihaTrack(kind, name);
    };

    window.fbq('init', PIXEL_ID);
    window.fbq('track', 'PageView');

    var choice = read();
    if (choice === 'sim') { load(); return; }
    if (choice === 'nao') { off(); return; }

    // Sem escolha ainda: faixa discreta no rodapé.
    var show = function () {
      if (document.getElementById('fx-cookies')) return;
      var st = document.createElement('style');
      st.textContent =
        '#fx-cookies{position:fixed;left:12px;right:12px;bottom:12px;z-index:2147483000;max-width:640px;margin:0 auto;' +
        'background:rgba(16,12,8,.96);color:#f3e6c8;border:1px solid #c9a050;border-radius:10px;padding:12px 14px;' +
        'font:14px/1.4 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;display:flex;gap:12px;align-items:center;flex-wrap:wrap;' +
        'box-shadow:0 6px 24px rgba(0,0,0,.5)}' +
        '#fx-cookies p{margin:0;flex:1 1 260px}' +
        '#fx-cookies button{font:inherit;font-weight:700;border-radius:7px;padding:8px 14px;cursor:pointer;border:1px solid #c9a050}' +
        '#fx-cookies .fx-ok{background:#c9a050;color:#1a1208}' +
        '#fx-cookies .fx-no{background:transparent;color:#f3e6c8}';
      var bar = document.createElement('div');
      bar.id = 'fx-cookies';
      bar.setAttribute('role', 'dialog');
      bar.setAttribute('aria-label', 'Aviso de cookies');
      bar.innerHTML = '<p>Usamos cookies e o Pixel da Meta para medir visitas e melhorar nossos anúncios. Você escolhe.</p>' +
        '<button type="button" class="fx-no">Recusar</button><button type="button" class="fx-ok">Aceitar</button>';
      var close = function (ev) { if (ev) { ev.preventDefault(); ev.stopPropagation(); } try { bar.remove(); st.remove(); } catch (e) {} };
      bar.querySelector('.fx-ok').addEventListener('click', function (ev) { save('sim'); load(); close(ev); });
      bar.querySelector('.fx-no').addEventListener('click', function (ev) { save('nao'); off(); close(ev); });
      ['pointerdown', 'mousedown', 'touchstart', 'keydown'].forEach(function (t) {
        bar.addEventListener(t, function (ev) { ev.stopPropagation(); });
      });
      document.head.appendChild(st);
      document.body.appendChild(bar);
    };
    if (document.body) show(); else document.addEventListener('DOMContentLoaded', show);
  } catch (e) {}
})();
