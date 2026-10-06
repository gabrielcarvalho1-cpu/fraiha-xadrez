extends SceneTree
## Ritmos do Ranked controlados pelo Admin: a tela JOGAR RANQUEADO mostra SÓ os ritmos abertos, sem buracos,
## e se refaz sozinha quando o Admin muda (aviso 'ranked_modes' do servidor). Servidor LOCAL real + API Admin real.
## Uso: tests/run_ranked_modes_client.sh  (SHOTS=<pasta> grava capturas quando há tela — xvfb)
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
func admin(mode: String, enabled: bool) -> int:
    var http = HTTPRequest.new()
    root.add_child(http)
    var body = JSON.stringify({"enabled": enabled, "reason": "teste de liquidez", "confirm": mode})
    http.request(API + "/admin/api/queues/ranked/" + mode, PackedStringArray(["Authorization: Bearer dev:boss", "Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
    var r = await http.request_completed
    http.queue_free()
    return int(r[1])
func shown() -> Array:
    var out := []
    for id in ["ranked_3min", "ranked_5min", "ranked_10min", "ranked_20min"]:
        if stage.ranked_ui.box.find_child("Queue_" + id, true, false) != null: out.append(id)
    return out
func rows() -> Array:
    var g = stage.ranked_ui.box.find_child("ModeGrid", true, false)
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
    var ap = stage.ranked_ui.art_panel
    ap.layout(root.get_visible_rect().size)
    var vis = ap.queue_hits.filter(func(b): return b.visible).size()
    check(vis == mode_ids.size(), "%s: painel desktop com %d cartão(ões) clicável(is)" % [label, vis])

func run():
    API = "http://127.0.0.1:%s" % OS.get_environment("RANKED_MODES_PORT")
    SHOTS = OS.get_environment("SHOTS")
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(6): await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    var nick = "Ritmos%d" % (Time.get_ticks_msec() % 100000)
    acc.access_token = "dev:" + nick
    acc.user_id = "pending"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conta conectada")
    if acc.needs_nickname: acc.create_profile(nick)
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    check(acc.ranked_modes_known and acc.ranked_modes.size() == 4, "acct_state trouxe os 4 ritmos abertos")
    stage._open_ranked()
    await expect(["ranked_3min", "ranked_5min", "ranked_10min", "ranked_20min"], "4 abertos", [2, 2])
    await shot("r4")
    # exemplo do dono: Relâmpago OFF, Rápida ON, Normal ON, Convencional OFF → só RÁPIDA e NORMAL
    check(await admin("ranked_3min", false) == 200 and await admin("ranked_20min", false) == 200, "Admin desligou Relâmpago e Convencional")
    await expect(["ranked_5min", "ranked_10min"], "2 abertos (tela aberta, sem recarregar)", [2])
    await shot("r2")
    # entrada num ritmo escondido é recusada pelo SERVIDOR (cliente adulterado)
    var errs := []
    stage.account.server_message.connect(func(m): if String(m.get("type", "")) == "ranked_error": errs.append(String(m.get("code", ""))))
    acc.send_server({"type": "ranked_queue", "mode": "ranked_20min"})
    check(await wait_until(func(): return errs.has("mode_disabled"), 5.0), "fila escondida forçada: servidor recusa (mode_disabled)")
    await admin("ranked_10min", false)
    await expect(["ranked_5min"], "1 aberto (centralizado)", [1])
    await shot("r1")
    await admin("ranked_5min", false)
    check(await wait_until(func(): return stage.ranked_ui.box.find_child("RankedUnavailable", true, false) != null, 5.0), "nenhum aberto: RANQUEADA TEMPORARIAMENTE INDISPONÍVEL")
    await expect([], "0 abertos", [])
    await shot("r0")
    await admin("ranked_3min", true); await admin("ranked_5min", true); await admin("ranked_10min", true)
    await expect(["ranked_3min", "ranked_5min", "ranked_10min"], "3 abertos", [2, 1])
    check(stage.ranked_ui.box.find_child("RankedUnavailable", true, false) == null, "aviso some quando reabre")
    await shot("r3")
    await admin("ranked_20min", true)
    await expect(["ranked_3min", "ranked_5min", "ranked_10min", "ranked_20min"], "4 de novo", [2, 2])
    # celular estreito: um por linha
    if DisplayServer.get_name() == "headless":
        print("SKIP estreito: sem janela no modo headless (rode com xvfb: SHOTS=<pasta>)")
        await admin("ranked_3min", true)
        print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
        quit(failures)
        return
    DisplayServer.window_set_size(Vector2i(390, 844))
    root.size = Vector2i(390, 844)
    for i in range(6): await process_frame
    stage.ranked_ui.open_modes()
    await admin("ranked_3min", false)
    # janela estreita no desktop: o painel de arte (escalado) reorganiza os cartões abertos; a grade de 1 coluna
    # vale para o celular (Mobile.active / _narrow(), a mesma regra de colunas de antes)
    check(await wait_until(func(): return shown() == ["ranked_5min", "ranked_10min", "ranked_20min"], 5.0), "janela estreita: 3 abertos, sem o fechado")
    await shot("r3_narrow")
    await admin("ranked_3min", true)
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
