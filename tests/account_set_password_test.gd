extends SceneTree
## DEFINIR SENHA em conta criada com Google: mesma conta (mesmo UUID), sem usuário novo, senha só para o Supabase.
## Supabase Auth MOCKADO (tests/mock/gotrue_password_mock.cjs) — nada real é tocado.
## Uso: tests/run_account_set_password.sh
var failures = 0
var AUTH := ""
var REC := ""
const PW := "NovaSenha!2026xyz"     # senha de TESTE (mock); o runner procura esta string em logs/arquivos

func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ", label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func wait_until(cond: Callable, seconds: float) -> bool:
    var end = Time.get_ticks_msec() + int(seconds * 1000)
    while Time.get_ticks_msec() < end:
        if cond.call(): return true
        await process_frame
    return cond.call()
func fetch(url: String, method := HTTPClient.METHOD_GET, body := "", headers := PackedStringArray()) -> Array:
    var http = HTTPRequest.new()
    root.add_child(http)
    http.request(url, headers, method, body)
    var r = await http.request_completed
    http.queue_free()
    var parsed = JSON.parse_string(r[3].get_string_from_utf8()) if r[3].size() > 0 else null
    return [r[1], parsed]
func buttons(node) -> Array:
    return node.find_children("*", "Button", true, false)
func press(ui, text: String) -> bool:
    for b in buttons(ui.panel):
        if b.text == text and b.is_visible_in_tree():
            b.pressed.emit()
            return true
    return false
func puts_count() -> int:
    var r = await fetch(AUTH + "/__bodies")
    return r[1].filter(func(x): return x.method == "PUT" and x.path.begins_with("/auth/v1/user")).size()

