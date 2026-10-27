extends Button
## R201 · balão do convite da Home (MARCHA REAL / XEQUE): placa dourada pequena com o NEON ROXO pulsando em volta
## (o mesmo roxo do botão do PASSE e da vez do jogador na Marcha). Entra crescendo, respira e some sozinho.
const F := preload("res://account/fonts/Cinzel-Bold.woff")
var text_line := "JOGUE AGORA!"
var t := 0.0

func _ready():
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = ""
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]: add_theme_stylebox_override(st, StyleBoxEmpty.new())

func appear(life: float):
	pivot_offset = size / 2.0
	scale = Vector2(0.5, 0.5)
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(life).timeout.connect(func():
		if not is_instance_valid(self): return
		var t2 := create_tween()
		t2.tween_property(self, "modulate:a", 0.0, 0.4)
		t2.tween_callback(queue_free))

func _process(d: float):
	t += d
	queue_redraw()

func _draw():
	var r := Rect2(Vector2.ZERO, size)
	var pz := 0.5 + 0.5 * sin(t * 3.0)
	# neon roxo em volta (brilho que espalha + filete claro)
	var glow := StyleBoxFlat.new()
	glow.draw_center = false
	glow.set_corner_radius_all(int(size.y * 0.5))
	glow.border_color = Color(0.86, 0.66, 1.0, 0.55 + 0.4 * pz)
	glow.set_border_width_all(3)
	glow.shadow_color = Color(0.66, 0.24, 1.0, 0.45 + 0.45 * pz)
	glow.shadow_size = int(10 + 8 * pz)
	glow.anti_aliasing = true
	draw_style_box(glow, r.grow(2.0))
	# placa dourada
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("f3c85a").lerp(Color("ffe08a"), 0.25 * pz)
	sb.border_color = Color("7a4a0c")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(int(size.y * 0.5))
	sb.anti_aliasing = true
	draw_style_box(sb, r)
	var fs := int(size.y * 0.42)
	while fs > 10 and F.get_string_size(text_line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - size.y * 0.6: fs -= 1
	var w := F.get_string_size(text_line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2((size.x - w) / 2.0, size.y / 2.0 + fs * 0.36)
	draw_string_outline(F, p, text_line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(1, 0.95, 0.75, 0.6))
	draw_string(F, p, text_line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("2a1604"))
