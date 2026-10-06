"""FRAIHA Admin V1 · QA do painel no Chromium real contra o servidor LOCAL (FRAIHA_DEV_AUTH=1) com dados reais
de jogo (tests/admin/seed_dev.cjs). Cobre: login admin/não-admin, telas, números sem invenção, toggle real
com confirmação + Admin Log, loading, empty, erro, timeout, reconexão e desktop 1280/1440/1920.
Pré-requisitos (ver tests/admin/run_admin_qa.sh): servidor em 127.0.0.1:8140 e Admin servido em 127.0.0.1:8150.
Rodar: python3 tests/admin/admin_ui_test.py [pasta_screenshots]"""
import os, sys, json, time, urllib.request
from playwright.sync_api import sync_playwright

# ADMIN_URL permite rodar o MESMO QA com o Admin servido pelo próprio servidor (http://127.0.0.1:8140/admin/).
ADMIN = os.environ.get("ADMIN_URL", "http://127.0.0.1:8150/index.html")
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
    check(pg.locator("[data-act='club.grant']").count() == 1 and pg.locator("[data-act='club.grant']").is_enabled(), "perfil: CONCEDER Clube disponível para owner (backend real)")
    pg.screenshot(path=f"{SHOTS}/10_perfil_jogador.png", full_page=True)

    # --- clube / founder
    pg.goto(ADMIN + "#/club"); pg.wait_for_selector("#online-panel", timeout=8000)
    pg.screenshot(path=f"{SHOTS}/11_clube.png", full_page=True)
    pg.goto(ADMIN + "#/founder"); pg.wait_for_selector("#online-panel", timeout=8000)
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
    def stall_system(r):
        pg.wait_for_timeout(9500)
        try: r.abort()
        except Exception: pass
    pg.route("**/admin/api/system", stall_system)
    pg.goto(ADMIN + "#/system")
    pg.wait_for_selector(".state.err", timeout=20000)
    check("não respondeu a tempo" in pg.inner_text(".state.err"), "timeout: mensagem clara + botão tentar de novo")
    pg.screenshot(path=f"{SHOTS}/15_timeout.png")
    pg.unroute_all(behavior="ignoreErrors")

    # ===================== auditoria Orca (retorno) =====================
    reqs = []
    pg.on("request", lambda r: reqs.append((time.time(), r.url, r.method)) if "/admin/api/" in r.url else None)
    pg.unroute_all(behavior="ignoreErrors")

    # --- LOGIN → abrir confirmação crítica → LOGOUT → tentar confirmar a antiga → NENHUMA mutação
    pg.goto(ADMIN + "#/queues"); pg.wait_for_selector("[data-family=ranked] [data-action=toggle]", timeout=8000)
    _, a0 = api("/admin/api/audit"); n0 = len(a0["items"])
    pg.click("[data-family=ranked] [data-action=toggle]"); pg.wait_for_selector(".modal", timeout=3000)
    pg.fill(".modal textarea", "tentativa depois do logout"); pg.fill(".modal input", "ranked")
    pg.evaluate("window.__staleGo = document.querySelector('.modal .btn.danger')")
    check(not pg.evaluate("window.__staleGo.disabled"), "confirmação pronta para enviar (antes do logout)")
    # o botão Sair fica atrás do modal: o logout pode vir de qualquer lugar (aqui: chamada direta, como um atalho)
    pg.evaluate("document.querySelector('header .btn.ghost').click()")
    pg.wait_for_selector("select[name=env]", timeout=5000)
    mark = time.time()
    check(pg.locator(".modal").count() == 0, "logout fecha a confirmação pendente")
    pg.evaluate("window.__staleGo && window.__staleGo.click()")
    pg.wait_for_timeout(1500)
    _, q = api("/admin/api/queues"); _, a1 = api("/admin/api/audit")
    check([x for x in q["queues"] if x["family"] == "ranked"][0]["enabled"] is True and len(a1["items"]) == n0, "confirmação antiga após logout: NENHUMA mutação no servidor e nada no Admin Log")
    pg.wait_for_timeout(6500)
    late = [r for r in reqs if r[0] > mark + 0.2]
    check(not late, f"depois do logout: nenhuma requisição administrativa (polling parado) {late[:2]}")
    check(pg.locator(".shell").count() == 0 and pg.locator("select[name=env]").count() == 1, "depois do logout: tela de login, nada da sessão administrativa")

    # --- perda de autenticação (401 no polling) com confirmação aberta → sessão encerrada, nada muda
    login(pg, "boss"); pg.wait_for_selector("[data-metric='Online agora'] .val:not(.na)", timeout=10000)
    pg.goto(ADMIN + "#/queues"); pg.wait_for_selector("[data-family=casual] [data-action=toggle]", timeout=8000)
    pg.click("[data-family=casual] [data-action=toggle]"); pg.wait_for_selector(".modal", timeout=3000)
    pg.fill(".modal textarea", "depois do 401"); pg.fill(".modal input", "casual")
    pg.evaluate("window.__staleGo2 = document.querySelector('.modal .btn.danger')")
    pg.route("**/admin/api/queues", lambda r: r.fulfill(status=401, body='{"error":"invalid_session"}', headers={"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"}))
    pg.wait_for_selector("select[name=env]", timeout=10000)
    pg.unroute_all(behavior="ignoreErrors")
    check(pg.locator(".modal").count() == 0, "401 durante o polling: sessão encerrada e confirmação fechada")
    pg.evaluate("window.__staleGo2 && window.__staleGo2.click()"); pg.wait_for_timeout(1200)
    _, q = api("/admin/api/queues")
    check([x for x in q["queues"] if x["family"] == "casual"][0]["enabled"] is True, "confirmação antiga após 401: nenhuma mutação")

    # --- request em voo → LOGOUT → resposta tardia → sessão NÃO reaparece, nenhuma ação nova
    login(pg, "boss"); pg.wait_for_selector("[data-metric='Online agora'] .val:not(.na)", timeout=10000)
    def slow_overview(route):
        pg.wait_for_timeout(2500)
        try: route.continue_()
        except Exception: pass
    pg.route("**/admin/api/overview", slow_overview)
    pg.goto(ADMIN + "#/live"); pg.wait_for_timeout(300); pg.goto(ADMIN + "#/dashboard")   # nova carga do overview (lenta)
    pg.wait_for_timeout(400)
    pg.click("header .btn.ghost")
    pg.wait_for_selector("select[name=env]", timeout=5000)
    mark = time.time()
    pg.wait_for_timeout(4500)
    check(pg.locator(".shell").count() == 0 and pg.locator("select[name=env]").count() == 1, "resposta tardia depois do logout NÃO restaura a sessão")
    late = [r for r in reqs if r[0] > mark + 0.2]
    check(not late, f"resposta tardia não dispara nova requisição {late[:2]}")
    pg.unroute_all(behavior="ignoreErrors")

    # ===================== correção final: 401 em AÇÃO administrativa (não só no polling) =====================
    JH = {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"}
    def ranked_enabled():
        _, q = api("/admin/api/queues"); return [x for x in q["queues"] if x["family"] == "ranked"][0]["enabled"]

    # --- 400 / 403 / 500 numa ação NÃO encerram a sessão (só mostram o erro)
    login(pg, "boss"); pg.wait_for_selector("[data-metric='Online agora'] .val:not(.na)", timeout=10000)
    pg.goto(ADMIN + "#/queues"); pg.wait_for_selector("[data-family=ranked] [data-action=toggle]", timeout=8000)
    for st, code, msg in ((400, "reason_required", "Informe o motivo"), (403, "forbidden", "não tem permissão"), (500, "server_error", "Erro interno")):
        def fail_post(st, code):
            return lambda r: r.fulfill(status=st, body=json.dumps({"error": code}), headers=JH) if r.request.method == "POST" else r.continue_()
        pg.route("**/admin/api/queues/ranked", fail_post(st, code))
        pg.click("[data-family=ranked] [data-action=toggle]"); pg.wait_for_selector(".modal", timeout=3000)
        pg.fill(".modal textarea", f"erro {st}"); pg.fill(".modal input", "ranked"); pg.click(".modal .btn.danger")
        pg.wait_for_selector(f".toast:has-text('{msg}')", timeout=5000)
        mark = time.time(); pg.wait_for_timeout(5500)
        polled = [r for r in reqs if r[0] > mark and r[1].endswith("/admin/api/queues")]
        check(pg.locator(".shell").count() == 1 and pg.locator("select[name=env]").count() == 0 and polled and ranked_enabled() is True,
              f"ação com HTTP {st}: erro exibido, sessão CONTINUA (polling segue), nada aplicado")
        pg.unroute_all(behavior="ignoreErrors")

    # --- LOGADO → ação de fila → endpoint responde 401 → sessão encerrada por inteiro
    pg.goto(ADMIN + "#/dashboard"); pg.wait_for_timeout(300)
    pg.goto(ADMIN + "#/queues"); pg.wait_for_selector("[data-family=ranked] [data-action=toggle]", timeout=8000)
    _, a0 = api("/admin/api/audit"); n0 = len(a0["items"])
    held = []
    pg.route("**/admin/api/queues/ranked", lambda r: held.append(r) if r.request.method == "POST" else r.continue_())
    pg.click("[data-family=ranked] [data-action=toggle]"); pg.wait_for_selector(".modal", timeout=3000)
    pg.fill(".modal textarea", "acao com 401"); pg.fill(".modal input", "ranked"); pg.click(".modal .btn.danger")
    pg.wait_for_function("() => !document.querySelector('.modal')", timeout=3000)
    for _ in range(30):
        if held: break
        pg.wait_for_timeout(100)
    check(len(held) == 1, "ação enviada (POST /admin/api/queues/ranked interceptado)")
    # enquanto a ação está em voo, outra confirmação crítica fica aberta e pronta
    pg.click("[data-family=casual] [data-action=toggle]"); pg.wait_for_selector(".modal", timeout=3000)
    pg.fill(".modal textarea", "pendente no 401"); pg.fill(".modal input", "casual")
    pg.evaluate("window.__staleGo3 = document.querySelector('.modal .btn.danger')")
    check(not pg.evaluate("window.__staleGo3.disabled"), "confirmação pendente pronta (antes do 401)")
    held[0].fulfill(status=401, body='{"error":"invalid_session"}', headers=JH)   # o servidor recusa a ação
    pg.wait_for_selector("select[name=env]", timeout=5000)
    mark = time.time()
    pg.unroute_all(behavior="ignoreErrors")
    check(pg.locator(".shell").count() == 0 and pg.locator("[data-action=toggle]").count() == 0 and pg.locator("header .btn.ghost").count() == 0,
          "401 na ação: tela privilegiada removida (sem shell, sem botões de fila, sem Sair)")
    check("Sessão inválida" in pg.inner_text(".banner.err"), "401 na ação: volta ao login com o motivo")
    check(pg.locator(".modal").count() == 0, "401 na ação: confirmação pendente fechada")
    pg.screenshot(path=f"{SHOTS}/18_acao_401_login.png")
    pg.evaluate("window.__staleGo3 && window.__staleGo3.click()"); pg.wait_for_timeout(1200)
    _, q = api("/admin/api/queues"); _, a1 = api("/admin/api/audit")
    check(ranked_enabled() is True and [x for x in q["queues"] if x["family"] == "casual"][0]["enabled"] is True and len(a1["items"]) == n0,
          "401 na ação: ação NÃO aplicada; confirmação antiga não envia nada; Admin Log inalterado")
    pg.wait_for_timeout(6500)
    late = [r for r in reqs if r[0] > mark + 0.2]
    check(not late, f"401 na ação: polling parado, nenhuma requisição administrativa depois {late[:2]}")
    check(pg.evaluate("location.hash === '' || !document.querySelector('.shell')") and pg.locator(".shell").count() == 0, "401 na ação: sessão não volta sozinha")

    # --- 401 em outra chamada (leitura de uma tela qualquer, não a fila) também encerra
    login(pg, "boss"); pg.wait_for_selector("[data-metric='Online agora'] .val:not(.na)", timeout=10000)
    pg.route("**/admin/api/audit*", lambda r: r.fulfill(status=401, body="", headers=JH))   # 401 com corpo vazio
    pg.goto(ADMIN + "#/audit")
    pg.wait_for_selector("select[name=env]", timeout=8000)
    pg.unroute_all(behavior="ignoreErrors")
    check(pg.locator(".shell").count() == 0, "401 (corpo vazio) na tela Admin Log: sessão encerrada")
    # novo login normal depois do 401 funciona (chamadas 200 normais)
    login(pg, "boss"); pg.wait_for_selector("[data-metric='Online agora'] .val:not(.na)", timeout=10000)
    check(pg.locator(".shell").count() == 1, "depois do 401: novo login normal funciona")

    # --- Clube/Founder: ERRO de consulta aparece como INDISPONÍVEL (não como "não possui")
    login(pg, "boss"); pg.wait_for_selector("[data-metric='Online agora'] .val:not(.na)", timeout=10000)
    _, pls = api("/admin/api/players?q=Rei"); uid = pls["items"][0]["user_id"]
    def ent_error(route):
        resp = route.fetch(); d = resp.json()
        d["entitlements_read"] = "query_error"
        d["club"]["status"] = "INDISPONÍVEL"; d["club"]["read_error"] = "ERRO DE CONSULTA"
        d["founder"].update({"value": None, "status": "unavailable", "note": "ERRO DE CONSULTA"})
        d["ent"] = None   # o servidor real devolve ent=null quando a leitura falha
        route.fulfill(response=resp, json=d)
    pg.route("**/admin/api/players/" + uid, ent_error)
    pg.goto(ADMIN + "#/players/" + uid); pg.wait_for_selector("#club-status", timeout=8000)
    check(pg.inner_text("#club-status") == "INDISPONÍVEL" and "INDISPONÍVEL" in pg.inner_text("#founder-value") and pg.locator("#ent-error").count() == 1,
          "perfil: erro de consulta = INDISPONÍVEL + aviso (não INATIVO/NÃO)")
    pg.screenshot(path=f"{SHOTS}/17_perfil_erro_consulta.png", full_page=True)
    pg.unroute_all(behavior="ignoreErrors")
    pg.goto(ADMIN + "#/players"); pg.wait_for_timeout(500)   # sai e volta: nova leitura real
    pg.goto(ADMIN + "#/players/" + uid); pg.wait_for_selector("#club-status", timeout=8000); pg.wait_for_timeout(300)
    check(pg.inner_text("#club-status") in ("INATIVO", "ATIVO", "EXPIRADO") and pg.locator("#ent-error").count() == 0, "perfil: leitura normal mostra o status real")

    # --- responsividade: celular 393, paisagem 852x393, desktop 1280 e 1920 em TODAS as telas
    for w, hgt in [(393, 852), (852, 393), (1280, 800), (1920, 1080)]:
        pg.set_viewport_size({"width": w, "height": hgt})
        bad = []
        for rt in ["dashboard", "live", "queues", "matches", "players", "players/" + uid, "club", "founder", "audit", "system"]:
            pg.goto(ADMIN + "#/" + rt); pg.wait_for_timeout(900)
            sw = pg.evaluate("document.documentElement.scrollWidth"); cw = pg.evaluate("document.documentElement.clientWidth")
            if sw > cw: bad.append(f"{rt}:{sw}>{cw}")
        check(not bad, f"{w}x{hgt}: sem rolagem horizontal estrutural em nenhuma tela {bad}")
        pg.goto(ADMIN + "#/queues"); pg.wait_for_selector("[data-family=ranked] [data-action=toggle]", timeout=8000)
        btn = pg.locator("[data-family=ranked] [data-action=toggle]").bounding_box()
        check(btn and btn["x"] >= 0 and btn["x"] + btn["width"] <= w + 0.5, f"{w}x{hgt}: botão crítico da fila visível e dentro da tela")
        pg.screenshot(path=f"{SHOTS}/18_filas_{w}x{hgt}.png", full_page=True)

    check(not [e for e in errors if "Content Security Policy" in e or "Uncaught" in e], "sem erro de JS/CSP no console: " + "; ".join(errors[:3]))
    pg.unroute_all(behavior="ignoreErrors"); b.close()
print("RESULT", "OK" if fails == 0 else f"FALHAS={fails}")
sys.exit(1 if fails else 0)