func run():
    var ap = int(OS.get_environment("MOCK_AUTH_PORT")); var wp = int(OS.get_environment("MOCK_WS_PORT"))
    AUTH = "http://127.0.0.1:%d" % ap
    REC = "http://127.0.0.1:%d" % (wp + 1)
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(3): await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    var ui = stage.account_ui
    acc._clear_session()
    acc.supabase_url = AUTH
    acc.public_key = "sb_publishable_test"
    acc.site_url = ""
    acc.server_url = "ws://127.0.0.1:%d" % wp     # "servidor FRAIHA" que só registra mensagens
    var notices := []
    acc.notice.connect(func(t, e): notices.append([t, e]))
    var saved := [0]
    acc.password_saved.connect(func(): saved[0] += 1)
    var st0 = (await fetch(AUTH + "/__state"))[1]

    # 1) sem login: não envia nada
    acc.update_password(PW, PW)
    check(notices.size() > 0 and "Entre na sua conta" in notices[-1][0] and notices[-1][1], "não autenticado: recusado com aviso")
    check(await puts_count() == 0, "não autenticado: nenhum PUT /auth/v1/user saiu")

    # 2) entra com Google (mesmo caminho do retorno #access_token: _adopt_session sem 'user' → GET /auth/v1/user)
    var g = (await fetch(AUTH + "/__google"))[1]
    acc._adopt_session({"access_token": g.access_token, "refresh_token": g.refresh_token, "expires_in": "3600"})
    check(await wait_until(func(): return acc.signed_in(), 5.0), "Google: sessão adotada")
    var uuid_before: String = acc.user_id
    check(uuid_before == "9249a3f2-bc90-45ea-b95b-a5b376421e0f" and acc.provider == "google", "Google: UUID %s, provedor google" % uuid_before)
    var direct = await fetch(AUTH + "/auth/v1/token?grant_type=password", HTTPClient.METHOD_POST, JSON.stringify({"email": acc.email, "password": PW}), PackedStringArray(["apikey: sb_publishable_test", "Content-Type: application/json"]))
    check(direct[0] == 400, "antes: conta Google ainda NÃO entra por senha")

    # 3) tela SUA CONTA → DEFINIR SENHA
    acc.server_ready = true
    acc.profile = {"nickname": "Dono"}
    acc.needs_nickname = false
    ui.open()
    await process_frame
    check(ui.page == "account" and buttons(ui.panel).any(func(b): return b.text == "DEFINIR SENHA"), "SUA CONTA mostra DEFINIR SENHA para conta Google")
    check(press(ui, "DEFINIR SENHA") and ui.page == "set_password", "abre a tela de senha")
    check(ui.fields.has("password") and ui.fields.has("password_confirm") and ui.fields.password.secret and ui.fields.password_confirm.secret, "dois campos de senha (ocultos)")

    # 4) validações (nada sai para o Supabase)
    var cases = [["", "", "Digite a nova senha"], ["curta1", "curta1", "pelo menos 8"], [PW, PW + "x", "não conferem"], ["a".repeat(73), "a".repeat(73), "no máximo"]]
    for c in cases:
        ui.fields.password.text = c[0]; ui.fields.password_confirm.text = c[1]
        press(ui, "SALVAR SENHA")
        await process_frame
        check(c[2] in ui.status_label.text and ui.fields.password.text == "" and ui.fields.password_confirm.text == "", "recusa local '%s' + campos limpos" % c[2])
    check(await puts_count() == 0 and saved[0] == 0, "validação local: nenhum envio")

    # 5) erros do Supabase são tratados
    for mode in [["same_password", "diferente da atual"], ["reauthentication_needed", "entre na conta de novo"], ["weak_password", "Senha fraca"]]:
        await fetch(AUTH + "/__fail?mode=" + mode[0])
        ui.fields.password.text = PW; ui.fields.password_confirm.text = PW
        press(ui, "SALVAR SENHA")
        check(await wait_until(func(): return mode[1] in ui.status_label.text, 5.0), "erro do Supabase '%s' → '%s'" % mode)
    check(saved[0] == 0, "erros: senha não marcada como salva")

    # 6) caminho feliz: define a senha
    ui.fields.password.text = PW; ui.fields.password_confirm.text = PW
    press(ui, "SALVAR SENHA")
    check(ui.fields.password.text == "" and ui.fields.password_confirm.text == "", "campos limpos logo após o envio")
    check(await wait_until(func(): return saved[0] == 1, 5.0), "senha salva (password_saved)")
    check("Senha salva" in ui.status_label.text, "mensagem de sucesso")
    var st1 = (await fetch(AUTH + "/__state"))[1]
    var me = st1.users.filter(func(u): return u.id == uuid_before)
    check(st1.count == st0.count, "NENHUM usuário novo (antes %d, depois %d)" % [st0.count, st1.count])
    check(me.size() == 1 and me[0].has_password and me[0].provider == "google", "senha gravada no MESMO usuário (mesmo UUID, ainda Google)")
    check(acc.user_id == uuid_before and acc.signed_in(), "sessão atual continua a mesma")

    # 7) Google continua: nova sessão Google → mesmo UUID
    var g2 = (await fetch(AUTH + "/__google"))[1]
    var who = await fetch(AUTH + "/auth/v1/user", HTTPClient.METHOD_GET, "", PackedStringArray(["apikey: sb_publishable_test", "Authorization: Bearer " + g2.access_token]))
    check(who[0] == 200 and who[1].id == uuid_before, "login Google depois: mesmo UUID")

    # 8) e-mail + nova senha → mesmo UUID (pelo fluxo normal do jogo: account.sign_in)
    var mail: String = acc.email
    acc.sign_out()
    acc.sign_in(mail, PW)
    check(await wait_until(func(): return acc.signed_in(), 5.0) and acc.user_id == uuid_before, "e-mail + nova senha: entra com o MESMO UUID")
    var wrong = await fetch(AUTH + "/auth/v1/token?grant_type=password", HTTPClient.METHOD_POST, JSON.stringify({"email": mail, "password": PW + "errada"}), PackedStringArray(["apikey: sb_publishable_test", "Content-Type: application/json"]))
    check(wrong[0] == 400, "senha incorreta não entra")
    var st2 = (await fetch(AUTH + "/__state"))[1]
    check(st2.count == st0.count, "depois de todos os logins: ainda nenhum usuário novo")

    # 9) sessão expirada → aviso, sem 'sucesso'
    await fetch(AUTH + "/__expire")
    acc.server_ready = true; acc.profile = {"nickname": "Dono"}
    ui.open("set_password")
    ui.fields.password.text = "OutraSenha!123"; ui.fields.password_confirm.text = "OutraSenha!123"
    press(ui, "SALVAR SENHA")
    check(await wait_until(func(): return "Sessão expirada" in ui.status_label.text, 5.0) and saved[0] == 1, "token expirado → 'Sessão expirada', nada salvo")

    # 10) onde a senha apareceu: só PUT /auth/v1/user e POST /token (Supabase). Nunca no servidor FRAIHA.
    var bodies = (await fetch(AUTH + "/__bodies"))[1]
    var with_pw = bodies.filter(func(x): return PW in x.body)
    check(with_pw.all(func(x): return (x.method == "PUT" and x.path == "/auth/v1/user") or x.path.begins_with("/auth/v1/token")), "senha só foi para o Supabase Auth (%d requisições)" % with_pw.size())
    var ws_msgs = (await fetch(REC))[1]
    check(ws_msgs is Array and not ws_msgs.any(func(m): return PW in m), "servidor FRAIHA (WebSocket) nunca recebeu a senha (%d mensagens)" % (ws_msgs.size() if ws_msgs is Array else -1))
    var leaked := []
    var d = DirAccess.open("user://")
    if d:
        for f in d.get_files():
            var fa = FileAccess.open("user://" + f, FileAccess.READ)
            if fa and PW in fa.get_as_text(): leaked.append(f)
    check(leaked.is_empty(), "senha não foi gravada em user:// %s" % [leaked])

    # 11) conta de e-mail mostra ALTERAR SENHA (mesma função)
    acc.provider = "email"
    ui.open("account")
    check(buttons(ui.panel).any(func(b): return b.text == "ALTERAR SENHA"), "conta de e-mail: botão ALTERAR SENHA")

    ui.hide_ui()
    acc.supabase_url = ""
    acc._clear_session()
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
