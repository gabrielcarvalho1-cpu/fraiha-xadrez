"""FRAIHA Admin V1 · ENTRAR COM GOOGLE — QA no Chromium com o Admin servido pelo PRÓPRIO servidor (/admin/).

MOCK (explícito): o Google e o Supabase Auth NÃO são chamados de verdade. O Playwright intercepta
  - https://<projeto>.supabase.co/auth/v1/authorize  → responde 302 de volta ao Admin com #access_token
    (ou #error=access_denied), como o Supabase faz no fluxo implícito;
  - https://<projeto>.supabase.co/auth/v1/token e /logout → respostas falsas registradas;
  - https://fraiha-xadrez-staging.onrender.com/*      → reencaminhado ao servidor LOCAL (127.0.0.1:8140).
O servidor local roda com FRAIHA_DEV_AUTH=1: o "access token" do Google falso é um token DEV
(dev:boss = owner na allowlist; dev:jogador1 = conta comum). A verificação do token, a allowlist e o 403
são os do servidor REAL (mesmo código). O que NÃO é testado aqui: Google real, consentimento real,
Redirect URL real no Supabase.
Rodar: tests/admin/run_admin_google_qa.sh [pasta_screenshots]"""
import os, sys, json, time, urllib.request
from urllib.parse import urlparse, parse_qs
from playwright.sync_api import sync_playwright

LOCAL = "http://127.0.0.1:8140"
ADMIN = LOCAL + "/admin/"
SUPA = "https://xbdkrrbppbhpufplnsbw.supabase.co"
STAGING = "https://fraiha-xadrez-staging.onrender.com"
SHOTS = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/admin_google_shots"
os.makedirs(SHOTS, exist_ok=True)
fails = 0


def check(ok, label):
    global fails
    print(("PASS " if ok else "FAIL ") + label)
    if not ok:
        fails += 1


def raw(path):
    with urllib.request.urlopen(LOCAL + path, timeout=10) as r:
        return r.read().decode("utf8")


