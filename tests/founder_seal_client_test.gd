extends SceneTree
## R62 · selo Fundador na faixa da partida (Casual e Ranked; PC, celular em pé e deitado), com o próprio jogador
## Fundador (conta de teste) contra um adversário Fundador (tests/server/founder_peer.cjs).
## Contrato do HUD atual: retrato sem moldura premium; o selo fica AO LADO DO NOME (não no canto do retrato),
## visível, dentro da faixa e sem cobrir o nome. Rodar: tests/run_founder_seal_client.sh [casual|ranked] [--mobile|--land]
var checks := 0
var failures := 0
func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)
func wait_until(cond: Callable, seconds: float) -> bool:
    var end := Time.get_ticks_msec() + int(seconds * 1000.0)
    while Time.get_ticks_msec() < end:
        if cond.call(): return true
        await process_frame
    return cond.call()
func _initialize(): call_deferred("run")

func seal_ok(strip: Dictionary, who: String):
    var seal: TextureRect = strip.seal
    var nm: Label = strip.name
    var shown: bool = (seal.visible and seal.texture != null and seal.is_visible_in_tree())
    check(shown, "%s: selo Fundador visível" % who)
    check(not strip.portrait.seal_rect.visible, "%s: sem selo repetido no canto do retrato" % who)
    if not shown: return
    var sr := seal.get_global_rect()
    var br: Rect2 = strip.bg.get_global_rect()
    check(br.grow(2.0).encloses(sr), "%s: selo dentro da faixa (%s em %s)" % [who, sr, br])
    var px := nm.get_theme_font_size("font_size")
    var font: Font = nm.get_theme_font("font")
    var tw := font.get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
    var name_end := nm.get_global_rect().position.x + minf(tw, nm.size.x)
    check(sr.position.x >= name_end - 1.0, "%s: selo depois do nome, sem cobrir o texto" % who)
    check(tw <= nm.size.x + 1.0, "%s: nome inteiro, sem corte (%s, %.0f de %.0f px)" % [who, nm.text, tw, nm.size.x])
    check(not sr.intersects(strip.portrait.get_global_rect()) or not strip.portrait.is_visible_in_tree(), "%s: selo não cobre o retrato" % who)

func run():
    var kind := OS.get_environment("SEAL_KIND")
    if kind.is_empty(): kind = "casual"
    var sz := OS.get_environment("LOOK_SIZE")
    var dims := Vector2i(1920, 1080) if sz.is_empty() else Vector2i(int(sz.split("x")[0]), int(sz.split("x")[1]))
    root.mode = Window.MODE_WINDOWED
    root.size = dims
    root.content_scale_size = root.size
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(6): await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    var nick := "EuFund%d" % (Time.get_ticks_msec() % 100000)
    acc.access_token = "dev:" + nick
    acc.user_id = "pending"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conta conectada")
    if acc.needs_nickname: acc.create_profile(nick)
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    acc.send_server({"type": "dev_set_entitlements", "is_founder": true, "club_active": true, "club_expires_at": Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) + 86400) + "Z"})
    check(await wait_until(func(): return stage.hub.is_founder() and stage.hub.current_badge() != "", 6.0), "eu sou Fundador (selo %s)" % stage.hub.current_badge())
    var ui = stage.casual_ui if kind == "casual" else stage.ranked_ui
    var ctl = stage.casual if kind == "casual" else stage.ranked
    if kind == "casual": stage._open_casual()
    else: stage._open_ranked()
    for i in 6: await process_frame
    ctl.queue(kind + "_3min")
    check(await wait_until(func(): return ctl.status == "playing", 30.0), "%s: partida começou contra o Fundador" % kind)
    for i in 20: await process_frame
    var land: bool = root.size.x > root.size.y and root.size.y < 600
    var lab := "%s_%s" % [kind, "deitado" if land else ("em_pe" if root.size.x < root.size.y else "pc")]
    seal_ok(ui.strips.top, lab + " · adversário")
    seal_ok(ui.strips.bottom, lab + " · eu")
    check(not ui.strips.top.portrait.frame_node or not ui.strips.top.portrait.frame_node.visible or not land, lab + ": sem moldura premium na faixa (HUD atual)")
    var out := OS.get_environment("SEAL_SHOTS")
    if out != "":
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [OS.get_environment("SEAL_TAG"), lab]))
    var pp = stage.profile_popup
    var top: Dictionary = ui.strips.top
    pp.toggle("chess_" + String(top.color), ui.strip_info(String(top.color)), top.bg.get_global_rect())
    check(await wait_until(func(): return pp.is_open(), 3.0), lab + ": cartão do adversário abre")
    for i in 6: await process_frame
    var cf = pp.view.find_child("CardFrame", true, false)
    var cb = pp.view.find_child("CardBadge", true, false)
    check(cf != null and cf.visible and String(cf.style) == "fundador" and cb != null and cb.visible, lab + ": cartão com moldura e selo Fundador")
    pp.close()
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
