extends Button
## R178 · PASSE DA TEMPORADA na tela de início (o maior atrativo do lançamento): um cartão dourado, bem à vista,
## com nível, barra de XP e quanto falta para a temporada acabar. Tocar abre o Passe.
## Dois jeitos: "card" (PC e celular deitado, embaixo do cartão de perfil) e "strip" (celular em pé, faixa
## entre o perfil e o JOGAR RANQUEADO). O desenho é todo em _draw (coordenadas do próprio botão).
const CROWN := preload("res://economy/art/pass_crown.png")   # cópia pequena no pacote principal (a da Marcha é do conteúdo extra)
const F_TITLE := preload("res://account/fonts/Cinzel-Bold.woff")
const F_INFO := preload("res://ui_kit/fonts/Alegreya-Bold.woff")
const GOLD := Color("f3c54e")
const GOLD_D := Color("8a5a12")
const CREAM := Color("f6ecd2")

var hub
var style := "card"
var state: Dictionary = {}
var t := 0.0
var _ask_t := 0.0

func setup(p_hub, p_style := "card"):
	hub = p_hub
	style = p_style
	name = "PassHomeCard"
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Passe da Temporada · suba de nível jogando e ganhe prêmios exclusivos"
	text = ""
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]: add_theme_stylebox_override(st, empty)
	pressed.connect(_open)
	_bind()

## a conta pode ser ligada à Home depois do cartão existir (stage.bind_account): liga quando aparecer
var _bound = null
func _bind():
	var acc = _account()
	if acc == null or acc == _bound or not acc.has_signal("server_message"): return
	if _bound != null and is_instance_valid(_bound) and _bound.server_message.is_connected(_on_message): _bound.server_message.disconnect(_on_message)
	acc.server_message.connect(_on_message)
	_bound = acc

func _account():
	return hub.get("account") if hub != null else null

func _open():
	if hub != null and hub.has_method("crowns_client"): hub.crowns_client().open_pass()

func _on_message(m: Dictionary):
	var ty := String(m.get("type", ""))
	if ty == "pass_state":
		state = m
		queue_redraw()
	elif ty == "crowns_reward":
		for l in m.get("lines", []):
			if String(l).begins_with("Passe"): _ask()

func _ask():
	var acc = _account()
	if acc != null and acc.has_method("send_server") and bool(acc.get("server_ready")): acc.send_server({"type": "pass_get"})

func _process(d: float):
	if not is_visible_in_tree(): return
	_bind()
	t += d
	# pede o estado quando a conexão fica pronta e de novo a cada 60 s (XP sobe com as partidas)
	_ask_t -= d
	if _ask_t <= 0.0:
		var acc = _account()
		if acc != null and bool(acc.get("server_ready")):
			_ask()
			_ask_t = 60.0 if not state.is_empty() else 4.0
		else:
			_ask_t = 2.0
	queue_redraw()

func _level() -> int: return int(state.get("level", 0))
func _frac() -> float:
	var per := maxf(1.0, float(state.get("xp_per_level", 150)))
	var lv := _level()
	if lv >= int(state.get("levels", 30)): return 1.0
	return clampf((float(state.get("xp", 0)) - lv * per) / per, 0.0, 1.0)
func _days() -> String:
	if not state.has("ends_in_s"): return ""
	var s := int(state.ends_in_s)
	var dd := s / 86400
	if dd >= 1: return "faltam %d dia%s" % [dd, "" if dd == 1 else "s"]
	return "termina em %dh" % maxi(1, s / 3600)

