extends SceneTree
## R48 · Casual controlado pelo Admin: a tela JOGAR ONLINE mostra SÓ os ritmos abertos, sem buracos, e se refaz
## sozinha quando o Admin muda (aviso 'casual_modes'); com o Casual fechado mostra CASUAL TEMPORARIAMENTE
## INDISPONÍVEL, some o CONVIDAR AMIGO e o botão JOGAR ONLINE da Home avisa. Quem estava na fila sai com aviso.
## Servidor LOCAL real + API Admin real. Uso: tests/run_casual_modes_client.sh (SHOTS=<pasta> com xvfb)
var failures = 0
var stage
var API := ""
var SHOTS := ""
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
func admin(path: String, enabled: bool, confirm: String) -> int:
    var http = HTTPRequest.new()
    root.add_child(http)
    var body = JSON.stringify({"enabled": enabled, "reason": "teste do casual", "confirm": confirm})
    http.request(API + "/admin/api/queues/" + path, PackedStringArray(["Authorization: Bearer dev:boss", "Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
    var r = await http.request_completed
    http.queue_free()
    return int(r[1])
func mode(m: String, on: bool) -> int:
    return await admin("casual/" + m, on, m)
func shown() -> Array:
    var out := []
    for id in ["casual_3min", "casual_5min", "casual_10min", "casual_20min"]:
        if stage.casual_ui.box.find_child("Queue_" + id, true, false) != null: out.append(id)
    return out
func rows() -> Array:
    var g = stage.casual_ui.box.find_child("ModeGrid", true, false)
    if g == null: return []
    return g.get_children().map(func(r): return r.get_children().filter(func(c): return c is PanelContainer).size())
func shot(name: String):
    if SHOTS.is_empty() or DisplayServer.get_name() == "headless": return
    for i in range(4): await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(SHOTS + "/" + name + ".png")
func expect(mode_ids: Array, label: String, layout: Array):
    check(await wait_until(func(): return shown() == mode_ids, 5.0), "%s: jogo mostra %s (veio %s)" % [label, mode_ids, shown()])
    check(rows() == layout, "%s: grade sem buracos %s (veio %s)" % [label, layout, rows()])
    var ap = stage.casual_ui.art_panel
    ap.layout(root.get_visible_rect().size)
    var vis = ap.queue_hits.filter(func(b): return b.visible).size()
    check(vis == mode_ids.size(), "%s: painel desktop com %d cartão(ões) clicável(is)" % [label, vis])
func online_sub() -> String:
    for b in stage.hub.menu_buttons:
        if stage.hub.title_of(b) == "JOGAR ONLINE":
            var rs = b.find_child("RefSubtitle", true, false)
            return String(rs.text) if rs != null else ""
    return ""

func run():
    API = "http://127.0.0.1:%s" % OS.get_environment("CASUAL_MODES_PORT")
    SHOTS = OS.get_environment("SHOTS")
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(6): await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    var nick = "Casual%d" % (Time.get_ticks_msec() % 100000)
    acc.access_token = "dev:" + nick
    acc.user_id = "pending"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conta conectada")
    if acc.needs_nickname: acc.create_profile(nick)
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    check(acc.casual_modes_known and acc.casual_modes.size() == 4, "acct_state trouxe os 4 ritmos do Casual abertos")
    check(online_sub() == "Partida casual · fila automática", "Home: JOGAR ONLINE normal (%s)" % online_sub())
    stage._open_casual()
    await expect(["casual_3min", "casual_5min", "casual_10min", "casual_20min"], "4 abertos", [2, 2])
    check(stage.casual_ui.box.find_child("InviteFriendButton", true, false) != null, "CONVIDAR AMIGO visível com o Casual aberto")
    await shot("c4")
    # entra na fila do Relâmpago e o Admin fecha o Relâmpago: sai da fila com aviso, tela volta sem o ritmo
    stage.casual.queue("casual_3min")   # mesmo caminho do cartão ENTRAR NA FILA
    check(await wait_until(func(): return stage.casual.searching, 5.0), "entrou na fila do Relâmpago")
    var errs := []
    stage.account.server_message.connect(func(m): if String(m.get("type", "")) == "casual_error": errs.append(String(m.get("code", ""))))
    check(await mode("casual_3min", false) == 200 and await mode("casual_20min", false) == 200, "Admin desligou Relâmpago e Convencional")
    var left_ok: bool = await wait_until(func(): return errs.has("mode_disabled") and not stage.casual.searching, 5.0)
    check(left_ok, "quem esperava saiu da fila com aviso (mode_disabled)")
    check(await wait_until(func(): return is_instance_valid(stage.casual_ui.notice) and "temporariamente desativado" in stage.casual_ui.notice.text, 3.0), "aviso claro para quem saiu da fila: " + (stage.casual_ui.notice.text if is_instance_valid(stage.casual_ui.notice) else "-"))
    await shot("c_removido")
    stage._open_casual()
    await expect(["casual_5min", "casual_10min"], "2 abertos (sem recarregar)", [2])
    await shot("c2")
    errs.clear()
    acc.send_server({"type": "casual_queue", "mode": "casual_20min"})
    check(await wait_until(func(): return errs.has("mode_disabled"), 5.0), "fila escondida forçada: servidor recusa (mode_disabled)")
    await mode("casual_5min", false); await mode("casual_10min", false)
    check(await wait_until(func(): return stage.casual_ui.box.find_child("CasualUnavailable", true, false) != null, 5.0), "nenhum ritmo: CASUAL TEMPORARIAMENTE INDISPONÍVEL")
    await expect([], "0 abertos", [])
    check(stage.casual_ui.box.find_child("InviteFriendButton", true, false) == null, "sem CONVIDAR AMIGO com o Casual fechado")
    check(online_sub() == "Temporariamente indisponível", "Home: JOGAR ONLINE avisa indisponível (%s)" % online_sub())
    await shot("c0")
    for m in ["casual_3min", "casual_5min", "casual_10min", "casual_20min"]: await mode(m, true)
    await expect(["casual_3min", "casual_5min", "casual_10min", "casual_20min"], "4 de novo", [2, 2])
    check(online_sub() == "Partida casual · fila automática", "Home: JOGAR ONLINE volta ao normal")
    # Casual inteiro (família) OFF/ON
    check(await admin("casual", false, "casual") == 200, "Admin desligou o Casual inteiro")
    check(await wait_until(func(): return stage.casual_ui.box.find_child("CasualUnavailable", true, false) != null, 5.0), "Casual inteiro OFF: indisponível")
    check(online_sub() == "Temporariamente indisponível", "Home avisa com o Casual inteiro OFF")
    await shot("c_off")
    check(await admin("casual", true, "casual") == 200, "Admin religou o Casual")
    await expect(["casual_3min", "casual_5min", "casual_10min", "casual_20min"], "Casual religado", [2, 2])
    check(acc.ranked_modes.size() == 4, "Ranked não foi afetado")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
