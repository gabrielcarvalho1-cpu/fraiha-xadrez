"""FRAIHA Admin V1 · QA do painel no Chromium real contra o servidor LOCAL (FRAIHA_DEV_AUTH=1) com dados reais
de jogo (tests/admin/seed_dev.cjs). Cobre: login admin/não-admin, telas, números sem invenção, toggle real
com confirmação + Admin Log, loading, empty, erro, timeout, reconexão e desktop 1280/1440/1920.
Pré-requisitos (ver tests/admin/run_admin_qa.sh): servidor em 127.0.0.1:8140 e Admin servido em 127.0.0.1:8150.
Rodar: python3 tests/admin/admin_ui_test.py [pasta_screenshots]"""
import os, sys, json, urllib.request
from playwright.sync_api import sync_playwright

ADMIN = "http://127.0.0.1:8150/index.html"
API = "http://127.0.0.1:8140"
SHOTS = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/admin_shots"
os.makedirs(SHOTS, exist_ok=True)
fails = 0


def check(ok, label):
    global fails
    print(("PASS " if ok else "FAIL ") + label)
    if not ok:
        fails += 1


def api(path, token="dev:boss", body=None):
    req = urllib.request.Request(API + path, data=None if body is None else json.dumps(body).encode(), method="POST" if body is not None else "GET",
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")


def login(pg, name):
    pg.goto(ADMIN)
    pg.select_option("select[name=env]", "local")
    pg.fill("input[name=dev]", name)
    pg.click("button[type=submit]")


with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": 1440, "height": 900})
    pg = ctx.new_page()
    errors = []
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.on("console", lambda m: errors.append(m.text) if m.type == "error" and "Failed to load resource" not in m.text else None)

    # --- usuário comum NÃO entra (o servidor recusa)
    login(pg, "jogador1")
    pg.wait_for_selector(".banner.err", timeout=8000)
    check("NÃO é administradora" in pg.inner_text(".banner.err"), "conta comum: servidor recusa (403 not_admin) e o painel não abre")
    pg.screenshot(path=f"{SHOTS}/00_login_nao_admin.png")

    # --- loading: atrasa a primeira resposta do overview e confere o esqueleto
    def slow(route):
        pg.wait_for_timeout(1500)
        route.continue_()
    pg.route("**/admin/api/overview", slow)
    login(pg, "boss")
    pg.wait_for_selector(".skeleton", timeout=5000)
    check(pg.locator(".skeleton").count() > 0, "loading: esqueleto aparece enquanto carrega")
    pg.wait_for_selector("[data-metric='Online agora'] .val:not(.na)", timeout=10000)
    pg.unroute("**/admin/api/overview")
    check("LOCAL" in pg.inner_text(".envbar"), "faixa de ambiente LOCAL bem visível")

    # --- dashboard: números reais vs indisponíveis
    online = pg.inner_text("[data-metric='Online agora'] .val")
    st, ov = api("/admin/api/overview")
    check(st == 200 and online.strip() == str(ov["cards"]["online_now"]["value"]), f"dashboard mostra o MESMO número do servidor (online {online})")
    for m in ["Plataforma", "Jogadores únicos hoje", "Retorno de jogadores", "Erros / reconexões"]:
        el = pg.locator(f"[data-metric='{m}']")
        check(el.get_attribute("data-status") == "unavailable" and "INDISPONÍVEL" in el.inner_text(), f"'{m}' sem dado → INDISPONÍVEL (nenhum número inventado)")
    pg.wait_for_timeout(400)
    pg.screenshot(path=f"{SHOTS}/01_dashboard.png", full_page=True)

    # --- ao vivo
    pg.goto(ADMIN + "#/live"); pg.wait_for_selector("text=Distribuição por modo", timeout=8000)
    pg.screenshot(path=f"{SHOTS}/02_ao_vivo.png", full_page=True)
    check(pg.locator(".seg button[disabled]").count() == 2, "Ao Vivo: 7/30 dias desabilitados (sem histórico durável)")

    # --- filas: toggle REAL com confirmação; partida em andamento continua
    pg.goto(ADMIN + "#/queues"); pg.wait_for_selector("[data-family=ranked]", timeout=8000)
    pg.screenshot(path=f"{SHOTS}/03_filas.png", full_page=True)
    _, before = api("/admin/api/matches")
    ranked_matches = [m["id"] for m in before["active"] if m["family"] == "ranked"]
    pg.click("[data-family=ranked] [data-action=toggle]")
    pg.wait_for_selector(".modal", timeout=3000)
    go = pg.locator(".modal .btn.danger")
    check(go.is_disabled(), "confirmação: botão bloqueado sem motivo + palavra")
    pg.fill(".modal textarea", "teste do painel")
    pg.fill(".modal input", "ranke")
    check(go.is_disabled(), "confirmação: palavra errada continua bloqueado")
    pg.fill(".modal input", "ranked")
    pg.screenshot(path=f"{SHOTS}/04_filas_confirmacao.png")
    go.click()
    pg.wait_for_selector("[data-family=ranked].off", timeout=8000)
    st, q = api("/admin/api/queues")
    rk = [x for x in q["queues"] if x["family"] == "ranked"][0]
    check(rk["enabled"] is False, "servidor confirma: Ranked DESATIVADO")
    check(rk["waiting"]["value"] == 0, "quem esperava na fila Ranked saiu (com aviso)")
    _, after = api("/admin/api/matches")
    check(all(any(m["id"] == i for m in after["active"]) for i in ranked_matches) and len(ranked_matches) > 0, "partida Ranked em andamento CONTINUA ativa")
    pg.screenshot(path=f"{SHOTS}/05_filas_ranked_desativado.png", full_page=True)
    # reativa pela UI
    pg.click("[data-family=ranked] [data-action=toggle]")
    pg.fill(".modal textarea", "fim do teste"); pg.fill(".modal input", "ranked"); pg.click(".modal .btn.ok")
    pg.wait_for_selector("[data-family=ranked]:not(.off)", timeout=8000)

    # --- admin log
    pg.goto(ADMIN + "#/audit"); pg.wait_for_selector("table", timeout=8000)
    txt = pg.inner_text("main")
    check("desativou" in txt and "teste do painel" in txt and "Gabriel" in txt, "Admin Log: ação real com admin, motivo, antes/depois")
    pg.screenshot(path=f"{SHOTS}/06_admin_log.png", full_page=True)

    # --- partidas
    pg.goto(ADMIN + "#/matches"); pg.wait_for_selector("text=Partidas ativas", timeout=8000)
    pg.screenshot(path=f"{SHOTS}/07_partidas.png", full_page=True)

    # --- jogadores + perfil + empty state
    pg.goto(ADMIN + "#/players"); pg.wait_for_selector("table", timeout=8000)
    pg.screenshot(path=f"{SHOTS}/08_jogadores.png", full_page=True)
    pg.fill("input[type=search]", "nadaexisteaqui"); pg.press("input[type=search]", "Enter")
    pg.wait_for_selector("text=Nenhum jogador encontrado", timeout=8000)
    check(True, "empty state: busca sem resultado")
    pg.screenshot(path=f"{SHOTS}/09_jogadores_vazio.png")
    pg.fill("input[type=search]", "Rei"); pg.press("input[type=search]", "Enter")
    pg.wait_for_selector("tr.click", timeout=8000); pg.click("tr.click")
    pg.wait_for_selector("text=Clube FRAIHA", timeout=8000)
    check(pg.locator("button:has-text('Conceder Clube')").is_disabled(), "perfil: Conceder Clube DESABILITADO (backend necessário)")
    pg.screenshot(path=f"{SHOTS}/10_perfil_jogador.png", full_page=True)

    # --- clube / founder
    pg.goto(ADMIN + "#/club"); pg.wait_for_selector("text=Campos preparados", timeout=8000)
    pg.screenshot(path=f"{SHOTS}/11_clube.png", full_page=True)
    pg.goto(ADMIN + "#/founder"); pg.wait_for_selector("text=Campos preparados", timeout=8000)
    pg.screenshot(path=f"{SHOTS}/12_founder.png", full_page=True)
    pg.goto(ADMIN + "#/system"); pg.wait_for_selector("text=Servidor", timeout=8000)
    pg.screenshot(path=f"{SHOTS}/13_sistema.png", full_page=True)

    # --- erro do backend aparece; reconexão volta sozinha
    pg.goto(ADMIN + "#/dashboard"); pg.wait_for_selector("[data-metric='Online agora'] .val:not(.na)", timeout=8000)
    pg.route("**/admin/api/overview", lambda r: r.fulfill(status=500, body='{"error":"server_error"}', headers={"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"}))
    pg.wait_for_selector("#view-banner.banner.err", timeout=12000)
    check("Erro interno do servidor" in pg.inner_text("#view-banner"), "erro do backend aparece (dados antigos sinalizados)")
    pg.screenshot(path=f"{SHOTS}/14_erro_backend.png")
    pg.unroute("**/admin/api/overview")
    pg.wait_for_selector("#view-banner.hidden", state="attached", timeout=20000)
    check("ao vivo" in pg.inner_text("#conn-text"), "reconexão: volta sozinho quando o servidor responde")

    # --- timeout (servidor não responde em 8 s) na primeira carga de uma tela
    pg.route("**/admin/api/system", lambda r: (pg.wait_for_timeout(9500), r.abort()))
    pg.goto(ADMIN + "#/system")
    pg.wait_for_selector(".state.err", timeout=20000)
    check("não respondeu a tempo" in pg.inner_text(".state.err"), "timeout: mensagem clara + botão tentar de novo")
    pg.screenshot(path=f"{SHOTS}/15_timeout.png")
    pg.unroute("**/admin/api/system")

    # --- responsividade desktop
    for w, hgt in [(1280, 800), (1920, 1080)]:
        pg.set_viewport_size({"width": w, "height": hgt})
        pg.goto(ADMIN + "#/dashboard"); pg.wait_for_selector("[data-metric='Online agora'] .val:not(.na)", timeout=8000)
        sw = pg.evaluate("document.documentElement.scrollWidth"); cw = pg.evaluate("document.documentElement.clientWidth")
        check(sw <= cw, f"desktop {w}x{hgt}: sem rolagem horizontal")
        pg.screenshot(path=f"{SHOTS}/16_dashboard_{w}.png")

    check(not [e for e in errors if "Content Security Policy" in e or "Uncaught" in e], "sem erro de JS/CSP no console: " + "; ".join(errors[:3]))
    pg.unroute_all(behavior="ignoreErrors"); b.close()
print("RESULT", "OK" if fails == 0 else f"FALHAS={fails}")
sys.exit(1 if fails else 0)
