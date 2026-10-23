extends CanvasLayer
## R176.9 · DICAS DOS BOTÕES no jogo inteiro (visual aprovado na R176.8c: ui_kit/fraiha_tooltip.gd).
## Lê o `tooltip_text` de qualquer controle — nada muda em quem já escreve dicas — e desenha a placa do jogo
## FORA do botão (embaixo; sem espaço, em cima; sem espaço nenhum, ao lado), sempre dentro da tela.
## A dica nativa do Godot fica desligada (project.godot: gui/timers/tooltip_delay_sec bem alto).
## Computador: aparece ao parar o mouse em cima (0,45 s). Celular: segurar o dedo no botão (0,5 s) mostra a dica e
## NÃO aperta o botão ao soltar.
## Texto "Título · explicação" (ou " — ") vira título + explicação; texto curto vira só título.
const Tip := preload("res://ui_kit/fraiha_tooltip.gd")
const DELAY := 0.45
const HOLD := 0.5
const SEPS := ["  ·  ", " · ", " — "]

var tip: Control = null
var target: Control = null
var shown_text := ""
var hover_t := 0.0
var touch_mode := false
var hold_t := -1.0
var hold_pos := Vector2.ZERO
var hold_shown := false
var _faking := false

func _ready():
	layer = 125
	name = "FraihaTooltips"
	process_mode = Node.PROCESS_MODE_ALWAYS

## "Título · explicação" → ["Título", "explicação"]
static func split(text: String) -> Array:
	var t := text.strip_edges()
	if "\n" in t:
		var i := t.find("\n")
		return [t.substr(0, i).strip_edges(), t.substr(i + 1).strip_edges().replace("\n", " ")]
	for s in SEPS:
		var i := t.find(s)
		if i > 0 and i <= 42:
			var b := t.substr(i + s.length()).strip_edges()
			return [t.substr(0, i).strip_edges(), b.left(1).to_upper() + b.substr(1)]
	if t.length() <= 34: return [t, ""]
	return ["", t]

static func tip_of(c: Control) -> String:
	var n: Node = c
	var hops := 0
	while n != null and n is Control and hops < 3:
		var s := String((n as Control).tooltip_text)
		if not s.strip_edges().is_empty(): return s
		if (n as Control).mouse_filter == Control.MOUSE_FILTER_STOP and n is BaseButton: return ""
		n = n.get_parent()
		hops += 1
	return ""

func _k() -> float:
	var vs := get_viewport().get_visible_rect().size
	if vs.y > vs.x: return clampf(vs.x / 430.0, 1.0, 1.6)
	return clampf(vs.y / 900.0, 0.85, 1.4)

func hide_tip():
	if tip != null and is_instance_valid(tip): tip.queue_free()
	tip = null
	shown_text = ""

func show_for(c: Control, text: String):
	hide_tip()
	var parts := split(text)
	tip = Tip.make(parts[0], parts[1], _k())
	tip.name = "FraihaTooltip"
	add_child(tip)
	shown_text = text
	_place(c)

func _place(c: Control):
	if tip == null or c == null or not is_instance_valid(c): return
	var vs := get_viewport().get_visible_rect()
	var r: Rect2 = c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size)   # em tela (camadas com escala)
	var fits_v := r.end.y + 8 + tip.size.y <= vs.end.y or r.position.y - 8 - tip.size.y >= vs.position.y
	if fits_v: tip.place_near(r, vs)
	else: tip.place_side(r, vs)

func _input(e: InputEvent):
	if _faking: return
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		touch_mode = true
	if e is InputEventMouseMotion and e.device != -1 and not e.relative.is_zero_approx():
		touch_mode = false   # mouse de verdade (notebook com tela de toque)
	if e is InputEventMouseButton:
		if e.pressed:
			hide_tip()
			hover_t = 0.0
			if e.device == -1: touch_mode = true   # toque emulado como mouse
			if touch_mode and e.button_index == MOUSE_BUTTON_LEFT:
				hold_t = 0.0
				hold_pos = e.position
				hold_shown = false
		else:
			if hold_shown:
				# a dica do toque longo apareceu: o "toque" já saiu do botão (_cancel_press), então soltar NÃO o aperta.
				# O soltar segue para a interface (libera o foco do mouse); só os tremidos do dedo são engolidos.
				hide_tip.call_deferred()
			hold_t = -1.0
			hold_shown = false
	elif e is InputEventMouseMotion:
		if hold_t >= 0.0 and not hold_shown and e.position.distance_to(hold_pos) > 12.0: hold_t = -1.0
		if hold_shown: get_viewport().set_input_as_handled()   # o dedo treme: o botão não volta a "estar apertado"
	elif e is InputEventKey and e.pressed:
		hide_tip()

func _process(delta):
	var vp := get_viewport()
	if vp == null: return
	if touch_mode:
		if hold_t < 0.0: return
		hold_t += delta
		if hold_t >= HOLD and not hold_shown:
			var c := vp.gui_get_hovered_control()
			var s := tip_of(c) if c != null else ""
			if s.is_empty():
				hold_t = -1.0
				return
			hold_shown = true
			target = c
			show_for(c, s)
			_cancel_press()
		return
	var h := vp.gui_get_hovered_control()
	var s := tip_of(h) if h != null else ""
	if h != target or s != shown_text and tip != null:
		if h != target:
			target = h
			hover_t = 0.0
			hide_tip()
		elif tip != null:
			show_for(h, s)   # o texto mudou com a dica aberta (ex.: som ligado/desligado)
		return
	if s.is_empty() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if tip != null: hide_tip()
		return
	hover_t += delta
	if tip == null and hover_t >= DELAY: show_for(h, s)
	elif tip != null and is_instance_valid(h) and not h.is_visible_in_tree(): hide_tip()

## o toque longo vira "consulta": tira o dedo de cima do botão sem apertar
func _cancel_press():
	var m := InputEventMouseMotion.new()
	m.position = Vector2(-9999, -9999)
	m.global_position = m.position
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	_faking = true
	get_viewport().push_input(m)
	_faking = false
