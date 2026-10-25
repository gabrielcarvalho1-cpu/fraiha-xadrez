extends SceneTree
## R184e · prévia das marcas de lance no celular (dama em a5 com captura em f5, como no print do dono).
## Uso: SHOT_DIR=<pasta> SHOT_TAG=x_ xvfb-run godot --rendering-driver opengl3 --path . -s tests/r184_move_hints_shots.gd -- --size 540x1200 --mobile-test
var stage
func _initialize(): call_deferred("run")
func frames(n := 6):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(540, 1200)
	var i := args.find("--size")
	if i >= 0:
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.mode = Window.MODE_WINDOWED
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	stage._start_bot("madeira", "w")
	await frames(20)
	var g = stage.game
	g.pieces.erase(Vector2i(3, 7))
	g.pieces[Vector2i(0, 3)] = "wQ"
	g.pieces[Vector2i(5, 3)] = "bP"
	g.pieces[Vector2i(6, 3)] = "bP"
	g.pieces.erase(Vector2i(5, 1)); g.pieces.erase(Vector2i(6, 1))
	g.pieces.erase(Vector2i(3, 6))
	g.selected = Vector2i(0, 3)
	var lm: Array[Vector2i] = []
	for x in range(1, 6): lm.append(Vector2i(x, 3))
	for y in [4, 5]: lm.append(Vector2i(0, y))
	lm.append_array([Vector2i(1, 2), Vector2i(2, 1), Vector2i(1, 4), Vector2i(2, 5), Vector2i(3, 6), Vector2i(0, 2), Vector2i(3, 0)])
	g.legal_moves = lm
	g.queue_redraw()
	await shot("lances")
	quit(0)
