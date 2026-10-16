"""R128 · FRAIHA Admin · LIGAS LIBERADAS na tela Filas (Chromium, Admin servido pelo próprio servidor): cartão
'Ligas · teste visual' com o estado, botão com confirmação (motivo + palavra "ligas"), servidor muda na hora,
Admin Log registra; 1440 px e 393 px. Rodar: tests/admin/run_admin_entitlements_qa.sh (roda junto)."""
import os, sys, json, urllib.request
from playwright.sync_api import sync_playwright
API = "http://127.0.0.1:8140"; ADMIN = API + "/admin/"
SHOTS = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/admin_ent_shots"
os.makedirs(SHOTS, exist_ok=True)
fails = 0
def check(ok, label):
    global fails
    print(("PASS " if ok else "FAIL ") + label)
    if not ok: fails += 1
def api(path):
    req = urllib.request.Request(API + path, headers={"Authorization": "Bearer dev:boss"})
    with urllib.request.urlopen(req, timeout=10) as r: return json.loads(r.read())
leagues = lambda: api("/admin/api/queues")["leagues"]
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={"width": 1440, "height": 900})
    errors = []; pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.goto(ADMIN); pg.select_option("select[name=env]", "local"); pg.fill("input[name=dev]", "boss"); pg.click("button[type=submit]")
    pg.wait_for_selector(".shell", timeout=10000)
    pg.goto(ADMIN + "#/queues"); pg.wait_for_selector("[data-family=leagues]", timeout=8000)
    card = pg.locator("[data-family=leagues]")
    check(not leagues()["enabled"] and "NORMAL" in card.inner_text(), "começa NORMAL (cada um com a liga conquistada)")
    card.locator("[data-action=leagues-toggle]").click(); pg.wait_for_selector(".modal", timeout=3000)
    go = pg.locator(".modal .btn.ok")
    check(go.is_disabled(), "confirmação exige motivo + palavra 'ligas'")
    check("PL, liga e Ranked não mudam" in pg.locator(".modal").inner_text(), "modal explica que é só aparência")
    pg.fill(".modal textarea", "testar o visual das ligas"); pg.fill(".modal input", "ligas"); go.click()
    pg.wait_for_selector("[data-family=leagues]:not(.off)", timeout=8000)
    check(leagues()["enabled"], "servidor: TODAS AS LIGAS LIBERADAS")
    check("TODAS LIBERADAS" in card.inner_text(), "cartão mostra TODAS LIBERADAS e quem ligou")
    pg.screenshot(path=f"{SHOTS}/l01_ligas_liberadas.png", full_page=True)
    pg.set_viewport_size({"width": 393, "height": 852}); pg.wait_for_timeout(300)
    check(pg.evaluate("document.documentElement.scrollWidth") <= 393, "393 px: sem rolagem lateral")
    pg.screenshot(path=f"{SHOTS}/l02_ligas_393.png", full_page=True)
    pg.set_viewport_size({"width": 1440, "height": 900})
    card.locator("[data-action=leagues-toggle]").click(); pg.wait_for_selector(".modal", timeout=3000)
    pg.fill(".modal textarea", "fim do teste"); pg.fill(".modal input", "ligas"); pg.locator(".modal .btn.danger").click()
    pg.wait_for_selector("[data-family=leagues].off", timeout=8000)
    check(not leagues()["enabled"], "voltar ao normal: servidor desligou")
    log = api("/admin/api/audit?limit=10")["items"]
    check([e["action"] for e in log[:2]] == ["leagues.preview_off", "leagues.preview_on"], "Admin Log: liberar e voltar ao normal")
    check(log[1]["reason"] == "testar o visual das ligas", "Admin Log guarda o motivo")
    check(not [e for e in errors if "Uncaught" in e], "sem erro de JS")
    b.close()
print("RESULT", "OK" if fails == 0 else f"{fails} FAIL"); sys.exit(1 if fails else 0)
