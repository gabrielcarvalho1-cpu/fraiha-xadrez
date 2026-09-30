extends SceneTree
## Conta no F5: estado "conectando", fluxo normal até acct_state e ausência de loop de invalid_token.
## Uso: /tmp/run_account_session.sh  (sobe servidor FRAIHA_DEV_AUTH + Auth falso)
var failures = 0
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
func texts(node) -> Array:
    return node.find_children("*", "Label", true, false).map(func(l): return l.text)
func run():
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(3): await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    var sends := []
    # 1) Conta com sessão, servidor ainda sem confirmar: AMIGOS não pede login.
    var url = acc.server_url
    acc.server_url = "ws://127.0.0.1:9"  # porta fechada: acct_state nunca chega
    acc.access_token = "dev:ContaPendente"
    acc.user_id = "pending"
    acc.email = "pendente@teste.local"
    acc._server_auth()
    check(acc.signed_in() and not acc.server_ready and not acc.has_profile() and acc.account_pending(), "sessão local sem acct_state: account_pending()")
    stage.hub.friends_requested.emit()
    check(stage.social_ui.is_open() and not stage.account_ui.is_open(), "AMIGOS não mostra login enquanto a conta conecta")
    check(texts(stage.social_ui.box).any(func(t): return t == "Conectando sua conta ao servidor..."), "mostra 'Conectando sua conta ao servidor...'")
    stage.social_ui.hide_ui()
    stage.account_ui.open()
    check(stage.account_ui.page == "waiting" and not texts(stage.account_ui.box).any(func(t): return "modo de teste" in t), "painel de conta mostra 'conectando' (sem 'Jogador:' vazio nem 'modo de teste')")
    stage.account_ui.hide_ui()
    # 2) Fluxo normal: acct_auth -> acct_state -> server_ready -> has_profile, com Amigos já aberto.
    acc.socket = null
    acc.server_url = url
    stage.hub.friends_requested.emit()
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "acct_state recebido: server_ready = true")
    if acc.needs_nickname: acc.create_profile("ContaPendente")
    check(await wait_until(func(): return acc.has_profile(), 6.0), "has_profile() = true")
    check(await wait_until(func(): return stage.social_ui.is_open() and stage.social_ui.has_list, 6.0), "Amigos aberto em 'conectando' carrega a lista sozinho quando a conta fica pronta")
    stage.social_ui.hide_ui()
    stage.account_ui.open()
    check(stage.account_ui.page == "account" and texts(stage.account_ui.box).has("Jogador: ContaPendente"), "painel de conta mostra o nickname depois do acct_state")
    stage.account_ui.hide_ui()
    # 2b) Conta existente + reconexão: a conexão cai e volta; acct_state já vem com perfil.
    acc.socket.close()
    check(await wait_until(func(): return not acc.server_ready, 5.0), "queda de conexão: server_ready volta a false")
    check(await wait_until(func(): return acc.has_profile(), 12.0), "reconexão automática: conta existente volta com perfil (has_profile)")
    # 3) Token recusado pelo servidor (JWT real contra FRAIHA_DEV_AUTH): renova só uma vez, sem loop.
    var auth_port = int(OS.get_environment("FAKE_AUTH_PORT"))
    if auth_port > 0:
        acc.supabase_url = "http://127.0.0.1:%d" % auth_port
        acc.public_key = "publishable-test"
        acc.server_ready = false
        acc.profile = {}
        acc.access_token = "eyJhbGciOiJIUzI1NiJ9." + "y".repeat(60) + ".0"
        acc.refresh_token = "refresh-0"
        if "auth_retried" in acc: acc.auth_retried = false
        acc.server_message.connect(func(_m): pass)
        var notices := []
        acc.notice.connect(func(t, e): notices.append(t))
        acc._server_auth()
        await wait_until(func(): return false, 6.0)
        var http = HTTPRequest.new()
        root.add_child(http)
        http.request("http://127.0.0.1:%d/count" % auth_port)
        var r = await http.request_completed
        var count = int(JSON.parse_string(r[3].get_string_from_utf8()).refreshes)
        print("DBG renovações de sessão em 6 s: ", count)
        check(count <= 1, "invalid_token: no máximo 1 renovação de sessão (sem loop) — foram %d" % count)
        check(not acc.server_ready and not acc.has_profile() and notices.any(func(t): return "Sessão" in t), "sessão recusada vira aviso ao jogador, não loop")
        check(acc.signed_in(), "sessão local não é apagada por recusa do servidor")
    acc.supabase_url = ""   # não deixa sessão falsa salva para os próximos testes
    acc._clear_session()
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
