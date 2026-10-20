# R171 SEC-011: abre o build Web real com o CSP em modo de BLOQUEIO (mais rígido que o report-only) e lista violações.
# Uso: python3 tests/web/csp_e2e.py <pasta do build Web com engines/ voice/ gl_recovery/> <arquivo com a política (CSP_POLICY do Worker)>
import http.server, threading, json, sys, time, functools, os
from playwright.sync_api import sync_playwright
SITE = sys.argv[1]; POLICY = open(sys.argv[2]).read()
POLICY = POLICY.replace("report-uri https://fraiha-xadrez.onrender.com/csp-report", "report-uri /csp-report")
reports = []
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        if self.path.split('?')[0] in ('/', '/index.html'):
            self.send_header('Content-Security-Policy', POLICY)
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        super().end_headers()
    def do_POST(self):
        n = int(self.headers.get('content-length', 0)); reports.append(self.rfile.read(n).decode('utf8', 'replace'))
        self.send_response(204); self.end_headers()
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 8177), functools.partial(H, directory=SITE))
threading.Thread(target=srv.serve_forever, daemon=True).start()
with sync_playwright() as p:
    b = p.chromium.launch(args=['--autoplay-policy=no-user-gesture-required', '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', '--enable-unsafe-swiftshader', '--use-gl=swiftshader'])
    pg = b.new_page(viewport={'width': 412, 'height': 860}, is_mobile=True, has_touch=True)
    errs = []
    pg.on('console', lambda m: errs.append(m.type + ': ' + m.text[:200]) if m.type in ('error', 'warning') else None)
    pg.add_init_script("window.__csp=[];document.addEventListener('securitypolicyviolation',e=>window.__csp.push([e.effectiveDirective,e.blockedURI,e.sourceFile+':'+e.lineNumber]));")
    pg.goto('http://127.0.0.1:8177/index.html')
    time.sleep(30)
    # motor (Worker + WASM), SDK de voz local (Agora), SDK do Mercado Pago, campo HTML (teclado do celular), áudio
    res = pg.evaluate("""async () => {
      const out = {};
      try { out.godot = !!document.querySelector('canvas') && !!window.Engine; } catch (e) { out.godot = String(e); }
      out.engine = await new Promise(r => { try { const w = new Worker('engines/stockfish-19-lite-single.js'); const t = setTimeout(() => r('timeout'), 20000);
        w.onmessage = e => { if (String(e.data).includes('uciok')) { clearTimeout(t); r('uciok'); w.terminate(); } }; w.onerror = e => r('error ' + e.message); w.postMessage('uci'); } catch (e) { r('throw ' + e); } });
      out.agora = await new Promise(r => { const s = document.createElement('script'); s.src = 'voice/AgoraRTC_N-4.24.8.js'; s.onload = () => r(!!window.AgoraRTC && window.AgoraRTC.VERSION); s.onerror = () => r('load error'); document.head.appendChild(s); });
      try { const c = window.AgoraRTC.createClient({ mode: 'rtc', codec: 'vp8' }); out.agoraClient = !!c;
        const tr = await window.AgoraRTC.createMicrophoneAudioTrack().then(t => { const ok = !!t; t.close(); return ok; }).catch(e => 'mic ' + e.message); out.agoraMic = tr; } catch (e) { out.agoraClient = String(e); }
      out.mp = await new Promise(r => { const s = document.createElement('script'); s.src = 'https://sdk.mercadopago.com/js/v2'; const t = setTimeout(() => r('timeout'), 15000); s.onload = () => { clearTimeout(t); r(!!window.MercadoPago); }; s.onerror = () => { clearTimeout(t); r('load error (rede ou CSP)'); }; document.head.appendChild(s); });
      try { const i = document.createElement('input'); i.type = 'text'; i.style.cssText = 'position:fixed;left:0;top:0;opacity:0.01'; document.body.appendChild(i); i.focus(); out.input = document.activeElement === i; i.remove(); } catch (e) { out.input = String(e); }
      try { const ctx = new (window.AudioContext || window.webkitAudioContext)(); await ctx.resume(); out.audio = ctx.state; } catch (e) { out.audio = String(e); }
      try { out.evalOk = eval('1+1') === 2; } catch (e) { out.evalOk = String(e); }
      try { out.wsBlocked = await new Promise(r => { try { const ws = new WebSocket('wss://fraiha-xadrez.onrender.com'); ws.onerror = () => r('erro de rede (esperado sem internet)'); ws.onopen = () => { r('aberto'); ws.close(); }; setTimeout(() => r('pendente'), 8000); } catch (e) { r('CSP: ' + e); } }); } catch (e) { out.wsBlocked = String(e); }
      try { await fetch('https://exemplo-malicioso.example/x').catch(() => {}); } catch (e) {}
      return out;
    }""")
    time.sleep(3)
    pg.screenshot(path=os.path.join(os.path.dirname(sys.argv[2]), 'csp_shot.png'))
    v = pg.evaluate('window.__csp')
    print(json.dumps({'checks': res, 'violations': v, 'reports_received': len(reports), 'console': errs[:25]}, indent=1, ensure_ascii=False))
    b.close()
srv.shutdown()
