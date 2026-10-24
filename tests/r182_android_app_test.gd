extends SceneTree
## R182 · app Android: endereço do rastreio a partir do servidor, PKCE (RFC 7636), base HTTP do servidor,
## lote do rastreador do app (formato aceito pela rota /t) e ids persistentes.
const AppTrack = preload("res://telemetry/app_track.gd")
const AccountService = preload("res://account/account_service.gd")
var failures := 0

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize():
	call_deferred("run")

func run():
	check(AppTrack.track_url_from("wss://fraiha-xadrez-staging.onrender.com") == "https://fraiha-xadrez-staging.onrender.com/t", "rastreio: wss → https://…/t")
	check(AppTrack.track_url_from("ws://127.0.0.1:8140/x") == "http://127.0.0.1:8140/t", "rastreio: ws local com caminho")
	check(AppTrack.track_url_from("") == "", "rastreio: sem servidor = desligado")
	check(AccountService.http_base("wss://fraiha-xadrez-staging.onrender.com") == "https://fraiha-xadrez-staging.onrender.com", "login app: base https do servidor")
	var ch := AccountService.pkce_challenge("dBjftJeZ4CVP-mtzzwyDdAdocrnoyN0pX0Nw-l7iz0y4")
	check(ch == "ARmRhWp2r_HiiCBzqVPH8Zj0WfTr8CJN_2HN3Yo9e50", "PKCE S256 igual ao Python (%s)" % ch)
	check(not ch.contains("=") and not ch.contains("+") and not ch.contains("/"), "PKCE base64url sem padding")
	var t = AppTrack.new()
	t.vid = "ab".repeat(16); t.sid = "cd".repeat(16); t.t0 = Time.get_ticks_msec()
	t.push({"k": "screen", "n": "Entrada / Login"})
	t.push({"k": "screen", "n": "Entrada / Login"})
	t.push({"k": "click", "n": "Jogar como convidado", "id": "GuestButton"})
	var b = JSON.parse_string(t.body())
	check(b is Dictionary and b.sid == t.sid and b.vid == t.vid, "lote com sid/vid")
	check(b.e.size() == 2, "tela repetida não duplica (%d eventos)" % b.e.size())
	check(String(b.e[1].s) == "Entrada / Login", "clique leva a tela atual")
	check(b.has("d") and b.d.has("app") and String(b.d.app) == AppTrack.platform(), "1º lote informa o app (android/windows)")
	t.sent_first = true
	t.push({"k": "hb"})
	var b2 = JSON.parse_string(t.body())
	check(not b2.has("d"), "lotes seguintes sem dados do aparelho")
	t.free()
	check(AppTrack.get_instance() == null, "fora do Android não cria rastreador")
	var src := FileAccess.get_file_as_string("res://account/account_service.gd")
	check(src.count("provider=google&prompt=select_account&") == 2, "R184: Google sempre mostra a escolha de conta (site e app)")
	print("R182_ANDROID FAILS=%d" % failures)
	quit(1 if failures > 0 else 0)
