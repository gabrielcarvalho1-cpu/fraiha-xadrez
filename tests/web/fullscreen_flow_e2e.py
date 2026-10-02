"""E2E Web (Chromium real, Playwright): tela cheia não pode cair ao navegar entre páginas do jogo.
Uso: sirva uma build Web exportada (COOP/COEP) e rode
    python3 tests/web/fullscreen_flow_e2e.py http://127.0.0.1:8129/ [chromium_path]
Fluxo: Home → 1º clique (entra em tela cheia) → Bots → VOLTAR → Bots → Esc → Perfil → Configurações → Home;
em cada passo document.fullscreenElement continua ativo e o canvas ocupa 100% da viewport.
Depois simula a perda técnica (exitFullscreen): o canvas continua 100% e o próximo clique volta à tela cheia.
Coordenadas: layout desktop 1600x900 (Home de referência)."""
import sys
from playwright.sync_api import sync_playwright

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8129/"
CHROME = sys.argv[2] if len(sys.argv) > 2 else "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
STATE = "(() => { const c = document.getElementById('canvas'); return { fs: !!document.fullscreenElement, el: document.fullscreenElement ? document.fullscreenElement.tagName : '', vw: innerWidth, vh: innerHeight, cw: c.clientWidth, ch: c.clientHeight, lock: (window.__kbLock || 0) }; })()"
HOOK = "(() => { window.__kbLock = 0; if (navigator.keyboard && navigator.keyboard.lock) { const o = navigator.keyboard.lock.bind(navigator.keyboard); navigator.keyboard.lock = (k) => { window.__kbLock++; return o(k); }; } return 1; })()"
fails = 0
def check(ok, label):
    global fails
    print(("PASS " if ok else "FAIL ") + label)
    if not ok: fails += 1

with sync_playwright() as p:
    b = p.chromium.launch(executable_path=CHROME, args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    page = b.new_context(viewport={"width": 1600, "height": 900}).new_page()
    page.goto(URL)
    page.wait_for_selector("#canvas")
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || getComputedStyle(s).display === 'none' || s.style.visibility === 'hidden'; }", timeout=120000)
    page.wait_for_timeout(4000)
    page.evaluate(HOOK)
    def click(x, y, wait=1500):
        page.mouse.click(x, y); page.wait_for_timeout(wait)
    def full(label):
        s = page.evaluate(STATE)
        check(s["fs"] and s["el"] == "HTML", label + ": tela cheia ativa (" + s["el"] + ")")
        check(s["cw"] == s["vw"] and s["ch"] == s["vh"], label + ": canvas = viewport (%dx%d)" % (s["cw"], s["ch"]))
        return s
    s0 = page.evaluate(STATE)
    check(s0["cw"] == s0["vw"] and s0["ch"] == s0["vh"], "antes do gesto: canvas já ocupa 100%% da viewport (%dx%d)" % (s0["cw"], s0["ch"]))
    click(820, 748, 3000)                       # 1º gesto (JOGAR COMO CONVIDADO no login)
    full("1º gesto")
    check(page.evaluate(STATE)["lock"] >= 1, "Esc travado para o jogo (Keyboard Lock) enquanto em tela cheia")
    click(800, 350); full("Home → Bots")
    click(240, 812); full("Bots → VOLTAR → Home")
    click(800, 350); page.keyboard.press("Escape"); page.wait_for_timeout(1200); full("Bots → Esc → Home")
    click(1370, 120); full("Home → Perfil")
    page.keyboard.press("Escape"); page.wait_for_timeout(1000)
    click(800, 660); full("Home → Configurações")
    page.keyboard.press("Escape"); page.wait_for_timeout(1000); full("Configurações → Home")
    # perda técnica da tela cheia
    page.evaluate("document.exitFullscreen()"); page.wait_for_timeout(1200)
    s = page.evaluate(STATE)
    check(not s["fs"] and s["cw"] == s["vw"] and s["ch"] == s["vh"], "tela cheia perdida: jogo continua em 100% da viewport")
    click(1500, 700); full("próximo clique: tela cheia de novo")
    b.close()
print("RESULT", "OK" if fails == 0 else "FALHAS=%d" % fails)
sys.exit(1 if fails else 0)