with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": 1440, "height": 900})
    pg = ctx.new_page()
    errors = []
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.on("console", lambda m: errors.append(m.text) if m.type == "error" and "Failed to load resource" not in m.text else None)

    mock = {"mode": "owner"}
    authorize_calls, logout_calls, token_calls, staging_calls = [], [], [], []
    CORS = {"Access-Control-Allow-Origin": LOCAL, "Access-Control-Allow-Headers": "*", "Access-Control-Allow-Methods": "GET,POST,OPTIONS"}

    def on_authorize(route):
        u = urlparse(route.request.url); q = parse_qs(u.query)
        authorize_calls.append(q)
        back = q.get("redirect_to", [""])[0]
        frag = {"owner": "access_token=dev:boss&refresh_token=rt_fake&provider_token=goog_fake&expires_in=3600&token_type=bearer",
                "normal": "access_token=dev:jogador1&refresh_token=rt_fake2&expires_in=3600&token_type=bearer",
                "cancel": "error=access_denied&error_code=403&error_description=The+user+denied+access"}[mock["mode"]]
        route.fulfill(status=302, headers={"Location": back + "#" + frag})

    def on_logout(route):
        if route.request.method == "OPTIONS":
            return route.fulfill(status=204, headers=CORS)
        logout_calls.append(route.request.headers.get("authorization", ""))
        route.fulfill(status=204, headers=CORS)

    def on_token(route):
        if route.request.method == "OPTIONS":
            return route.fulfill(status=204, headers=CORS)
        body = json.loads(route.request.post_data or "{}")
        token_calls.append(body.get("email"))
        if body.get("email") == "dono@exemplo.test" and body.get("password") == "senha-certa-123":
            return route.fulfill(status=200, headers={**CORS, "Content-Type": "application/json"}, body=json.dumps({"access_token": "dev:boss", "refresh_token": "rt", "expires_in": 3600}))
        route.fulfill(status=400, headers={**CORS, "Content-Type": "application/json"}, body='{"error":"invalid_grant"}')

    def on_staging(route):   # STAGING → servidor local (mesmo código do servidor real)
        req = route.request
        staging_calls.append((time.time(), req.method, req.url))
        if req.method == "OPTIONS":
            return route.fulfill(status=204, headers={**CORS, "Access-Control-Allow-Headers": "Authorization, Content-Type"})
        if mock.get("api401") and "/admin/api/overview" in req.url:
            return route.fulfill(status=401, headers={**CORS, "Content-Type": "application/json"}, body='{"error":"invalid_session"}')
        resp = route.fetch(url=req.url.replace(STAGING, LOCAL), headers={**req.headers, "origin": LOCAL})
        route.fulfill(response=resp, headers={**resp.headers, **CORS})

    pg.route(SUPA + "/auth/v1/authorize*", on_authorize)
    pg.route(SUPA + "/auth/v1/logout*", on_logout)
    pg.route(SUPA + "/auth/v1/token*", on_token)
    pg.route(STAGING + "/**", on_staging)

    def open_login(env="staging"):
        pg.goto(ADMIN); pg.wait_for_selector("select[name=env]", timeout=8000)
        pg.select_option("select[name=env]", env)

    def storage_dump():
        return pg.evaluate("JSON.stringify([Object.entries(sessionStorage), Object.entries(localStorage)])")

    # --- botão aparece (STAGING/PRODUÇÃO) e some em LOCAL (conta DEV)
    open_login("local")
    check(not pg.is_visible("#google-login"), "LOCAL: sem botão Google (login DEV)")
    pg.select_option("select[name=env]", "staging")
    check(pg.is_visible("#google-login") and pg.inner_text("#google-login") == "ENTRAR COM GOOGLE", "STAGING: botão ENTRAR COM GOOGLE aparece")
    check(pg.is_visible("input[name=email]") and pg.is_visible("input[name=password]"), "STAGING: e-mail + senha continuam na tela")
    pg.screenshot(path=f"{SHOTS}/g01_login_staging_desktop.png")

    # --- owner autorizado: Google → Supabase → token → /admin/api/session → allowlist → painel
    mock["mode"] = "owner"
    pg.click("#google-login")
    pg.wait_for_selector(".shell", timeout=10000)
    q = authorize_calls[-1]
    check(q.get("provider") == ["google"] and q.get("redirect_to") == [ADMIN], f"início do OAuth: /auth/v1/authorize provider=google redirect_to={q.get('redirect_to')}")
    check("access_token" not in pg.url and "error" not in pg.url, f"retorno: token removido do endereço ({pg.url})")
    check(pg.inner_text(".who").startswith("Gabriel") and "owner" in pg.inner_text(".who"), "owner autorizado entra (papel vindo do servidor)")
    check("dev:boss" not in storage_dump() and "rt_fake" not in storage_dump() and "fraiha_admin_oauth" not in storage_dump(),
          "nenhum token/refresh guardado em storage; marcador consumido")
    check(any("/admin/api/session" in c[2] for c in staging_calls), "sessão verificada no servidor (/admin/api/session)")
    pg.screenshot(path=f"{SHOTS}/g02_google_owner_dashboard.png")

    # --- logout encerra a sessão do Admin E a sessão Supabase/OAuth
    n = len(logout_calls)
    pg.click("header .btn.ghost"); pg.wait_for_selector("select[name=env]", timeout=5000)
    pg.wait_for_timeout(500)
    check(len(logout_calls) == n + 1 and logout_calls[-1] == "Bearer dev:boss", "logout: chama /auth/v1/logout do Supabase com o token da sessão")
    mark = time.time(); pg.wait_for_timeout(5500)
    check(pg.locator(".shell").count() == 0 and not [c for c in staging_calls if c[0] > mark], "logout: login na tela e nenhuma chamada administrativa depois")

    # --- usuário Google COMUM (conta FRAIHA válida fora da allowlist) → 403, não entra
    open_login("staging"); mock["mode"] = "normal"; n = len(logout_calls)
    pg.click("#google-login")
    pg.wait_for_selector(".banner.err", timeout=10000)
    check("NÃO é administradora" in pg.inner_text(".banner.err") and pg.locator(".shell").count() == 0, "Google de conta comum: servidor responde 403 not_admin e o painel NÃO abre")
    pg.wait_for_timeout(400)
    check(len(logout_calls) == n + 1 and logout_calls[-1] == "Bearer dev:jogador1", "conta recusada: sessão Supabase dela é encerrada (token descartado)")
    check("access_token" not in pg.url, "conta recusada: endereço limpo")
    pg.screenshot(path=f"{SHOTS}/g03_google_conta_comum_403.png")

    # --- OAuth cancelado/falha → volta ao login com erro
    open_login("staging"); mock["mode"] = "cancel"
    pg.click("#google-login")
    pg.wait_for_selector(".banner.err", timeout=10000)
    check("Login com Google não concluído" in pg.inner_text(".banner.err") and "denied" in pg.inner_text(".banner.err") and pg.locator(".shell").count() == 0,
          "OAuth cancelado: erro claro e permanece no login")
    check("error" not in pg.url, "OAuth cancelado: endereço limpo")
    pg.screenshot(path=f"{SHOTS}/g04_google_cancelado.png")

    # --- link pronto com #access_token (sem login iniciado nesta aba) → ignorado
    n_calls = len(staging_calls)
    pg.goto("about:blank")   # link aberto do zero (carga nova da página), como um link recebido de fora
    pg.goto(ADMIN + "#access_token=dev:boss&token_type=bearer"); pg.wait_for_selector("select[name=env]", timeout=8000)
    check(pg.locator(".shell").count() == 0 and "ignorado" in pg.inner_text(".banner.err") and "access_token" not in pg.url and len(staging_calls) == n_calls,
          "token injetado no link (sem login iniciado aqui): ignorado, nada enviado ao servidor")

    # --- 401 continua fail-closed numa sessão aberta pelo Google
    open_login("staging"); mock["mode"] = "owner"
    pg.click("#google-login"); pg.wait_for_selector(".shell", timeout=10000)
    mock["api401"] = True
    pg.goto(ADMIN + "#/live"); pg.wait_for_timeout(300); pg.goto(ADMIN + "#/dashboard")
    pg.wait_for_selector("select[name=env]", timeout=10000)
    mock["api401"] = False
    check(pg.locator(".shell").count() == 0 and "Sessão inválida" in pg.inner_text(".banner.err"), "sessão Google + 401 → sessão encerrada, volta ao login")

    # --- e-mail + senha continuam funcionando (STAGING, Supabase falso) e senha errada não entra
    open_login("staging")
    pg.fill("input[name=email]", "dono@exemplo.test"); pg.fill("input[name=password]", "errada-0000"); pg.click("button[type=submit]")
    pg.wait_for_selector(".banner.err", timeout=8000)
    check("E-mail ou senha incorretos" in pg.inner_text(".banner.err"), "e-mail/senha: senha errada recusada")
    pg.fill("input[name=password]", "senha-certa-123"); pg.click("button[type=submit]")
    pg.wait_for_selector(".shell", timeout=10000)
    check("owner" in pg.inner_text(".who"), "e-mail/senha (STAGING) continua funcionando")
    pg.click("header .btn.ghost"); pg.wait_for_selector("select[name=env]", timeout=5000)
    # LOCAL (conta DEV) também
    open_login("local"); pg.fill("input[name=dev]", "boss"); pg.click("button[type=submit]")
    pg.wait_for_selector(".shell", timeout=10000)
    check("owner" in pg.inner_text(".who"), "login DEV (LOCAL) continua funcionando")
    pg.click("header .btn.ghost"); pg.wait_for_selector("select[name=env]", timeout=5000)

    # --- nenhuma chave secreta exposta nos arquivos servidos
    served = "".join(raw(x) for x in ["/admin/", "/admin/src/app.js", "/admin/src/api.js", "/admin/src/config.js", "/admin/src/oauth.js", "/admin/src/ui.js", "/admin/src/views/index.js", "/admin/assets/admin.css"])
    leaked = [w for w in ["sb_secret", "service_role", "SUPABASE_SECRET", "SERVICE_ROLE_KEY", "client_secret"] if w in served]
    check(not leaked, f"nenhuma chave secreta nos arquivos servidos {leaked}")
    check("sb_publishable_" in raw("/admin/src/config.js"), "só a chave PUBLICÁVEL (a mesma do jogo) no navegador")

    # --- 393 px: tela de login com Google sem rolagem lateral
    pg.set_viewport_size({"width": 393, "height": 852})
    open_login("staging")
    sw = pg.evaluate("document.documentElement.scrollWidth")
    gb = pg.locator("#google-login").bounding_box()
    check(sw <= 393 and gb and gb["x"] >= 0 and gb["x"] + gb["width"] <= 393.5, f"393 px: login + botão Google cabem (scrollWidth {sw})")
    pg.screenshot(path=f"{SHOTS}/g05_login_staging_393.png", full_page=True)
    mock["mode"] = "owner"; pg.click("#google-login"); pg.wait_for_selector(".shell", timeout=10000)
    check(pg.evaluate("document.documentElement.scrollWidth") <= 393, "393 px: painel após login Google sem rolagem lateral")
    pg.screenshot(path=f"{SHOTS}/g06_google_owner_393.png")
    pg.click("header .btn.ghost"); pg.wait_for_selector("select[name=env]", timeout=5000)

    check(not [e for e in errors if "Content Security Policy" in e or "Uncaught" in e], "sem erro de JS/CSP no console: " + "; ".join(errors[:3]))
    pg.unroute_all(behavior="ignoreErrors"); b.close()

print("RESULT", "OK" if fails == 0 else f"{fails} FAIL")
sys.exit(1 if fails else 0)
