extends CanvasLayer
## R88 · Controle deslizante de volume dos modos XEQUE e MARCHA REAL (MÚSICA ou EFEITOS).
## Tocar no ícone abre este painel; arrastar muda o volume na hora (o valor fica salvo, como na
## Configuração); lá embaixo = mudo. Tocar fora do painel (ou no ícone de novo) fecha.
## R96 · kind "both" (botão de som da Home): MÚSICA e EFEITOS lado a lado no mesmo painel.
const GOLD := Color("f4ce7f")
const CREAM := Color("efe3c4")
const PANEL := Vector2(116, 330)
const PANEL_BOTH := Vector2(228, 330)

var hub
var kind := "music"           # "music" | "fx" | "both"
var drag_kind := ""           # trilho sendo arrastado
var box := Rect2()            # painel na tela
var track := Rect2()          # trilho do controle na tela (painel de uma barra)
var dragging := false
var opened_ms := 0			# R91 · hora em que abriu (ignora o toque repetido do celular logo depois)
var canvas: Control

func _init():
	layer = 120
	visible = false
	preload("res://ui_v022/esc_stack.gd").register(self)   # R129 · ESC fecha
	canvas = Control.new()
	canvas.name = "VolumePopover"
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_draw_panel)
	canvas.gui_input.connect(_input_event)
	add_child(canvas)

## anchor = retângulo do ícone tocado, em pixels de tela
func open(p_hub, p_kind: String, anchor: Rect2):
	hub = p_hub
	kind = p_kind
	var vs: Vector2 = canvas.get_viewport_rect().size
	var ps := PANEL_BOTH if kind == "both" else PANEL
	var x := clampf(anchor.get_center().x - ps.x / 2.0, 8.0, vs.x - ps.x - 8.0)
	var y := anchor.end.y + 10.0
	if y + ps.y > vs.y - 8.0: y = maxf(8.0, anchor.position.y - ps.y - 10.0)
	box = Rect2(x, y, ps.x, ps.y)
	opened_ms = Time.get_ticks_msec()
	track = _track_for(kind if kind != "both" else "music")
	visible = true
	canvas.modulate.a = 0.0
	create_tween().tween_property(canvas, "modulate:a", 1.0, 0.14)
	canvas.queue_redraw()

func close():
	dragging = false
	visible = false

func _kinds() -> Array:
	return ["music", "fx"] if kind == "both" else [kind]

## trilho de cada barra (no "both", MÚSICA à esquerda e EFEITOS à direita)
func _track_for(k: String) -> Rect2:
	var cx := box.position.x + box.size.x / 2.0
	if kind == "both": cx = box.position.x + box.size.x * (0.27 if k == "music" else 0.73)
	return Rect2(cx - 7.0, box.position.y + 66.0, 14.0, box.size.y - 120.0)

func value(k := "") -> float:
	if hub == null: return 0.0
	if k == "": k = kind
	if k == "music":
		return 0.0 if bool(hub.get("music_muted")) else float(hub.get("music_volume"))
	return 0.0 if bool(hub.get("effects_muted")) else float(hub.get("volume"))

func _set_from(y: float, k := ""):
	if k == "": k = kind if kind != "both" else (drag_kind if drag_kind != "" else "music")
	var tr := _track_for(k)
	var v := clampf((tr.end.y - y) / tr.size.y, 0.0, 1.0)
	if v < 0.03: v = 0.0
	if hub != null and hub.has_method("set_mode_volume"): hub.set_mode_volume(k, v)
	canvas.queue_redraw()

func _input_event(e: InputEvent):
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	var moved := false
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position; pressed = e.pressed; released = not e.pressed
	elif e is InputEventScreenTouch:
		pos = e.position; pressed = e.pressed; released = not e.pressed
	elif e is InputEventMouseMotion or e is InputEventScreenDrag:
		pos = e.position; moved = true
	else:
		return
	canvas.accept_event()
	if pressed:
		if not box.has_point(pos):
			if Time.get_ticks_msec() - opened_ms < 400: return   # R91 · eco do toque que abriu (toque + clique emulado)
			close()
			return
		for k in _kinds():
			if _track_for(k).grow_individual(30, 14, 30, 14).has_point(pos):
				dragging = true
				drag_kind = k
				_set_from(pos.y, k)
				break
	elif moved and dragging:
		_set_from(pos.y, drag_kind)
	elif released:
		dragging = false

func _draw_panel():
	if not visible: return
	var c := canvas
	c.draw_rect(box.grow(5), Color(0, 0, 0, 0.35))
	c.draw_rect(box, Color(0.071, 0.085, 0.113, 0.96))
	c.draw_rect(box, GOLD, false, 2.0)
	c.draw_rect(box.grow(-5), Color(GOLD.r, GOLD.g, GOLD.b, 0.3), false, 1.0)
	var f: Font = ThemeDB.fallback_font
	for k in _kinds():
		var tr := _track_for(k)
		var col_w := box.size.x if kind != "both" else box.size.x / 2.0
		var col_x := box.position.x if (kind != "both" or k == "music") else box.position.x + col_w
		var v := value(k)
		c.draw_string(f, Vector2(col_x, box.position.y + 26), "MÚSICA" if k == "music" else "EFEITOS", HORIZONTAL_ALIGNMENT_CENTER, col_w, 16, GOLD)
		var pct := "MUDO" if v <= 0.0 else "%d%%" % roundi(v * 100.0)
		c.draw_string(f, Vector2(col_x, box.position.y + 50), pct, HORIZONTAL_ALIGNMENT_CENTER, col_w, 18, CREAM if v > 0.0 else Color("e0574a"))
		# trilho: vazio escuro, cheio dourado de baixo para cima
		c.draw_rect(tr.grow(2), Color("120a06"))
		c.draw_rect(tr, Color("313744"))
		var fill_h := tr.size.y * v
		c.draw_rect(Rect2(tr.position.x, tr.end.y - fill_h, tr.size.x, fill_h), GOLD)
		var ky := tr.end.y - fill_h
		var knob := Rect2(tr.get_center().x - 22.0, ky - 9.0, 44.0, 18.0)
		c.draw_rect(knob.grow(2), Color("120a06"))
		c.draw_rect(knob, Color("ffe6a0") if dragging and drag_kind == k else GOLD)
		c.draw_line(Vector2(knob.position.x + 10, ky), Vector2(knob.end.x - 10, ky), Color("6b4b16"), 2.0)
	if kind == "both":
		c.draw_line(Vector2(box.get_center().x, box.position.y + 14), Vector2(box.get_center().x, box.end.y - 40), Color(GOLD.r, GOLD.g, GOLD.b, 0.25), 1.0)
	# rodapé: "arraste para baixo = mudo"
	c.draw_string(f, Vector2(box.position.x, box.end.y - 16), "0 = mudo", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 13, Color(CREAM.r, CREAM.g, CREAM.b, 0.7))
