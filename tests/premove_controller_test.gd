extends SceneTree
## R53 · Pré-move com o controlador do Ranked/Casual (sem a propriedade local_mode): antes, bool(null) abortava
## world._premove_color() com erro de script a cada consulta (pré-move quebrado nas partidas online).
## Uso: xvfb-run godot --path <proj> -s tests/premove_controller_test.gd
var failures := 0

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run():
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	for i in 8: await process_frame
	var world = stage.game
	var ranked = stage.ranked
	check(ranked != null and ranked.get("local_mode") == null, "controlador do Ranked não tem local_mode (cenário do erro)")
	world.premove_enabled = true
	world.game_started = true
	world.game_over = false
	world.settings_open = false
	world.bot = ranked
	ranked.active = true
	ranked.status = "playing"
	ranked.human_color = "b"
	check(world._premove_color() == "b", "Ranked em andamento: pré-move na cor do jogador")
	ranked.status = "finished"
	check(world._premove_color() == "", "Ranked terminado: sem pré-move")
	ranked.status = "playing"
	ranked.active = false
	check(world._premove_color() == "", "controlador inativo: sem pré-move")
	# bot local (dois jogadores no mesmo aparelho): sem pré-move
	var bc = stage.bot_controller
	world.bot = bc
	bc.active = true
	bc.local_mode = true
	check(world._premove_color() == "", "partida local: sem pré-move")
	bc.local_mode = false
	bc.active = false
	world.bot = null
	ranked.active = false
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
