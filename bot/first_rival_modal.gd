extends CanvasLayer
## R184e · CONTA NOVA no celular/app: "SEU PRIMEIRO RIVAL" — tela de boas-vindas com arte (moldura dos cavalos),
## o retrato do BOT MADEIRA com luz girando atrás, o que se ganha ao vencer e o botão DESAFIAR.
## (Antes era uma caixinha de texto com "Todo mundo começa na Madeira".) No PC continua a pergunta simples.
signal accepted
signal skipped

const ART := preload("res://ranked/art/mob_first_rival.png")   # tools: moldura "Adversário encontrado" sem o título
const ART_SIZE := Vector2(842, 1052)
const FONT_TITLE := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_BODY := preload("res://ui_kit/fonts/Alegreya-Bold.woff")
const FONT_MED := preload("res://ui_kit/fonts/Alegreya-Medium.woff")
const GOLD := Color("f7d27a")
const CREAM := Color("f4ead2")
const MUTED := Color("c3c9bb")
const EMERALD := Color("8fe6a6")
const Ladder := preload("res://bot/bot_ladder.gd")
const Catalog := preload("res://profile/avatar_catalog.gd")

var root: Control
var buttons := {}

func _ready():
	layer = 61
	preload("res://ui_v022/esc_stack.gd").register(self)

func is_open() -> bool:
	return is_instance_valid(root)

func close():
	if is_instance_valid(root): root.queue_free()
	root = null

## bot_id = "madeira"; avatar_for: id -> Texture2D; crowns = coroas da 1ª vitória (0 = não mostra)
func open(bot_id: String, avatar_for: Callable, crowns := 0):
	close()
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(540, 1200)
	var bot: Dictionary = Ladder.bot(bot_id)
	var reward: Dictionary = Ladder.reward(bot_id)
	root = Control.new()
	root.name = "FirstRival"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	# moldura: a maior que couber deixando espaço para os 2 botões embaixo
	var btn_h := clampf(vp.y * 0.075, 52.0, 96.0)
	var avail_h := vp.y - btn_h * 2.0 - 60.0
	var w := minf(vp.x - 16.0, avail_h * ART_SIZE.x / ART_SIZE.y)
	var k := w / ART_SIZE.x
	var h := ART_SIZE.y * k
	var top := maxf(10.0, (vp.y - (h + btn_h * 2.0 + 34.0)) * 0.5)
	var frame := Control.new()
	frame.name = "Frame"
	frame.position = Vector2((vp.x - w) * 0.5, top)
	frame.size = Vector2(w, h)
	frame.pivot_offset = frame.size * 0.5
	root.add_child(frame)
	var art := TextureRect.new()
	art.texture = ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)
	var A := func(x: float, y: float) -> Vector2: return Vector2(x, y) * k
	# luz girando atrás do retrato + faíscas pela moldura
	var fx = preload("res://ui_kit/reward_fx.gd").new()
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.center = A.call(421, 622)
	fx.radius = 300.0 * k
	fx.sparkle_area = Rect2(A.call(110, 280), A.call(620, 640))
	frame.add_child(fx)
	_text(frame, "SEU PRIMEIRO", Rect2(A.call(150, 352), A.call(542, 70)), int(64 * k), GOLD, FONT_TITLE, 5)
	_text(frame, "RIVAL", Rect2(A.call(150, 418), A.call(542, 78)), int(78 * k), GOLD, FONT_TITLE, 6)
	# retrato redondo do bot (o avatar que ele dá) dentro do círculo da arte
	var aid := String(reward.get("id", ""))
	var tex: Texture2D = avatar_for.call(aid) if avatar_for.is_valid() and not aid.is_empty() else null
	if tex != null:
		var por := TextureRect.new()
		por.name = "Portrait"
		por.texture = tex
		por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		por.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		por.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var d := 166.0 * k
		por.position = A.call(421, 622) - Vector2(d, d) * 0.5
		por.size = Vector2(d, d)
		por.material = _circle_mask()
		por.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(por)
	_text(frame, String(bot.get("name", "BOT")), Rect2(A.call(110, 706), A.call(622, 52)), int(50 * k), CREAM, FONT_TITLE, 4)
	_text(frame, String(bot.get("title", "")), Rect2(A.call(110, 752), A.call(622, 34)), int(30 * k), MUTED, FONT_MED, 2)
	# prêmio
	var prize := "Vença e ganhe o avatar " + Catalog.display_name(aid) if not aid.is_empty() else "Vença seu primeiro desafio!"
	_text(frame, prize, Rect2(A.call(120, 818), A.call(602, 46)), int(34 * k), GOLD, FONT_BODY, 3)
	if crowns > 0:
		_text(frame, "+ %d COROAS" % crowns, Rect2(A.call(120, 862), A.call(602, 46)), int(36 * k), Color("ffe08a"), FONT_TITLE, 3)
	# botões
	buttons.clear()
	var by := top + h + 12.0
	var bw := minf(vp.x - 32.0, w * 0.94)
	buttons["accept"] = _button(Rect2((vp.x - bw) * 0.5, by, bw, btn_h), "DESAFIAR O " + String(bot.get("name", "BOT")), true, func():
		close()
		accepted.emit())
	buttons["skip"] = _button(Rect2((vp.x - bw * 0.7) * 0.5, by + btn_h + 10.0, bw * 0.7, btn_h * 0.78), "AGORA NÃO", false, func():
		close()
		skipped.emit())
	# entrada: moldura cresce com um pulinho
	frame.scale = Vector2(0.86, 0.86)
	frame.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(frame, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(frame, "modulate:a", 1.0, 0.25)

## ESC (esc_stack): fecha como "agora não"
func esc_close() -> bool:
	if not is_open(): return false
	close()
	skipped.emit()
	return true

func _text(parent: Control, s: String, r: Rect2, fs: int, col: Color, font: Font, outline: int) -> Label:
	var l := Label.new()
	l.text = s
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", maxi(12, fs))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("1a0f04"))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = false
	parent.add_child(l)
	return l

func _button(r: Rect2, caption: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = caption
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", FONT_TITLE)
	b.add_theme_font_size_override("font_size", int(r.size.y * (0.34 if primary else 0.36)))
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		if primary:
			s.bg_color = Color("e9b23a") if st != "pressed" else Color("c98f22")
			s.border_color = Color("fff0b8")
			s.shadow_color = Color(1.0, 0.75, 0.25, 0.45)
			s.shadow_size = 12
		else:
			s.bg_color = Color("13264d") if st != "pressed" else Color("0c1a38")
			s.border_color = Color("c9a24c")
		s.set_border_width_all(3)
		s.set_corner_radius_all(int(r.size.y * 0.2))
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", Color("2a1702") if primary else CREAM)
	b.add_theme_color_override("font_hover_color", Color("2a1702") if primary else Color("fff4c8"))
	b.add_theme_color_override("font_pressed_color", Color("2a1702") if primary else CREAM)
	b.pressed.connect(cb)
	root.add_child(b)
	if primary:
		# brilho pulsando no botão principal
		b.pivot_offset = r.size * 0.5
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "scale", Vector2(1.03, 1.03), 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
	return b

static var _mask_mat: ShaderMaterial = null
static func _circle_mask() -> ShaderMaterial:
	if _mask_mat == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nvoid fragment(){ vec2 d = UV - vec2(0.5); float r = length(d); COLOR = texture(TEXTURE, UV); COLOR.a *= 1.0 - smoothstep(0.47, 0.5, r); }"
		_mask_mat = ShaderMaterial.new()
		_mask_mat.shader = sh
	return _mask_mat
