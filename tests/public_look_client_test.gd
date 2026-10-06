extends SceneTree
## R41 · O que um jogador VÊ do adversário Fundador no Casual: retrato com avatar Fundador, moldura e selo
## na tela "ADVERSÁRIO ENCONTRADO" (com o título) e na faixa da partida, e no cartão de perfil.
## Rodar: tests/run_public_look_client.sh [--shots]
var failures := 0
var checks := 0
var shots := OS.get_environment("LOOK_SHOTS") != ""
func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)
func _initialize(): call_deferred("run")
func wait_until(cond: Callable, seconds: float) -> bool:
    var end = Time.get_ticks_msec() + int(seconds * 1000)
    while Time.get_ticks_msec() < end:
        if cond.call(): return true
        await process_frame
    return cond.call()
func shot(n: String):
    if not shots: return
    for i in 6: await process_frame
    root.get_texture().get_image().save_png("/tmp/claude-0/sc/look_%s%s.png" % [n, OS.get_environment("LOOK_SIZE")])
func frame_style(p: Node) -> String:
    if p == null: return ""
    var f = p.find_child("ClubFrame", true, false)
    return String(f.style) if f != null and f.visible else ""
func run():
    var sz := OS.get_environment("LOOK_SIZE")   # celular: "390x844" (com -- --mobile-test)
    var dims := Vector2i(1920, 1080) if sz.is_empty() else Vector2i(int(sz.split("x")[0]), int(sz.split("x")[1]))
    root.mode = Window.MODE_WINDOWED
    root.size = dims
    root.content_scale_size = root.size
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(3): await process_frame
    stage.account_ui.hide_ui()
    stage.hub.play_online_requested.emit()
    check(await wait_until(func(): return stage.account.online_ready(), 8.0), "convidado conectado ao servidor")
    await process_frame
    var q = stage.casual_ui.box.find_child("Queue_casual_3min", true, false)
    q.pressed.emit()
    check(await wait_until(func(): return stage.casual_ui.screen == "found", 25.0), "ADVERSÁRIO ENCONTRADO")
    var fp = stage.casual_ui.box.find_child("FoundPortrait", true, false)
    check(fp != null and fp.avatar_rect.texture != null, "tela: retrato do adversário com o avatar dele")
    check(frame_style(fp) == "fundador", "tela: moldura Fundador no retrato do adversário")
    check(fp != null and fp.seal_rect.visible and fp.seal_rect.texture != null, "tela: selo Fundador no canto do retrato")
    var tl = stage.casual_ui.box.find_child("FoundTitle", true, false)
    check(tl != null and tl.text == "Fundador do Reino", "tela: título do adversário (Fundador do Reino)")
    await shot("1_encontrado")
    check(await wait_until(func(): return stage.casual.status == "playing", 12.0), "partida começou")
    for i in 10: await process_frame
    var top: Dictionary = stage.casual_ui.strips.top
    var bottom: Dictionary = stage.casual_ui.strips.bottom
    var land: bool = root.size.x > root.size.y and root.size.y < 600
    check((top.portrait.avatar_rect.texture != null and frame_style(top.portrait) == "fundador") and (land or (top.seal.visible and not top.portrait.seal_rect.visible)), "faixa do adversário: avatar + moldura Fundador + selo (ao lado do nome, sem repetir no retrato)")
    # R46 (placa aprovada): no celular deitado o retrato pequeno também aparece, junto com o selo
    if land: check(top.portrait.visible and top.portrait.size.x <= 32.0 and top.portrait.seal_rect.visible and not top.seal.visible and top.name.get_line_count() <= 2 and top.name.get_visible_line_count() == top.name.get_line_count(), "celular deitado: retrato pequeno com o selo no canto; nome inteiro (%s)" % top.name.text)
    check(frame_style(bottom.portrait) == "" and not bottom.seal.visible, "minha faixa (convidado, free): sem moldura premium nem selo")
    await shot("2_partida")
    var pp = stage.profile_popup
    pp.toggle("chess_" + String(top.color), stage.casual_ui.strip_info(String(top.color)), top.bg.get_global_rect())
    check(await wait_until(func(): return pp.is_open(), 3.0), "cartão de perfil do adversário abre")
    for i in 6: await process_frame
    var cf = pp.view.find_child("CardFrame", true, false)
    var cb = pp.view.find_child("CardBadge", true, false)
    check(cf != null and cf.visible and String(cf.style) == "fundador", "cartão: moldura Fundador sobre a foto")
    check(cb != null and cb.visible, "cartão: selo Fundador")
    await shot("3_cartao")
    pp.close()
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
