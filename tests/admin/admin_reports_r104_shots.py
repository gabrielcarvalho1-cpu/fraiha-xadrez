"""R104 · prints da tela DENÚNCIAS do Admin (servidor DEV local). Uso: python3 tests/admin/admin_reports_r104_shots.py <pasta>"""
import os, sys
from playwright.sync_api import sync_playwright
ADMIN = "http://127.0.0.1:8140/admin/"
SHOTS = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/r104_admin"
os.makedirs(SHOTS, exist_ok=True)
with sync_playwright() as p:
    b = p.chromium.launch()
    for name, vp in [("pc", {"width": 1440, "height": 900}), ("cel", {"width": 393, "height": 852})]:
        pg = b.new_page(viewport=vp)
        pg.goto(ADMIN); pg.select_option("select[name=env]", "local"); pg.fill("input[name=dev]", "boss"); pg.click("button[type=submit]")
        pg.wait_for_selector(".shell", timeout=10000)
        pg.goto(ADMIN + "#/reports"); pg.wait_for_timeout(1500)
        pg.screenshot(path=f"{SHOTS}/{name}_01_denuncias.png", full_page=True)
        if name == "pc":
            pg.locator("button", has_text="Suspender 7 dias").first.click(); pg.wait_for_timeout(500)
            pg.screenshot(path=f"{SHOTS}/{name}_02_suspender.png")
            pg.fill(".modal textarea", "ofensas por mensagem privada"); pg.fill(".modal input", "SUSPENDER")
            pg.locator(".modal button.danger").click(); pg.wait_for_timeout(1500)
            pg.screenshot(path=f"{SHOTS}/{name}_03_suspenso.png", full_page=True)
        pg.close()
    b.close()
print("SHOTS OK")
