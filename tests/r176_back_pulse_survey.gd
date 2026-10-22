extends SceneTree
## R176 · levantamento: em cada tela, quais botões de VOLTAR/SAIR/DESISTIR/FECHAR/CANCELAR/INÍCIO estão
## com o tom avermelhado (BackPulse) e quais botões visíveis NÃO estão (para conferir se falta algum).
const BP := preload("res://ui_kit/back_pulse.gd")
func _initialize(): call_deferred("run")
func frames(n := 6):
	for i in n: await process_frame
func label_of(b: BaseButton) -> String:
	var t := String(b.text) if b is Button else ""
	if t.is_empty():
		for c in b.get_children():
			if c is Label and not String(c.text).is_empty(): return String(c.text)
			for cc in c.get_children():
				if cc is Label and not String(cc.text).is_empty(): return String(cc.text)
	return t
func survey(tag: String):
	await create_timer(0.35).timeout
	var on := []
	var off := []
	for n in root.find_children("*", "BaseButton", true, false):
		var b: BaseButton = n
		if not b.is_visible_in_tree(): continue
		var r := b.get_global_rect()
		if r.size.x < 2 or r.end.x < 0 or r.position.x > 4000: continue
		var desc := "%s[%s]" % [b.name, label_of(b).replace("\n", " ").left(28)]
		if b.has_node("BackPulse"): on.append(desc)
		else: off.append(desc)
	print("== ", tag)
	print("   VERMELHO: ", ", ".join(on))
	print("   outros:   ", ", ".join(off))
func run():
	var size := Vector2i(1920, 1080)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open():
		await survey("conta (login)")
		stage.account_ui.hide_ui()
	await frames(6)
	await survey("home")
	var hub = stage.hub
	for id in hub.pages.keys():
		hub.show_page(id)
		await frames(6)
		await survey("página " + str(id))
	hub.show_page("home") if hub.pages.has("home") else null
	hub.open_premium("founder")
	await frames(8)
	await survey("premium fundador")
	hub.premium.open_payment("founder")
	await frames(8)
	await survey("pagamento: escolha")
	hub.close_modal() if hub.has_method("close_modal") else null
	stage._start_bot("easy", "w")
	await frames(10)
	await survey("partida contra o bot")
	quit(0)
