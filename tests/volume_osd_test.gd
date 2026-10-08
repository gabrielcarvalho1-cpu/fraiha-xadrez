extends SceneTree
## OSD de volume: aparece com o valor quando Música/Efeitos mudam e some sozinho.
var checks := 0
var failures := 0

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
    checks += 1
    if ok: print("PASS ", label)
    else:
        failures += 1
        print("FAIL ", label)

func run():
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in 5: await process_frame
    var hub = stage.get_node("MainHub")
    var music_before = hub.music_volume * 100.0
    var fx_before = hub.volume * 100.0
    check(not is_instance_valid(hub.volume_osd) or not hub.volume_osd.panel.visible, "OSD escondido ao abrir o jogo (carregar preferências não mostra aviso)")
    hub._set_music_volume(40.0)
    await process_frame
    var osd = hub.volume_osd
    check(is_instance_valid(osd) and osd.panel.visible and osd.title.text.begins_with("MÚSICA") and osd.value_label.text == "40%", "mudar Música mostra 'MÚSICA 40%'")
    # R53 · espera por TEMPO, não por quadros: o fade-in dura 0,12 s e o OSD fica 1,1 s antes de sumir.
    # Com 20 quadros fixos, numa máquina lenta (headless ~13 qps = 1,5 s) o OSD já tinha sumido.
    var t_fade := Time.get_ticks_msec()
    while Time.get_ticks_msec() - t_fade < 300: await process_frame
    check(osd.panel.modulate.a > 0.9, "OSD aparece com fade-in")
    hub._set_volume(0.0)
    await process_frame
    check(osd.title.text.begins_with("EFEITOS") and "MUDO" in osd.title.text and osd.value_label.text == "0%", "Efeitos em 0 mostra 'MUDO'")
    check(osd.panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "OSD não bloqueia cliques")
    var deadline = Time.get_ticks_msec() + 2500
    while osd.panel.visible and Time.get_ticks_msec() < deadline: await process_frame
    check(not osd.panel.visible, "OSD some sozinho depois de ~1,5 s")
    hub._set_music_volume(music_before)
    hub._set_volume(fx_before)
    print("VOLUME_OSD_CHECKS=", checks, " FAILURES=", failures)
    quit(failures)
