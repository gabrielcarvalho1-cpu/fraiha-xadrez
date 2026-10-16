extends SceneTree
## R136 · página das Ligas: escolher uma liga liberada com outro tema PERGUNTA antes ("Você deseja ativar o tema de
## peças e tabuleiro da Liga X nas suas partidas?" SIM/NÃO). NÃO não muda nada; SIM troca; a liga em uso não pergunta.
## Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/r136_tema_caixa_test.gd [-- --mobile-test]
var failures := 0
var checks := 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func run():
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(25)
	if stage.account_ui.is_open(): stage.account_ui.close()
	stage.account._receive({"type": "leagues_preview", "enabled": true})
	await frames(4)
	var hub = stage.hub
	var tm = stage.theme_manager
	hub.show_page("ranking")
	await frames(6)
	check(tm.active_theme == "wood", "começa na Madeira")
	var done := [0]
	hub._select_league("ouro", true, func(): done[0] += 1)
	await frames(3)
	var m = hub.notice_modal
	check(is_instance_valid(m) and m.visible and m.yes_button.visible, "Ouro: a caixa pergunta")
	check(is_instance_valid(m) and "Liga Ouro" in m.text_label.text and m.yes_button.text == "SIM" and m.ok_button.text == "NÃO", "texto e botões SIM / NÃO")
	check(tm.active_theme == "wood", "antes de responder nada muda")
	m.ok_button.pressed.emit()
	await frames(3)
	check(not m.visible and tm.active_theme == "wood" and done[0] == 0, "NÃO: fecha e continua na Madeira")
	hub._select_league("ouro", true, func(): done[0] += 1)
	await frames(3)
	check(m.visible, "Ouro de novo: pergunta de novo")
	m.yes_button.pressed.emit()
	await frames(3)
	check(not m.visible and tm.active_theme == "gold" and hub.selected_league == "ouro", "SIM: tema da Liga Ouro ativado")
	check(done[0] == 1, "depois do SIM a página se redesenha")
	hub._select_league("ouro", true)
	await frames(3)
	check(not m.visible and tm.active_theme == "gold", "a liga em uso não pergunta")
	hub._select_league("madeira", true)
	await frames(3)
	check(m.visible and "Liga Madeira" in m.text_label.text, "voltar para a Madeira também pergunta")
	m.yes_button.pressed.emit()
	await frames(3)
	check(tm.active_theme == "wood", "SIM: Madeira de volta")
	var shot := OS.get_environment("SHOT_DIR")
	print("RESULT " + ("%d/%d OK" % [checks, checks] if failures == 0 else "%d FALHAS" % failures))
	quit(0 if failures == 0 else 1)