## R178 · XP EM DOBRO (lançamento): selo vermelho piscando
func _boost() -> bool: return state.get("xp_boost") is Dictionary
func _xp2(at: Vector2, h: float) -> float:
	var txt := "XP 2x"
	var fs := int(h * 0.62)
	var w := F_INFO.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + h * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("c8202a").lerp(Color("ff4a3a"), 0.5 + 0.5 * sin(t * 5.0))
	sb.set_corner_radius_all(int(h * 0.25))
	sb.border_color = Color("ffd96a")
	sb.set_border_width_all(1)
	draw_style_box(sb, Rect2(at, Vector2(w, h)))
	draw_string(F_INFO, Vector2(at.x + h * 0.25, at.y + h * 0.74), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	return w

func _frame(r: Rect2, rad: float):
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0b1530")
	sb.set_corner_radius_all(int(rad))
	sb.border_color = GOLD_D
	sb.set_border_width_all(maxi(2, int(r.size.y * 0.045)))
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = int(r.size.y * 0.08)
	draw_style_box(sb, r)
	# degradê azul-noite → roxo real e o brilho dourado do contorno
	var inner := r.grow(-r.size.y * 0.06)
	var n := 18
	for i in n:
		var f := float(i) / n
		var c := Color("13224a").lerp(Color("2a1240"), f)
		draw_rect(Rect2(inner.position.x + inner.size.x * f, inner.position.y, inner.size.x / n + 1.0, inner.size.y), Color(c, 0.85))
	var pulse := 0.55 + 0.45 * sin(t * 2.4)
	var sb2 := StyleBoxFlat.new()
	sb2.draw_center = false
	sb2.set_corner_radius_all(int(rad))
	sb2.border_color = GOLD.lerp(Color("fff1b0"), pulse * 0.6)
	sb2.set_border_width_all(maxi(2, int(r.size.y * 0.035)))
	draw_style_box(sb2, r.grow(-r.size.y * 0.02))
	if is_hovered() or button_pressed:
		var sb3 := StyleBoxFlat.new()
		sb3.bg_color = Color(1, 0.85, 0.4, 0.10 if not button_pressed else 0.18)
		sb3.set_corner_radius_all(int(rad))
		draw_style_box(sb3, r)
	# reflexo passando (a cada ~3,5 s)
	var ph := fmod(t, 3.5) / 1.1
	if ph < 1.0:
		var x := r.position.x - r.size.y + (r.size.x + r.size.y * 2.0) * ph
		var w := r.size.y * 0.5
		var pts := PackedVector2Array([Vector2(x, r.end.y - 3), Vector2(x + w, r.end.y - 3), Vector2(x + w + r.size.y * 0.5, r.position.y + 3), Vector2(x + r.size.y * 0.5, r.position.y + 3)])
		var clip := PackedVector2Array()
		for p in pts: clip.append(Vector2(clampf(p.x, r.position.x + rad * 0.5, r.end.x - rad * 0.5), p.y))
		draw_colored_polygon(clip, Color(1, 0.95, 0.75, 0.12))

func _bar(r: Rect2, f: float):
	draw_rect(r.grow(1.5), Color("05080f"))
	draw_rect(r, Color("1b2440"))
	if f > 0.0:
		var fr := Rect2(r.position, Vector2(r.size.x * f, r.size.y))
		draw_rect(fr, Color("e7a52a"))
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.45)), Color("ffd96a"))
	draw_rect(r, GOLD_D, false, 1.0)

func _crown(c: Vector2, h: float):
	var g := 0.5 + 0.5 * sin(t * 2.0)
	for i in 4: draw_circle(c, h * (0.55 + 0.12 * i), Color(1.0, 0.78, 0.25, 0.07 + 0.03 * g))
	var ts := CROWN.get_size()
	var w := h * ts.x / ts.y
	draw_texture_rect(CROWN, Rect2(c - Vector2(w, h) / 2.0, Vector2(w, h)), false)

func _str(f: Font, s: String, pos: Vector2, fs: int, col: Color, max_w := -1.0, outline := 0) -> float:
	var size := fs
	if max_w > 0.0:
		while size > 8 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w: size -= 1
	if outline > 0: draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color("120a04"))
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## R178e · a ARTE do dono (tools/pass_button_r178e.py): placa 2036x502 sem a frase, sem o roxo da barra e sem o
## número; o jogo escreve a frase, estica o roxo até o progresso e escreve o nível — nos mesmos lugares da arte.
const PLATE := preload("res://economy/art/pass_button_plate.png")
const FILL := preload("res://economy/art/pass_button_fill.png")
const ART := Vector2(2036, 502)
const F_SERIF := preload("res://account/fonts/Cinzel-Bold.woff")
## R196 · celular: NEON ROXO acendendo e apagando em volta da placa (o mesmo roxo da vez do jogador na Marcha).
## O brilho é a silhueta da placa desfocada (tools/art/home_buttons_r196.py): 1/4 do tamanho + 40 px de margem.
const GLOW_PATH := "res://economy/art/pass_button_glow.png"
const GLOW_Q := 4.0
const GLOW_PAD := 40.0
var neon := false
var _glow: Texture2D
func _draw():
	_draw_art()

