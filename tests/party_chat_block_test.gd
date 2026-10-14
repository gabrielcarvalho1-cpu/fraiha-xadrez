extends SceneTree
## R95 · o CHAT da mesa (camada acima da MARCHA / XEQUE) some quando o modo abre menu, tutorial, confirmação ou
## resultado, e volta na partida. Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/party_chat_block_test.gd
## Env opcional: SHOT_DIR=<pasta> grava prints (antes = com o bloqueio desligado à força; depois = R95).
var stage
var hub
var fails := 0

func _initialize(): call_deferred("run")

func frames(n := 8):
	for i in n: await process_frame

func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1

func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(name + ".png"))

func toggle_visible(pc) -> bool:
	return pc.visible and pc.toggle.is_visible_in_tree()

func run():
	var size := Vector2i(1280, 720)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	hub = stage.get_node("MainHub")
	var pc = stage.party_chat

	for game in ["marcha", "xeque"]:
		var m
		if game == "marcha":
			hub.open_marcha()
			m = hub.marcha
			m.tut_page = -1
			m.start_game()
		else:
			hub.open_xeque()
			m = hub.xeque
			m.start_game()
		await frames(10)
		pc.bind("sala-teste", game, ["Você", "Ana", "Bia", "Caio"])
		m.online = true
		await frames(6)
		check(toggle_visible(pc), game + ": botão CHAT visível na partida")
		await shot(game + "_partida")
		m.menu_open = true
		if m.has_method("_redraw"): m._redraw()
		await frames(6)
		check(not toggle_visible(pc), game + ": CHAT some com o menu aberto")
		await shot(game + "_menu_depois")
		# "antes" (R94): força o comportamento antigo para mostrar o problema
		m.set_process(false)
		pc.set_blocked(false)
		await frames(4)
		await shot(game + "_menu_antes")
		m.set_process(true)
		await frames(4)
		check(not toggle_visible(pc), game + ": bloqueio volta sozinho")
		pc.set_open(true)
		await frames(4)
		check(not pc.panel.is_visible_in_tree(), game + ": painel aberto também some com o menu")
		pc.set_open(false)
		m.menu_open = false
		await frames(6)
		check(toggle_visible(pc), game + ": CHAT volta ao fechar o menu")
		if game == "marcha":
			m.tut_page = 0
			await frames(4)
			check(not toggle_visible(pc), "marcha: CHAT some no tutorial")
			m.tut_page = -1
		else:
			m.confirm_quit = true
			await frames(4)
			check(not toggle_visible(pc), "xeque: CHAT some na confirmação de sair")
			m.confirm_quit = false
		await frames(4)
		check(toggle_visible(pc), game + ": CHAT volta depois")
		pc.unbind()
		m.online = false
		m.close()
		await frames(6)
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
