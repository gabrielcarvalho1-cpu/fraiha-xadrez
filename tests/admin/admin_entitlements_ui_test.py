"""FRAIHA Admin V1 · CLUBE + FUNDADOR no Chromium, com o Admin servido pelo PRÓPRIO servidor (/admin/) e
jogadores REAIS conectados (servidor LOCAL FRAIHA_DEV_AUTH=1 + tests/admin/seed_dev.cjs).
Cobre: lista ONLINE AGORA, conceder/alterar/revogar Clube (30 dias, sem expiração, data personalizada),
conceder/revogar Fundador, confirmação com motivo obrigatório, cancelar = nada muda, tela desatualizada,
atualização imediata (linha, telas Clube/Fundador, perfil), Admin Log, desktop + 393 px.
Rodar: tests/admin/run_admin_entitlements_qa.sh [pasta_screenshots]"""
import os, sys, json, time, urllib.request
from datetime import datetime, timedelta
from playwright.sync_api import sync_playwright

API = "http://127.0.0.1:8140"
ADMIN = API + "/admin/"
SHOTS = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/admin_ent_shots"
os.makedirs(SHOTS, exist_ok=True)
fails = 0
NICK = "GambitoRei"


def check(ok, label):
    global fails
    print(("PASS " if ok else "FAIL ") + label)
    if not ok:
        fails += 1


