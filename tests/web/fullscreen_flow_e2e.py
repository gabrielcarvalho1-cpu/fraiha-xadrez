"""E2E Web (Chromium real, Playwright) — tela cheia R29.2 (comportamento natural do navegador).
Uso: sirva uma build Web exportada (COOP/COEP) e rode
    python3 tests/web/fullscreen_flow_e2e.py http://127.0.0.1:8129/ [chromium_path]
Cobre:
 1 R42.2: só o botão entra em tela cheia (nada automático)        6 Home -> Bots -> VOLTAR mantém a tela cheia
 2 botão de tela cheia SAI                                   7 Bots + Esc em tela cheia: sai da tela cheia e NÃO navega
 3 Esc em tela cheia sai                                     8 2º Esc fora da tela cheia volta a página (regra antiga)
 4 depois de sair, clicar no jogo NÃO volta sozinho          9 SAIR: sai da tela cheia e vai para https://fraihaxadrez.com/
 5 botão de tela cheia entra de novo                        10 canvas = 100% da viewport depois de sair
Observação: em automação o Esc é uma tecla sintética (o navegador não a usa para sair da tela cheia);
quem sai é o próprio jogo ao receber o Esc em tela cheia — o mesmo caminho do Esc real quando a tecla chega à página.
Coordenadas: layout desktop 1600x900 (Home de referência)."""
import sys
from playwright.sync_api import sync_playwright

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8129/"
CHROME = sys.argv[2] if len(sys.argv) > 2 else "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
STATE = "(() => { const c = document.getElementById('canvas'); return { fs: !!document.fullscreenElement, vw: innerWidth, vh: innerHeight, cw: c.clientWidth, ch: c.clientHeight }; })()"
FS_BTN = (465, 47)          # botão de tela cheia (ao lado do som)
BOT_ITEM = (800, 350)       # JOGAR CONTRA O COMPUTADOR
BOT_BACK = (240, 812)       # VOLTAR À HOME da página dos bots
SAIR = (800, 838)          # R32: SAIR é a 10ª linha do menu
CONFIRM = (640, 566)        # CONFIRMAR do diálogo
EMPTY = (1450, 700)         # área sem botão (cenário)
fails = 0
log = []
def check(ok, label):
    global fails
    print(("PASS " if ok else "FAIL ") + label)
    if not ok: fails += 1

with sync_playwright() as p:
    b = p.chromium.launch(executable_path=CHROME, args=["--use-gl=swiftshader", "--enable-unsafe-swiftshader"])
    ctx = b.new_context(viewport={"width": 1600, "height": 900})
    page = ctx.new_page()
    went = []
    ctx.route("https://fraihaxadrez.com/**", lambda route: (went.append(route.request.url), route.fulfill(status=200, content_type="text/html", body="<title>site</title>site")))
    page.goto(URL)
    page.wait_for_selector("#canvas")
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || getComputedStyle(s).display === 'none' || s.style.visibility === 'hidden'; }", timeout=120000)
    page.wait_for_timeout(4000)
    def click(xy, wait=1500):
        page.mouse.click(*xy); page.wait_for_timeout(wait)
    def st(tag):
        s = page.evaluate(STATE); log.append((tag, s)); return s
    def full100(s): return s["cw"] == s["vw"] and s["ch"] == s["vh"]

    s = st("ANTES FULLSCREEN")
    check(not s["fs"] and full100(s), "antes do gesto: sem tela cheia e canvas em 100%% (%dx%d)" % (s["cw"], s["ch"]))
    click((820, 748), 3000)                    # JOGAR COMO CONVIDADO (1º clique da sessão)
    s = st("1º CLIQUE")
    check(not s["fs"] and full100(s), "1. R42.2: 1º clique NÃO entra em tela cheia sozinho")
    click(EMPTY); click(BOT_ITEM); click(BOT_BACK)
    check(not st("VÁRIOS CLIQUES")["fs"], "1b. R42.2: navegar pela Home não entra em tela cheia")
    click(FS_BTN, 2500)
    s = st("EM FULLSCREEN")
    check(s["fs"] and full100(s), "1c. botão de expandir entra em tela cheia")
    click(FS_BTN)
    s = st("APÓS BOTÃO SAIR")
    check(not s["fs"], "2. botão de tela cheia SAI da tela cheia")
    check(full100(s), "10. canvas 100%% após sair (%dx%d de %dx%d)" % (s["cw"], s["ch"], s["vw"], s["vh"]))
    click(EMPTY); click(EMPTY)
    s = st("APÓS NOVO CLIQUE")
    check(not s["fs"], "4. depois de sair, clicar no jogo NÃO volta à tela cheia sozinho")
    click(FS_BTN)
    s = st("REENTRADA MANUAL")
    check(s["fs"], "5. botão de tela cheia entra de novo")
    page.keyboard.press("Escape"); page.wait_for_timeout(1200)
    s = st("APÓS ESC")
    check(not s["fs"] and full100(s), "3. Esc em tela cheia sai da tela cheia (canvas 100%)")
    click(EMPTY)
    check(not st("CLIQUE APÓS ESC")["fs"], "4b. clique depois do Esc também não reentra")
    click(FS_BTN)
    click(BOT_ITEM); click(BOT_BACK)
    s = st("BOTS -> VOLTAR")
    check(s["fs"], "6. Home -> Bots -> VOLTAR mantém a tela cheia")
    click(BOT_ITEM)
    page.screenshot(path="/tmp/fs_e2e_bots.png")
    page.keyboard.press("Escape"); page.wait_for_timeout(1200)
    s = st("BOTS + ESC")
    page.screenshot(path="/tmp/fs_e2e_bots_esc.png")
    check(not s["fs"], "7a. Bots + Esc em tela cheia: sai da tela cheia")
    # a página dos bots continua: o 2º Esc (fora da tela cheia) é que volta
    page.keyboard.press("Escape"); page.wait_for_timeout(1200)
    page.screenshot(path="/tmp/fs_e2e_bots_esc2.png")
    from PIL import Image, ImageChops
    a = Image.open("/tmp/fs_e2e_bots.png").convert("RGB").crop((600, 300, 1000, 500))
    e1 = Image.open("/tmp/fs_e2e_bots_esc.png").convert("RGB").crop((600, 300, 1000, 500))
    e2 = Image.open("/tmp/fs_e2e_bots_esc2.png").convert("RGB").crop((600, 300, 1000, 500))
    diff = lambda x, y: sum(ImageChops.difference(x, y).convert("L").point(lambda v: 255 if v > 40 else 0).histogram()[255:])
    check(diff(a, e1) < 2000, "7b. Bots + Esc em tela cheia NÃO navegou (ainda na página dos bots)")
    check(diff(e1, e2) > 2000, "8. 2º Esc fora da tela cheia volta para a Home (regra antiga)")
    click(FS_BTN)
    check(st("ANTES DO SAIR")["fs"], "9a. em tela cheia antes do SAIR")
    click(SAIR); click(CONFIRM, 2500)
    check(any(u.rstrip("/") == "https://fraihaxadrez.com" for u in went) or page.url.startswith("https://fraihaxadrez.com"), "9b. SAIR foi para https://fraihaxadrez.com/ (%s)" % (went[:1] or page.url))
    b.close()
print("SEQUÊNCIA:")
for t, s in log: print("  %-18s fs=%s canvas=%dx%d viewport=%dx%d" % (t, s["fs"], s["cw"], s["ch"], s["vw"], s["vh"]))
print("RESULT", "OK" if fails == 0 else "FALHAS=%d" % fails)
sys.exit(1 if fails else 0)
