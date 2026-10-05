"""R40 · Formulário de cartão dentro do jogo (monetization/card_form_web.gd) no Chromium real.
Usa o JS de verdade do arquivo .gd (JS_OPEN/JS_CLOSE e os comandos de resolve/reject) e um SDK do
Mercado Pago FALSO (a rede real não é usada). Opcional: QA_URL=<build Web servida> roda dentro da
página do jogo exportado (por cima do canvas do Godot).
Rodar: python3 tests/web/card_form_e2e.py"""
import json, os, re, sys
from playwright.sync_api import sync_playwright

SRC = open(os.path.join(os.path.dirname(__file__), "../../monetization/card_form_web.gd"), encoding="utf-8").read()
def block(name):
    return re.search(name + r' := """(.*?)"""', SRC, re.S).group(1)
JS_OPEN, JS_CLOSE = block("JS_OPEN"), block("JS_CLOSE")
RESOLVE_OK = re.search(r'func resolve_ok\(\):\n\s+if available\(\): JavaScriptBridge\.eval\("(.*?)"\)\n', SRC).group(1)
REJECT = re.search(r'func resolve_reject.*?JavaScriptBridge\.eval\("(.*?)"\)\n', SRC, re.S).group(1)
SDK_URL = re.search(r'const SDK_URL := "(.*?)"', SRC).group(1)

FAKE_SDK = r"""
window.__mpLog = [];
window.MercadoPago = class {
  constructor(pk, opts) { window.__mpLog.push({ pk, opts }); }
  bricks() { return { create: (kind, id, s) => new Promise((ok) => {
    window.__mpLog.push({ kind, id, amount: s.initialization.amount, email: s.initialization.payer.email, maxInst: s.customization.paymentMethods.maxInstallments });
    const host = document.getElementById(id);
    host.innerHTML = '<input id="fake-name" placeholder="Nome"><button id="fake-ok">Pagar OK</button><button id="fake-no">Pagar recusado</button><div id="fake-state">idle</div>';
    const pay = (tok) => { document.getElementById('fake-state').textContent = 'processing';
      s.callbacks.onSubmit({ token: tok, payment_method_id: 'master', issuer_id: 24, installments: 1, transaction_amount: s.initialization.amount,
        payer: { email: s.initialization.payer.email, identification: { type: 'CPF', number: '12345678909' } } }, { bin: '503143' })
       .then(() => document.getElementById('fake-state').textContent = 'resolved')
       .catch(() => document.getElementById('fake-state').textContent = 'rejected'); };
    document.getElementById('fake-ok').onclick = () => pay('tok-approve-web-1');
    document.getElementById('fake-no').onclick = () => pay('tok-reject-web-1');
    setTimeout(() => s.callbacks.onReady(), 50);
    ok({ unmount: () => { window.__mpLog.push({ unmount: true }); host.innerHTML = ''; } });
  }) }; }
};
"""
checks = failures = 0
def check(ok, label):
    global checks, failures
    checks += 1; failures += 0 if ok else 1
    print(("PASS " if ok else "FAIL ") + label)

def cfg(title="CLUB FRAIHA", price="R$ 19,90 · 30 DIAS DE CLUB"):
    return json.dumps({"pk": "APP_USR-public-key-teste", "amount": 19.9, "email": "cartao@teste.local", "title": title, "price": price, "sdk": SDK_URL})

def prep(pg):
    pg.evaluate("""() => { window.__ev = []; window.fraihaCardCb = (k, v) => window.__ev.push([k, v]);
        window.__docKeys = 0; document.addEventListener('keydown', () => window.__docKeys++); window.MP_DEVICE_SESSION_ID = 'armor.dev123'; }""")

def events(pg, kind):
    return [e for e in pg.evaluate("() => window.__ev") if e[0] == kind]

