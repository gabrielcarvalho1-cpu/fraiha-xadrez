"""FRAIHA Admin · CASUAL na tela Filas (Chromium, Admin servido pelo próprio servidor): os 4 ritmos REAIS do
Casual com status, na fila, maior espera, tempo médio, partidas e jogadores ativos e ATIVAR/DESATIVAR com
confirmação; Casual inteiro OFF/ON; Admin Log. 1440 px e 393 px.
Rodar: tests/admin/run_admin_entitlements_qa.sh (roda junto)."""
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
def casual():
    return [q for q in api("/admin/api/queues")["queues"] if q["family"] == "casual"][0]
def modes():
    return {m["mode"]: m["enabled"] for m in casual()["modes"]}
ALL = ["casual_3min", "casual_5min", "casual_10min", "casual_20min"]
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={"width": 1440, "height": 900})
    errors = []; pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.goto(ADMIN); pg.select_option("select[name=env]", "local"); pg.fill("input[name=dev]", "boss"); pg.click("button[type=submit]")
    pg.wait_for_selector(".shell", timeout=10000)
    pg.goto(ADMIN + "#/queues"); pg.wait_for_selector(".moderow[data-mode='casual_3min']", timeout=8000)
    card = pg.locator("[data-family=casual]")
    check(card.locator(".moderow").count() == 4, "Filas: 4 ritmos do Casual com ON/OFF")
    check([card.locator(".moderow").nth(i).get_attribute("data-mode") for i in range(4)] == ALL, "ritmos = filas reais do servidor (3/5/10/20)")
    txt = card.inner_text()
    for k in ("Jogadores na fila", "Maior espera atual", "Tempo médio (1 h)", "Partidas ativas", "Jogadores ativos no modo"): check(k in txt, "cartão Casual mostra: " + k)
    stats = card.locator(".moderow .modestats").first.inner_text()
    check("na fila" in stats or "fila vazia" in stats, "linha do ritmo mostra fila/partidas/jogando: " + stats)
    check("partida" in stats and "jogando" in stats, "linha do ritmo mostra partidas e jogadores ativos")
    row = lambda m: pg.locator(f".moderow[data-mode='{m}']")
    for m, word in (("casual_3min", "relampago"), ("casual_20min", "convencional")):
        row(m).locator("[data-action=mode-toggle]").click(); pg.wait_for_selector(".modal", timeout=3000)
        go = pg.locator(".modal .btn.danger"); check(go.is_disabled(), f"{m}: confirmação exige motivo + palavra")
        check("JOGAR ONLINE" in pg.locator(".modal").inner_text(), f"{m}: modal explica o efeito na tela JOGAR ONLINE")
        pg.fill(".modal textarea", "liquidez casual"); pg.fill(".modal input", word); go.click()
        pg.wait_for_selector(f".moderow[data-mode='{m}'][data-open='false']", timeout=8000)
    check(modes() == {"casual_3min": False, "casual_5min": True, "casual_10min": True, "casual_20min": False}, "servidor: Relâmpago OFF, Rápida ON, Normal ON, Convencional OFF")
    pg.screenshot(path=f"{SHOTS}/c01_casual_ritmos.png", full_page=True)
    pg.set_viewport_size({"width": 393, "height": 852}); pg.wait_for_timeout(300)
    check(pg.evaluate("document.documentElement.scrollWidth") <= 393, "393 px: ritmos do Casual sem rolagem lateral")
    pg.screenshot(path=f"{SHOTS}/c02_casual_ritmos_393.png", full_page=True)
    pg.set_viewport_size({"width": 1440, "height": 900})
    for m, word in (("casual_3min", "relampago"), ("casual_20min", "convencional")):
        row(m).locator("[data-action=mode-toggle]").click(); pg.wait_for_selector(".modal", timeout=3000)
        pg.fill(".modal textarea", "reabrindo"); pg.fill(".modal input", word); pg.locator(".modal .btn.ok").click()
        pg.wait_for_selector(f".moderow[data-mode='{m}'][data-open='true']", timeout=8000)
    check(all(modes().values()), "reativados: os 4 ON")
    # Casual inteiro
    card.locator("[data-action=toggle]").click(); pg.wait_for_selector(".modal", timeout=3000)
    pg.fill(".modal textarea", "manutenção"); pg.fill(".modal input", "casual"); pg.locator(".modal .btn.danger").click()
    pg.wait_for_selector("[data-family=casual].off", timeout=8000)
    check(not casual()["enabled"] and all(not m["open"] for m in casual()["modes"]), "Casual inteiro OFF: nenhum ritmo aberto no servidor")
    check("inteiro DESATIVADO" in card.inner_text(), "Admin avisa que o Casual inteiro está desativado")
    pg.screenshot(path=f"{SHOTS}/c03_casual_off.png", full_page=True)
    card.locator("[data-action=toggle]").click(); pg.wait_for_selector(".modal", timeout=3000)
    pg.fill(".modal textarea", "volta"); pg.fill(".modal input", "casual"); pg.locator(".modal .btn.ok").click()
    pg.wait_for_selector("[data-family=casual]:not(.off)", timeout=8000)
    log = api("/admin/api/audit?limit=20")["items"]
    check([e["action"] for e in log[:6]] == ["queue.enable", "queue.disable"] + ["queue.mode_enable"] * 2 + ["queue.mode_disable"] * 2, "Admin Log: ritmos + Casual inteiro")
    check(log[5]["target"] == {"family": "casual", "mode": "casual_3min"} and log[5]["reason"] == "liquidez casual", "Admin Log guarda ritmo e motivo")
    pg.goto(ADMIN + "#/audit"); pg.wait_for_selector("table", timeout=8000)
    check("CASUAL 3min" in pg.inner_text("body"), "Admin Log na tela: 'CASUAL 3min'")
    check(not [e for e in errors if "Uncaught" in e], "sem erro de JS")
    b.close()
print("RESULT", "OK" if fails == 0 else f"{fails} FAIL"); sys.exit(1 if fails else 0)
