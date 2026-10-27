extends CanvasLayer
## R176 · "VOCÊ CONFIRMA ESSA TROCA?" — confirmação antes de aplicar/trocar avatar, ícone, moldura, cores do
## tabuleiro, peças, emotes/molduras da loja, remover a foto… Mesma arte das janelas do Premium (moldura escura
## com borda dourada, título dourado, botões NÃO / SIM). ESC ou clicar fora = NÃO.
const Art := preload("res://monetization/premium_art.gd")
const Mobile := preload("res://ui_v022/mobile_layout.gd")

signal answered(ok: bool)
signal cancel_button   # R197 · tocou no botão da esquerda/de baixo (não conta ESC nem tocar fora)
var _on_ok: Callable
var _done := false

## Abre a confirmação por cima de tudo. on_ok roda só no SIM.
static func ask(owner: Node, title: String, body: String, ok_text: String, on_ok: Callable, cancel_text := "NÃO") -> Node:
	# testes antigos (antes da confirmação): FRAIHA_AUTO_CONFIRM=1 responde SIM na hora
	if OS.get_environment("FRAIHA_AUTO_CONFIRM") == "1":
		if on_ok.is_valid(): on_ok.call()
		return null
	var c = load("res://ui_kit/confirm_box.gd").new()
	owner.get_tree().root.add_child(c)
	c._build(title, body, ok_text, cancel_text, on_ok)
	return c

## Atalho com o texto padrão: "TROCAR <O QUÊ>?" / "Você deseja mesmo aplicar <nome>?"
static func ask_change(owner: Node, what: String, name_text: String, on_ok: Callable) -> Node:
	return ask(owner, "CONFIRMAR TROCA?", "Você deseja mesmo aplicar %s:\n%s?" % [what, name_text], "SIM, APLICAR", on_ok)

func _build(title: String, body: String, ok_text: String, cancel_text: String, on_ok: Callable) -> void:
	name = "ConfirmBox"
	layer = 99
	_on_ok = on_ok
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var narrow := vs.x < 700.0
	var k := clampf(minf(vs.x / 1920.0, vs.y / 1080.0) * 1.25, 0.75, 1.3) if not Mobile.active(get_viewport()) else clampf(vs.x / 420.0, 0.85, 2.6)
	var dim := ColorRect.new()
	dim.name = "ConfirmDim"
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _answer(false))
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var f := Art.Frame.new("dark", int(24 * k))
	f.name = "ConfirmBoxPanel"
	f.custom_minimum_size.x = minf(vs.x - 32.0, 620.0 * k)
	f.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(f)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(14 * k))
	f.add_child(v)
	var tl := Art.label(v, title, int(28 * k), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
	tl.name = "ConfirmBoxTitle"
	var bl := Art.label(v, body, int(19 * k), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
	bl.name = "ConfirmBoxBody"
	var row: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	row.add_theme_constant_override("separation", int(14 * k))
	v.add_child(row)
	var no := Art.Cta.new(cancel_text, "dark", 56 * k, int(19 * k))
	no.name = "ConfirmBoxNo"
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func():
		if not _done: cancel_button.emit()
		_answer(false))
	var yes := Art.Cta.new(ok_text, "gold", 56 * k, int(19 * k))
	yes.name = "ConfirmBoxYes"
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(func(): _answer(true))
	if narrow:
		row.add_child(yes)
		row.add_child(no)
	else:
		row.add_child(no)
		row.add_child(yes)

func _unhandled_input(e):
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_answer(false)

func _answer(ok: bool) -> void:
	if _done: return
	_done = true
	answered.emit(ok)
	queue_free()
	if ok and _on_ok.is_valid(): _on_ok.call()