func _draw_art():
	var k: float = minf(size.x / ART.x, size.y / ART.y)
	var o: Vector2 = (size - ART * k) / 2.0
	var at := func(p: Vector2) -> Vector2: return o + p * k
	var glow := 0.5 + 0.5 * sin(t * 2.4)
	var mod := Color(1, 1, 1) if not (is_hovered() or button_pressed) else Color(1.12, 1.1, 1.04)
	if neon:
		if _glow == null:
			_glow = load(GLOW_PATH)
			texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var pz := 0.5 + 0.5 * sin(t * 2.2)   # ~2,9 s por ciclo, suave
		var gs: Vector2 = _glow.get_size() * GLOW_Q * k
		draw_texture_rect(_glow, Rect2(o - Vector2.ONE * GLOW_PAD * GLOW_Q * k, gs), false, Color(1, 1, 1, 0.18 + 0.72 * pz))
	draw_texture_rect(PLATE, Rect2(o, ART * k), false, mod)
	var has := not state.is_empty() and bool(state.get("available", true))
	# frase de baixo (creme, como na arte)
	var sub := (String(state.get("name", "")) + (" • " + _days() if _days() != "" else "")) if has else "Suba de nível jogando e ganhe prêmios"
	var fs := int(68.0 * k)
	while fs > 6 and F_INFO.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 1120.0 * k: fs -= 1
	draw_string(F_INFO, at.call(Vector2(460, 295)) + Vector2(0, 1.5 * k * 3), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.45))
	draw_string(F_INFO, at.call(Vector2(460, 295)), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(246, 236, 207))
	# barra roxa até o progresso (corpo esticado + a ponta da arte)
	var f := _frac() if has else 0.0
	var full := 1184.0
	var len := full * f
	if len > 1.0:
		var tip := 32.0
		var body := maxf(0.0, len - tip)
		var bpos: Vector2 = at.call(Vector2(453, 335))
		var fsz := FILL.get_size()
		if body > 0.0:
			draw_texture_rect_region(FILL, Rect2(bpos, Vector2(body, fsz.y) * k), Rect2(0, 0, fsz.x - tip, fsz.y))
		var tw := minf(tip, len)
		draw_texture_rect_region(FILL, Rect2(bpos + Vector2(body * k, 0), Vector2(tw, fsz.y) * k), Rect2(fsz.x - tip, 0, tw, fsz.y))
		# brilho passando pela barra
		var ph := fmod(t, 2.6) / 2.6
		var gx: float = bpos.x + (len * k) * ph
		draw_rect(Rect2(gx - 10.0 * k, bpos.y + 6.0 * k, 20.0 * k, (fsz.y - 12.0) * k), Color(1, 0.85, 1, 0.18))
	# número do nível no escudo (dourado com contorno escuro)
	var nt := str(_level())
	var ns := int(137.0 * k)
	while ns > 6 and F_SERIF.get_string_size(nt, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x > 120.0 * k: ns -= 1
	var nw := F_SERIF.get_string_size(nt, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x
	var np: Vector2 = at.call(Vector2(1830.5, 353)) - Vector2(nw / 2.0, 0)
	draw_string_outline(F_SERIF, np, nt, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, maxi(2, int(10.0 * k)), Color("2a1204"))
	draw_string(F_SERIF, np, nt, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, Color8(251, 212, 52).lerp(Color("fff1b0"), glow * 0.25))
	if _boost():   # selo XP 2x por cima, no canto do escudo
		var bh := 70.0 * k
		var bw := F_INFO.get_string_size("XP 2x", HORIZONTAL_ALIGNMENT_LEFT, -1, int(bh * 0.62)).x + bh * 0.5
		_xp2(at.call(Vector2(1830.5, 0)) - Vector2(bw / 2.0, bh * 0.15), bh)

func _draw_old():
	var r := Rect2(Vector2.ZERO, size)
	var h := size.y
	_frame(r, h * (0.22 if style == "card" else 0.3))
	var lv := _level()
	var has := not state.is_empty() and bool(state.get("available", true))
	if style == "card":
		var ch := h * 0.72
		_crown(Vector2(h * 0.58, h * 0.5), ch)
		var x0 := h * 1.12
		var right_w := h * 0.95
		var tw := size.x - x0 - right_w - h * 0.15
		var wide := size.x > h * 5.5   # R178d · celular em pé: cartão bem largo, letras maiores
		_str(F_TITLE, "PASSE DA TEMPORADA", Vector2(x0, h * (0.38 if wide else 0.36)), int(h * (0.30 if wide else 0.24)), GOLD, tw, 2)
		var sub := (String(state.get("name", "")) + ("  ·  " + _days() if _days() != "" else "")) if has else "Suba de nível jogando e ganhe prêmios"
		_str(F_INFO, sub, Vector2(x0, h * 0.61), int(h * (0.2 if wide else 0.17)), CREAM, tw, 1)
		_bar(Rect2(x0, h * 0.70, tw, h * 0.11), _frac() if has else 0.0)
		# selo do nível
		var c := Vector2(size.x - right_w / 2.0 - h * 0.08, h * 0.5)
		var rr := h * 0.36
		draw_circle(c, rr + 3.0, Color("120a04"))
		draw_circle(c, rr, GOLD_D)
		draw_circle(c, rr * 0.86, Color("1a1030"))
		var lt := "NÍVEL"
		var f1 := F_INFO
		var s1 := int(h * 0.13)
		draw_string(f1, Vector2(c.x - f1.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, s1).x / 2.0, c.y - rr * 0.22), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, s1, CREAM)
		var nt := str(lv)
		var s2 := int(h * 0.32)
		draw_string_outline(F_TITLE, Vector2(c.x - F_TITLE.get_string_size(nt, HORIZONTAL_ALIGNMENT_LEFT, -1, s2).x / 2.0, c.y + rr * 0.62), nt, HORIZONTAL_ALIGNMENT_LEFT, -1, s2, 3, Color("120a04"))
		draw_string(F_TITLE, Vector2(c.x - F_TITLE.get_string_size(nt, HORIZONTAL_ALIGNMENT_LEFT, -1, s2).x / 2.0, c.y + rr * 0.62), nt, HORIZONTAL_ALIGNMENT_LEFT, -1, s2, GOLD)
		if _boost():   # selo XP 2x por cima da borda, acima do nível
			var bh := h * 0.26
			var bw := F_INFO.get_string_size("XP 2x", HORIZONTAL_ALIGNMENT_LEFT, -1, int(bh * 0.62)).x + bh * 0.5
			_xp2(Vector2(c.x - bw / 2.0, -bh * 0.45), bh)
	else:
		# faixa fina do celular em pé: coroa · PASSE DA TEMPORADA · NÍV X · barra · ›
		_crown(Vector2(h * 0.62, h * 0.5), h * 0.86)
		var x := h * 1.2
		var tw2 := _str(F_TITLE, "PASSE DA TEMPORADA", Vector2(x, h * 0.68), int(h * 0.42), GOLD, size.x * 0.5, 2)
		x += tw2 + h * 0.3
		var chip := "NÍV %d" % lv
		var cs := int(h * 0.34)
		var cw := F_INFO.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x + h * 0.36
		var cr := Rect2(x, h * 0.17, cw, h * 0.66)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("e7a52a")
		sb.set_corner_radius_all(int(h * 0.14))
		draw_style_box(sb, cr)
		draw_string(F_INFO, Vector2(cr.position.x + h * 0.18, h * 0.63), chip, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, Color("2a1604"))
		x = cr.end.x + h * 0.2
		if _boost():
			x += _xp2(Vector2(x, h * 0.17), h * 0.66) + h * 0.2
		var bw := size.x - x - h * 0.75
		if bw > h: _bar(Rect2(x, h * 0.42, bw, h * 0.18), _frac() if has else 0.0)
		var ar := "›"
		draw_string(F_TITLE, Vector2(size.x - h * 0.48, h * 0.72), ar, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.55), GOLD)