def api(path, body=None, token="dev:boss"):
    req = urllib.request.Request(API + path, data=None if body is None else json.dumps(body).encode(), method="POST" if body is not None else "GET",
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")


with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={"width": 1440, "height": 900})
    errors = []
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.on("console", lambda m: errors.append(m.text) if m.type == "error" and "Failed to load resource" not in m.text else None)

    _, on = api("/admin/api/online")
    target = [i for i in on["items"] if i["nickname"] == NICK]
    check(len(target) == 1 and on["items"][0]["ent"] is not None, f"API: {NICK} está ONLINE com estado de Clube/Fundador ({len(on['items'])} contas online)")
    uid = target[0]["user_id"]
    _, a0 = api("/admin/api/audit?limit=500"); n0 = len(a0["items"])

    pg.goto(ADMIN); pg.select_option("select[name=env]", "local"); pg.fill("input[name=dev]", "boss"); pg.click("button[type=submit]")
    pg.wait_for_selector(".shell", timeout=10000)
    pg.goto(ADMIN + "#/club"); pg.wait_for_selector("#online-panel .onrow", timeout=10000)
    row = lambda: pg.locator(f".onrow[data-uid='{uid}']")
    check(pg.locator("#online-panel .onrow").count() == len(on["items"]) and row().count() == 1, "Clube: JOGADORES ONLINE AGORA lista as contas online reais")
    check("ONLINE" in row().inner_text() or "EM " in row().inner_text(), "linha mostra status online")
    check(row().locator("[data-club='INATIVO']").count() == 1 and row().locator("[data-founder='false']").count() == 1, "estado inicial: Clube INATIVO, Fundador NÃO")
    pg.screenshot(path=f"{SHOTS}/e01_clube_online.png", full_page=True)

    # --- CONCEDER Clube 30 dias: confirmação com resumo + motivo obrigatório
    row().locator("[data-act='club.grant']").click()
    pg.wait_for_selector(".modal[data-ent='club.grant']", timeout=3000)
    m = pg.locator(".modal")
    exp30 = (datetime.now() + timedelta(days=30)).strftime("%d/%m/%Y")
    check(NICK in m.inner_text() and pg.inner_text("#ent-expires") == exp30, f"modal: 'Conceder Clube para {NICK}', validade 30 dias, expira {exp30}")
    go = m.locator(".btn.ok")
    check(go.inner_text() == "CONFIRMAR CONCESSÃO" and go.is_disabled(), "CONFIRMAR CONCESSÃO bloqueado sem motivo")
    pg.screenshot(path=f"{SHOTS}/e02_modal_conceder.png")
    # cancelar = nada muda
    m.locator(".btn.ghost").click()
    _, st = api(f"/admin/api/players/{uid}")
    check(pg.locator(".modal").count() == 0 and st["ent"]["club"]["status"] == "INATIVO", "cancelar: nada muda")
    row().locator("[data-act='club.grant']").click(); pg.wait_for_selector(".modal", timeout=3000)
    pg.fill(".modal textarea", "teste do painel"); pg.locator(".modal .btn.ok").click()
    pg.wait_for_selector(f".onrow[data-uid='{uid}'] [data-club='ATIVO']", timeout=8000)
    _, st = api(f"/admin/api/players/{uid}")
    check(st["ent"]["club"]["status"] == "ATIVO" and st["ent"]["club"]["source"] == "manual", "servidor confirma: Clube ATIVO (origem manual)")
    check(f"até {exp30}" in row().inner_text(), f"linha atualizada na hora: 'até {exp30}' + [ALTERAR] [REVOGAR]")
    check(row().locator("[data-act='club.change']").count() == 1 and row().locator("[data-act='club.revoke']").count() == 1, "botões ALTERAR e REVOGAR aparecem")

    # --- ALTERAR: sem expiração
    row().locator("[data-act='club.change']").click(); pg.wait_for_selector(".modal[data-ent='club.change']", timeout=3000)
    pg.select_option(".modal select[name=term]", "none")
    check(pg.inner_text("#ent-expires") == "sem expiração", "modal: 'Sem expiração'")
    pg.fill(".modal textarea", "vitalício de teste"); pg.locator(".modal .btn.ok").click()
    pg.wait_for_function(f"() => (document.querySelector(\".onrow[data-uid='{uid}']\") || {{}}).innerText?.includes('sem expiração')", timeout=8000)
    _, st = api(f"/admin/api/players/{uid}")
    check(st["ent"]["club"]["expires_at"] is None and st["ent"]["club"]["status"] == "ATIVO", "servidor: Clube ATIVO sem expiração")

    # --- ALTERAR: data personalizada
    day = (datetime.now() + timedelta(days=45)).strftime("%Y-%m-%d")
    row().locator("[data-act='club.change']").click(); pg.wait_for_selector(".modal", timeout=3000)
    pg.select_option(".modal select[name=term]", "custom")
    check(pg.locator(".modal .btn.ok").is_disabled() and pg.inner_text("#ent-expires") == "escolha a data", "data personalizada: exige escolher a data")
    pg.fill(".modal input[type=date]", day); pg.fill(".modal textarea", "data combinada")
    dshow = (datetime.now() + timedelta(days=45)).strftime("%d/%m/%Y")
    check(pg.inner_text("#ent-expires") == dshow, f"modal mostra expira {dshow}")
    pg.locator(".modal .btn.ok").click()
    pg.wait_for_function(f"() => (document.querySelector(\".onrow[data-uid='{uid}']\") || {{}}).innerText?.includes('até {dshow}')", timeout=8000)
    check(True, f"linha: 'até {dshow}'")

    # --- tela desatualizada: o estado muda por fora com o modal aberto → servidor recusa, tela atualiza
    row().locator("[data-act='club.change']").click(); pg.wait_for_selector(".modal", timeout=3000)
    _, cur = api(f"/admin/api/players/{uid}")
    s2, r2 = api(f"/admin/api/players/{uid}/club", {"action": "change", "duration": "90", "reason": "mudança paralela", "confirm": uid, "expect_version": cur["ent"]["version"]})
    check(s2 == 200, "mudança paralela feita (outra aba)")
    pg.fill(".modal textarea", "tela velha"); pg.locator(".modal .btn.ok").click()
    pg.wait_for_selector(".toast.err", timeout=5000)
    check("estado mudou" in pg.inner_text(".toast.err"), "tela desatualizada: servidor recusa (409) e avisa")
    _, st = api(f"/admin/api/players/{uid}")
    check(st["ent"]["club"]["expires_at"] == r2["state"]["club"]["expires_at"], "nada sobrescrito pela tela velha")

    # --- REVOGAR Clube
    row().locator("[data-act='club.revoke']").click(); pg.wait_for_selector(".modal[data-ent='club.revoke']", timeout=3000)
    check(pg.locator(".modal .btn.danger").inner_text() == "CONFIRMAR REVOGAÇÃO" and pg.locator(".modal .btn.danger").is_disabled(), "revogar: confirmação + motivo obrigatório")
    pg.fill(".modal textarea", "fim do teste"); pg.locator(".modal .btn.danger").click()
    pg.wait_for_selector(f".onrow[data-uid='{uid}'] [data-club='INATIVO']", timeout=8000)
    check(row().locator("[data-act='club.grant']").count() == 1, "Clube revogado: volta a mostrar [CONCEDER]")

    # --- FUNDADOR
    pg.goto(ADMIN + "#/founder"); pg.wait_for_selector(f".onrow[data-uid='{uid}']", timeout=10000)
    row().locator("[data-act='founder.grant']").click(); pg.wait_for_selector(".modal[data-ent='founder.grant']", timeout=3000)
    check("permanente" in pg.inner_text(".modal") and pg.locator(".modal .btn.ok").inner_text() == "CONFIRMAR FUNDADOR" and pg.locator(".modal select").count() == 0, "Fundador: confirmação sem validade (permanente)")
    pg.fill(".modal textarea", "fundador de teste"); pg.screenshot(path=f"{SHOTS}/e03_modal_fundador.png"); pg.locator(".modal .btn.ok").click()
    pg.wait_for_selector(f".onrow[data-uid='{uid}'] [data-founder='true']", timeout=8000)
    _, st = api(f"/admin/api/players/{uid}")
    check(st["ent"]["founder"]["value"] is True and st["ent"]["club"]["status"] == "INATIVO", "servidor: Fundador SIM; Clube continua INATIVO (independentes)")
    check(row().locator("[data-act='founder.revoke']").count() == 1, "Fundador SIM: botão [REVOGAR]")
    pg.screenshot(path=f"{SHOTS}/e04_fundador.png", full_page=True)
    # perfil mostra o mesmo estado (atualização em todas as telas)
    pg.goto(ADMIN + "#/players/" + uid); pg.wait_for_selector("#founder-value", timeout=8000)
    check("SIM" in pg.inner_text("#founder-value") and pg.locator("[data-act='founder.revoke']").count() == 1, "perfil do jogador mostra Fundador SIM + [REVOGAR]")
    pg.locator("[data-act='founder.revoke']").click(); pg.wait_for_selector(".modal", timeout=3000)
    pg.fill(".modal textarea", "fim do teste fundador"); pg.locator(".modal .btn.danger").click()
    pg.wait_for_selector("[data-founder='false']", timeout=8000)
    _, st = api(f"/admin/api/players/{uid}")
    check(st["ent"]["founder"]["value"] is False, "Fundador revogado pelo perfil")

    # --- Admin Log
    pg.goto(ADMIN + "#/audit"); pg.wait_for_selector("table", timeout=8000)
    txt = pg.inner_text("table")
    _, a1 = api("/admin/api/audit?limit=500")
    new = [e for e in a1["items"][: len(a1["items"]) - n0]]
    acts = [e["action"] for e in reversed(new)]
    check(acts == ["clube_grant", "clube_change", "clube_change", "clube_change", "clube_revoke", "founder_grant", "founder_revoke"], f"Admin Log: eventos na ordem {acts}")
    check(all(e["actor"]["role"] == "owner" and e["target"]["user_id"] == uid and e["reason"] and e["before"] and e["after"] for e in new), "cada evento: admin, alvo, UUID, antes/depois, motivo")
    check("concedeu Clube" in txt and "revogou Fundador" in txt and NICK in txt and "teste do painel" in txt, "tela Admin Log mostra ação, alvo e motivo")
    pg.screenshot(path=f"{SHOTS}/e05_admin_log.png", full_page=True)

    # --- 393 px
    pg.set_viewport_size({"width": 393, "height": 852})
    for r in ["club", "founder"]:
        pg.goto(ADMIN + "#/dashboard"); pg.wait_for_timeout(200); pg.goto(ADMIN + "#/" + r); pg.wait_for_selector("#online-panel .onrow", timeout=10000)
        sw = pg.evaluate("document.documentElement.scrollWidth")
        bb = row().locator("[data-act]").first.bounding_box()
        check(sw <= 393 and bb and bb["x"] >= 0 and bb["x"] + bb["width"] <= 393.5, f"393 px: {r} sem rolagem lateral e botões visíveis (scrollWidth {sw})")
        pg.screenshot(path=f"{SHOTS}/e06_{r}_393.png", full_page=True)
    row().locator("[data-act]").first.click(); pg.wait_for_selector(".modal", timeout=3000)
    mb = pg.locator(".modal").bounding_box()
    check(mb["x"] >= 0 and mb["x"] + mb["width"] <= 393.5, "393 px: modal de confirmação cabe na tela")
    pg.screenshot(path=f"{SHOTS}/e07_modal_393.png")
    pg.locator(".modal .btn.ghost").click()

    check(not [e for e in errors if "Content Security Policy" in e or "Uncaught" in e], "sem erro de JS/CSP no console: " + "; ".join(errors[:3]))
    b.close()

print("RESULT", "OK" if fails == 0 else f"{fails} FAIL")
sys.exit(1 if fails else 0)
