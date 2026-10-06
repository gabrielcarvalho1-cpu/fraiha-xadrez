"""FRAIHA Admin V1 · RITMOS DO RANKED na tela Filas (Chromium, Admin servido pelo próprio servidor).
Desativar/ativar um ritmo com confirmação; servidor confirma; jogo recebe a lista (via API). 393 px.
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
def modes():
    return {m["mode"]: m["enabled"] for m in [q for q in api("/admin/api/queues")["queues"] if q["family"] == "ranked"][0]["modes"]}
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={"width": 1440, "height": 900})
    errors = []; pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.goto(ADMIN); pg.select_option("select[name=env]", "local"); pg.fill("input[name=dev]", "boss"); pg.click("button[type=submit]")
    pg.wait_for_selector(".shell", timeout=10000)
    pg.goto(ADMIN + "#/queues"); pg.wait_for_selector(".moderow[data-mode='ranked_3min']", timeout=8000)
    check(pg.locator("[data-family=ranked] .moderow").count() == 4, "Filas: 4 ritmos do Ranked com ON/OFF")
    row = lambda m: pg.locator(f".moderow[data-mode='{m}']")
    for m, word in (("ranked_3min", "relampago"), ("ranked_20min", "convencional")):
        row(m).locator("[data-action=mode-toggle]").click(); pg.wait_for_selector(".modal", timeout=3000)
        go = pg.locator(".modal .btn.danger"); check(go.is_disabled(), f"{m}: confirmação exige motivo + palavra")
        pg.fill(".modal textarea", "liquidez no lançamento"); pg.fill(".modal input", word); go.click()
        pg.wait_for_selector(f".moderow[data-mode='{m}'][data-open='false']", timeout=8000)
    check(modes() == {"ranked_3min": False, "ranked_5min": True, "ranked_10min": True, "ranked_20min": False}, "servidor: Relâmpago OFF, Rápida ON, Normal ON, Convencional OFF")
    pg.screenshot(path=f"{SHOTS}/m01_filas_ritmos.png", full_page=True)
    pg.set_viewport_size({"width": 393, "height": 852}); pg.wait_for_timeout(300)
    check(pg.evaluate("document.documentElement.scrollWidth") <= 393, "393 px: ritmos sem rolagem lateral")
    pg.screenshot(path=f"{SHOTS}/m02_filas_ritmos_393.png", full_page=True)
    pg.set_viewport_size({"width": 1440, "height": 900})
    for m, word in (("ranked_3min", "relampago"), ("ranked_20min", "convencional")):
        row(m).locator("[data-action=mode-toggle]").click(); pg.wait_for_selector(".modal", timeout=3000)
        pg.fill(".modal textarea", "reabrindo"); pg.fill(".modal input", word); pg.locator(".modal .btn.ok").click()
        pg.wait_for_selector(f".moderow[data-mode='{m}'][data-open='true']", timeout=8000)
    check(all(modes().values()), "reativados: os 4 ON")
    log = api("/admin/api/audit?limit=20")["items"]
    check([e["action"] for e in log[:4]] == ["queue.mode_enable"] * 2 + ["queue.mode_disable"] * 2, "Admin Log: queue.mode_disable/enable")
    check(not [e for e in errors if "Uncaught" in e], "sem erro de JS")
    b.close()
print("RESULT", "OK" if fails == 0 else f"{fails} FAIL"); sys.exit(1 if fails else 0)