URL = os.environ.get("QA_URL", "")
with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/opt/pw-browsers/chromium-1194/chrome-linux/chrome")
    for vw, vh, tag in [(1600, 900, "desktop"), (390, 844, "celular retrato"), (844, 390, "celular paisagem")]:
        ctx = b.new_context(viewport={"width": vw, "height": vh})
        mode = {"sdk": "ok"}
        def sdk_route(route):
            if mode["sdk"] == "fail": return route.abort()
            if mode["sdk"] == "empty": return route.fulfill(status=200, content_type="application/javascript", body="/* sem MercadoPago */")
            route.fulfill(status=200, content_type="application/javascript", body=FAKE_SDK)
        ctx.route(SDK_URL, sdk_route)
        pg = ctx.new_page()
        errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        if URL:
            pg.goto(URL); pg.wait_for_selector("#canvas"); pg.wait_for_timeout(3000)
        else:
            pg.set_content('<html><body style="margin:0;background:#111"><canvas id="canvas" width="800" height="600" style="width:100vw;height:100vh;display:block"></canvas></body></html>')
        prep(pg)
        # ---------- abre ----------
        pg.evaluate(JS_OPEN.replace("__CFG__", cfg(title='CLUB <img src=x onerror="window.__xss=1">')))
        pg.wait_for_function("() => window.__ev.some(e => e[0] === 'ready')", timeout=8000)
        log = pg.evaluate("() => window.__mpLog")
        check(log[0]["pk"] == "APP_USR-public-key-teste" and log[0]["opts"]["locale"] == "pt-BR" and log[1]["kind"] == "cardPayment" and abs(log[1]["amount"] - 19.9) < 1e-9 and log[1]["email"] == "cartao@teste.local" and log[1]["maxInst"] == 1,
              f"[{tag}] SDK do Mercado Pago carregado: Public Key, pt-BR, Card Payment Brick com R$ 19,90, e-mail e 1x")
        check(pg.is_visible("#fraiha-card-overlay") and not pg.is_visible("#fraiha-card-loading") and pg.text_content("#fraiha-card-price").startswith("R$ 19,90"), f"[{tag}] janela por cima do jogo, com preço; 'carregando' some quando o formulário fica pronto")
        check(pg.evaluate("() => !window.__xss") and "<img" in pg.text_content("#fraiha-card-title"), f"[{tag}] texto do título não vira HTML (sem injeção)")
        box = pg.evaluate("() => { const r = document.getElementById('fraiha-card-box').getBoundingClientRect(); return [r.left, r.right, document.documentElement.scrollWidth]; }")
        check(box[0] >= 0 and box[1] <= vw and box[2] <= vw, f"[{tag}] cabe na largura da tela (sem rolagem lateral)")
        top = pg.evaluate("() => { const r = document.getElementById('fraiha-card-box').getBoundingClientRect(); const el = document.elementFromPoint(r.left + 20, r.top + 20); return !!el.closest('#fraiha-card-overlay'); }")
        check(top, f"[{tag}] clique na janela cai no formulário, não no jogo por baixo")
        pg.click("#fake-name"); pg.keyboard.type("Ana Silva")
        if not URL:  # no jogo exportado isso é coberto pelo QA do fluxo completo (o Godot solta o foco ao abrir)
            check(pg.evaluate("() => window.__docKeys") == 0, f"[{tag}] teclas digitadas no formulário não vão para o jogo")
        # ---------- recusado ----------
        pg.click("#fake-no")
        pg.wait_for_function("() => window.__ev.some(e => e[0] === 'submit')")
        sub = json.loads(events(pg, "submit")[0][1])
        check(sub == {"token": "tok-reject-web-1", "payment_method_id": "master", "issuer_id": "24", "id_type": "CPF", "id_number": "12345678909", "device_id": "armor.dev123"},
              f"[{tag}] o jogo recebe só token + bandeira + banco + CPF + device id (nunca número/CVV)")
        check(pg.text_content("#fake-state") == "processing", f"[{tag}] formulário fica 'processando' até o servidor responder")
        pg.evaluate("() => " + REJECT)
        pg.evaluate("""() => { const m = document.getElementById('fraiha-card-msg'); m.textContent = 'Saldo ou limite insuficiente'; m.style.display = 'block'; }""")
        pg.wait_for_function("() => document.getElementById('fake-state').textContent === 'rejected'")
        check(pg.is_visible("#fraiha-card-msg") and "Saldo" in pg.text_content("#fraiha-card-msg"), f"[{tag}] recusado: formulário liberado para tentar de novo, com o motivo no topo")
        # ---------- aprovado ----------
        pg.click("#fake-ok")
        pg.wait_for_function("() => window.__ev.filter(e => e[0] === 'submit').length === 2")
        pg.evaluate("() => " + RESOLVE_OK)
        pg.wait_for_function("() => document.getElementById('fake-state').textContent === 'resolved'")
        check(json.loads(events(pg, "submit")[1][1])["token"] == "tok-approve-web-1", f"[{tag}] aprovado: segundo envio com o novo token e o formulário conclui")
        # ---------- fechar ----------
        pg.click("#fraiha-card-close")
        check(len(events(pg, "close")) == 1, f"[{tag}] botão ✕ avisa o jogo para fechar")
        pg.keyboard.press("Escape")
        check(len(events(pg, "close")) == 2, f"[{tag}] tecla Esc também fecha")
        pg.evaluate(JS_CLOSE)
        check(not pg.query_selector("#fraiha-card-overlay") and any(x.get("unmount") for x in pg.evaluate("() => window.__mpLog")), f"[{tag}] fechar remove a janela e desmonta o formulário do Mercado Pago")
        pg.keyboard.press("Escape")
        check(len(events(pg, "close")) == 2, f"[{tag}] depois de fechado, Esc não dispara mais nada")
        # ---------- reabrir (SDK já carregado) ----------
        pg.evaluate("() => { window.__ev = []; }")
        pg.evaluate(JS_OPEN.replace("__CFG__", cfg()))
        pg.wait_for_function("() => window.__ev.some(e => e[0] === 'ready')", timeout=8000)
        check(len(pg.query_selector_all("#fraiha-card-overlay")) == 1 and len(pg.query_selector_all("#fraiha-mp-sdk")) == 1, f"[{tag}] reabrir: uma janela só e o SDK não é carregado duas vezes")
        pg.evaluate(JS_CLOSE)
        ctx.close()
        # ---------- SDK não carrega → página do Mercado Pago ----------
        for m, why in [("fail", "script"), ("empty", "sdk")]:
            ctx = b.new_context(viewport={"width": vw, "height": vh})
            ctx.route(SDK_URL, lambda route, m=m: route.abort() if m == "fail" else route.fulfill(status=200, content_type="application/javascript", body="/* nada */"))
            pg = ctx.new_page()
            pg.set_content('<html><body><canvas id="canvas"></canvas></body></html>')
            prep(pg)
            pg.evaluate(JS_OPEN.replace("__CFG__", cfg()))
            pg.wait_for_function("() => window.__ev.some(e => e[0] === 'load_failed')", timeout=8000)
            check(events(pg, "load_failed")[0][1] in ("script", "sdk"), f"[{tag}] SDK {'bloqueado' if m == 'fail' else 'inválido'}: o jogo é avisado (load_failed) e usa a página do Mercado Pago")
            ctx.close()
        check(not errs, f"[{tag}] sem erros de JavaScript na página")
    b.close()
print(f"RESULT {checks - failures}/{checks}" + (" OK" if failures == 0 else f" FALHAS={failures}"))
sys.exit(1 if failures else 0)
