extends SceneTree
## R53 · Capturas das telas do celular redesenhadas (comparação lado a lado com as referências aprovadas).
## Uso: SHOT_DIR=<pasta> [SHOT_TAG=<prefixo>] xvfb-run godot --rendering-driver opengl3 --path <proj> \
##        -s tests/mobile_ref_shots.gd -- --mobile-test --size 390x844 [--only mais,history,...]
var stage
var hub

func _initialize(): call_deferred("run")

func frames(n := 6):
	for i in n: await process_frame

func shot(name: String):
	await frames(10)
	await RenderingServer.frame_post_draw
	var p := OS.get_environment("SHOT_DIR").path_join(OS.get_environment("SHOT_TAG") + "_" + name + ".png")
	root.get_texture().get_image().save_png(p)
	print("SHOT ", p)

func run():
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(390, 844)
	var i := args.find("--size")
	if i >= 0:
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	var only: PackedStringArray = []
	i = args.find("--only")
	if i >= 0: only = args[i + 1].split(",")
	root.mode = Window.MODE_WINDOWED
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	hub = stage.get_node("MainHub")
	# conta de teste (sem rede): o estado que o acct_state preencheria — Ranked e Perfil com dados reais
	var acc = stage.account
	acc.user_id = "u1"
	acc.access_token = "teste"
	acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.ranked = {"ranked_3min": {"league": 1, "pl": 0, "highest_league": 1, "wins": 30, "losses": 8, "draws": 0, "matches": 38},
		"ranked_5min": {"league": 0, "pl": 12, "highest_league": 0, "wins": 4, "losses": 2, "draws": 0, "matches": 6}}
	stage._sync_theme_unlocks()
	await frames()
	for page in ["main", "mais", "about", "history", "profile", "bot", "ranking"]:
		if not only.is_empty() and page not in only: continue
		if page == "mais": hub.mobile_ui.show_page("mais")   # MAIS é só do celular (não existe no hub do PC)
		else: hub.show_page(page)
		await frames()
		await shot(page)
	if only.is_empty() or "ranked" in only:
		hub.show_page("main")
		await frames()
		stage._open_ranked()
		await frames()
		await shot("ranked")
		stage.ranked_ui.close_panel()
		stage.open_home()
		await frames()
	if only.is_empty() or "match" in only:
		stage._start_bot("madeira", "w")
		await frames(20)
		await shot("match")
	quit()
