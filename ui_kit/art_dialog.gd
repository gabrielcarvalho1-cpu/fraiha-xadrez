extends CanvasLayer
## R198 · janela que é a ARTE do dono (placa pronta, com textos e botões desenhados na imagem): o jogo só põe
## áreas de toque invisíveis em cima dos botões da arte (mais claros ao passar o mouse/tocar).
## ESC ou tocar fora = fechar. Ex.: COMUNIDADE (Discord · Instagram · Agora não).
const Mobile := preload("res://ui_v022/mobile_layout.gd")
var _tex: Texture2D
var _art: TextureRect
var _hots: Array = []   # [Rect2 em px da arte, Callable, fecha?]

## hots: [[Rect2 (px da arte), Callable ou null (só fecha)], ...]
static func open(owner: Node, tex_path: String, hots: Array, node_name := "ArtDialog") -> CanvasLayer:
	var d = load("res://ui_kit/art_dialog.gd").new()
	d.name = node_name
	owner.get_tree().root.add_child(d)
	d._build(load(tex_path), hots)
	return d

func _build(tex: Texture2D, hots: Array) -> void:
	layer = 98
	_tex = tex
	var dim := ColorRect.new()
	dim.name = "ArtDialogDim"
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e): if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed: close())
	add_child(dim)
	_art = TextureRect.new()
	_art.name = "ArtDialogArt"
	_art.texture = tex
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_art)
	for i in hots.size():
		var h: Array = hots[i]
		var b := Button.new()
		b.name = "ArtDialogHot_%d" % i
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var lit := StyleBoxFlat.new()
		lit.bg_color = Color(1, 0.95, 0.75, 0.10)
		lit.set_corner_radius_all(10)
		for st in ["normal", "focus", "disabled"]: b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		for st in ["hover", "pressed", "hover_pressed"]: b.add_theme_stylebox_override(st, lit)
		var cb = h[1]
		b.pressed.connect(func():
			close()
			if cb is Callable and cb.is_valid(): cb.call())
		_art.add_child(b)
		_hots.append([b, h[0]])
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	if not is_instance_valid(_art): return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var ts := _tex.get_size()
	var w := minf(vs.x - 24.0, (980.0 if not Mobile.active(get_viewport()) else 1400.0) * clampf(minf(vs.x / 1920.0, vs.y / 1080.0) * 1.25, 0.6, 1.6))
	w = minf(w, (vs.y - 24.0) * ts.x / ts.y)
	var k := w / ts.x
	_art.size = ts * k
	_art.position = (vs - _art.size) / 2.0
	for h in _hots:
		var r: Rect2 = h[1]
		h[0].position = r.position * k
		h[0].size = r.size * k

func _unhandled_input(e):
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	if is_queued_for_deletion(): return
	queue_free()
