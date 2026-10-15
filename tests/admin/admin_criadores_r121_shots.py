"""R121 · prints da tela CRIADORES do Admin (servidor DEV local na 8140). Uso: python3 tests/admin/admin_criadores_r121_shots.py <pasta>"""
import os, sys
from playwright.sync_api import sync_playwright
ADMIN = "http://127.0.0.1:8140/admin/"
SHOTS = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/r121_admin"
os.makedirs(SHOTS, exist_ok=True)
with sync_playwright() as p:
    b = p.chromium.launch()
    for name, vp in [("pc", {"width": 1440, "height": 900}), ("cel", {"width": 393, "height": 852})]:
        pg = b.new_page(viewport=vp)
        pg.goto(ADMIN); pg.select_option("select[name=env]", "local"); pg.fill("input[name=dev]", "boss"); pg.click("button[type=submit]")
        pg.wait_for_selector(".shell", timeout=10000)
        pg.goto(ADMIN + "#/creators"); pg.wait_for_timeout(1500)
        if name == "pc":
            pg.locator("button", has_text="Novo criador").click(); pg.wait_for_timeout(300)
            fields = pg.locator(".modal input[type=text]")
            fields.nth(0).fill("XADREZDOJOAO"); fields.nth(1).fill("João Xadrez"); fields.nth(2).fill("@joaoxadrez · PIX joao@email.com")
            pg.fill(".modal textarea", "parceria fechada")
            pg.screenshot(path=f"{SHOTS}/{name}_01_novo_criador.png")
            pg.locator(".modal button.ok").click(); pg.wait_for_timeout(1500)
        pg.screenshot(path=f"{SHOTS}/{name}_02_criadores.png", full_page=True)
        pg.close()
    b.close()
print("SHOTS OK")
