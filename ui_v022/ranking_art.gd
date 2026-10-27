extends CanvasLayer
## R198 · RANKING no PC com a ARTE do dono (ui_kit/pages/ranking_r198, preparada por tools/art/ranking_r198.py):
## painel, cabeçalho e regra vêm da imagem; abas (XADREZ · XEQUE · MARCHA REAL e os 4 ritmos) são as placas da arte
## (acesa/apagada) com o texto escrito pelo jogo; as linhas do 1º, 2º e 3º são as da arte (com o louro), as outras a
## linha comum. Tudo vem do servidor (leaderboard_get), igual ao ranking antigo. Tocar fora ou ESC fecha.
## No celular em pé continua o ranking antigo (leaderboard_ui.gd).
const DIR := "res://ui_kit/pages/ranking_r198/"
const ART := Vector2(2172, 724)
const F_BOLD := preload("res://account/fonts/Cinzel-Bold.woff")
const F_SEMI := preload("res://account/fonts/Cinzel-SemiBold.woff")
const LEAGUES := ["Madeira", "Ferro", "Bronze", "Prata", "Ouro", "Platina", "Esmeralda", "Diamante", "Mestre", "Grande Mestre", "Challenger"]
const LEAGUE_TINT := [Color(1, 1, 1), Color(1, 1, 1), Color("e0995a"), Color("dfe6ee"), Color("ffd45c"), Color("9fe3e0"), Color("5fe08a"), Color("8fc4ff"), Color("d58cff"), Color("ff8a7a"), Color("ffe08a")]
## [id, texto, retângulo da peça na arte (x0, y0, x1, y1), centro do texto]: a peça é a própria aba da arte, no
## mesmo lugar (tab_<id>_on/off.png, tools/art/ranking_r198.py); o cavalo, as espadas e a coroa vêm nela.
const MODES := [["xadrez", "XADREZ", Rect2(150, 14, 640, 148), 525.0],
	["xeque", "XEQUE", Rect2(765, 14, 635, 148), 1137.0],
	["marcha", "MARCHA REAL", Rect2(1370, 14, 660, 148), 1775.0]]
## ritmos: [board, texto, peça, ícone, retângulo do ícone, centro do texto]
const CHESS := [["ranked_3min", "RELÂMPAGO", Rect2(84, 160, 512, 102), "relampago", Rect2(195, 180, 63, 68), 395.0],
	["ranked_5min", "RÁPIDA", Rect2(590, 160, 500, 102), "rapida", Rect2(728, 178, 84, 70), 893.0],
	["ranked_10min", "NORMAL", Rect2(1082, 160, 508, 102), "normal", Rect2(1203, 178, 65, 70), 1375.0],
	["ranked_20min", "CONVENCIONAL", Rect2(1578, 160, 507, 102), "convencional", Rect2(1672, 178, 70, 70), 1872.0]]
const LIST := Rect2(88, 330, 2000, 262)
const ROW_H := 85.0
const CREAM := Color("f2e6c8")
const GOLD := Color("f2c75c")
const BROWN := Color("3a2208")

var hub
var account
var tab := "xadrez"
var chess_board := "ranked_3min"
var cache := {}
var waiting := ""
var k := 1.0
var _root: Control
var _holder: Control
var _list: VBoxContainer
var _scroll: ScrollContainer
var _me: Control
var _status: Label
var _round_mat: ShaderMaterial

static func available() -> bool:
	return ResourceLoader.exists(DIR + "painel.png")

func setup(p_hub, acc):
	hub = p_hub
	account = acc
	name = "RankingArt"
	layer = 95
	if account != null and account.has_signal("server_message"): account.server_message.connect(_on_message)
	get_viewport().size_changed.connect(func(): if visible: _rebuild())
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float d = length(UV - vec2(0.5)); COLOR = vec4(c.rgb, c.a * (1.0 - smoothstep(0.47, 0.5, d))); }"
	_round_mat = ShaderMaterial.new()
	_round_mat.shader = sh
	hide()

func board() -> String:
	return chess_board if tab == "xadrez" else tab

func show_ranking():
	show()
	_rebuild()
	_request()

func close():
	hide()
	if _root != null: _root.queue_free()
	_root = null

func _unhandled_input(e):
	if visible and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func _p(v: Vector2) -> Vector2: return v * k
func _r(r: Rect2) -> Rect2: return Rect2(r.position * k, r.size * k)

func _tex(parent: Control, file: String, r: Rect2, mod := Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(DIR + file)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.position = r.position * k
	t.size = r.size * k
	t.modulate = mod
	parent.add_child(t)
	return t

## texto centrado (cx) ou à esquerda (x) na altura y (centro), em px da arte
func _text(parent: Control, s: String, x: float, y: float, px: float, col: Color, font: Font = F_BOLD, center := true, w := 0.0, outline := 3) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", maxi(8, int(round(px * k))))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.05, 0.85) if col != BROWN else Color(1, 0.9, 0.6, 0.35))
	l.add_theme_constant_override("outline_size", maxi(1, int(round(outline * k))))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ww := (w if w > 0.0 else 900.0) * k
	l.size = Vector2(ww, px * 1.6 * k)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(x * k - ww / 2.0, (y - px * 0.8) * k)
	else:
		l.position = Vector2(x * k, (y - px * 0.8) * k)
		if w > 0.0:
			l.clip_text = true
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(l)
	return l

func _hot(parent: Control, r: Rect2, cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(1, 0.95, 0.75, 0.08)
	lit.set_corner_radius_all(int(10 * k))
	for s in ["normal", "focus", "disabled", "pressed"]: b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", lit)
	b.position = r.position * k
	b.size = r.size * k
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _rebuild():
	if _root != null: _root.queue_free()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	k = minf(minf((vs.x - 24.0) / ART.x, (vs.y - 24.0) / ART.y) * 0.97, 1.0)
	_root = Control.new()
	_root.name = "RankingArtRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e): if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed: close())
	_root.add_child(dim)
	_holder = Control.new()
	_holder.name = "RankingArtPanel"
	_holder.size = ART * k
	_holder.position = ((vs - _holder.size) / 2.0).round()
	_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_holder)
	_tex(_holder, "painel.png", Rect2(Vector2.ZERO, ART))
	# abas dos modos (a escolhida dourada, as outras azuis — as peças da própria arte)
	for m in MODES:
		var on: bool = m[0] == tab
		_tex(_holder, "tab_%s_%s.png" % [m[0], "on" if on else "off"], m[2])
		_text(_holder, m[1], m[3], 97.0, 52.0, BROWN if on else CREAM, F_BOLD, true, 560.0, 2 if on else 4)
		var id: String = m[0]
		_hot(_holder, m[2], func(): set_tab(id)).name = "RankTab_" + id
	# ritmos do xadrez (apagados e sem toque nos outros modos)
	for c in CHESS:
		var on2: bool = tab == "xadrez" and c[0] == chess_board
		var dimmed := Color(0.55, 0.55, 0.6) if tab != "xadrez" else Color.WHITE   # escurece (opaco: o painel de baixo não aparece)
		_tex(_holder, "tab_%s_%s.png" % [c[0], "on" if on2 else "off"], c[2], dimmed)
		_tex(_holder, "ico_%s_%s.png" % [c[3], "on" if on2 else "off"], c[4], dimmed)
		var lab: String = c[1]
		_text(_holder, lab, c[5], 213.0, 30.0 if lab.length() > 9 else 32.0, BROWN if on2 else CREAM * dimmed, F_BOLD, true, 400.0, 2 if on2 else 3)
		if tab == "xadrez":
			var cid: String = c[0]
			_hot(_holder, c[2], func(): set_chess(cid)).name = "RankChess_" + cid
	# lista
	_scroll = ScrollContainer.new()
	_scroll.name = "RankingArtScroll"
	preload("res://ui_v022/touch_scroll.gd").attach(_scroll)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.position = LIST.position * k
	_scroll.size = LIST.size * k
	_holder.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.custom_minimum_size.x = LIST.size.x * k
	_scroll.add_child(_list)
	_status = _text(_holder, "", 1088.0, 460.0, 30.0, Color("cfd8e8"), F_SEMI, true, 1600.0)
	# R199 · X de fechar (no celular deitado não sobra "fora" para tocar)
	var xs := maxf(44.0, 84.0 * k)
	var xb := preload("res://ui_kit/close_x.gd").make(close, xs)
	xb.position = Vector2(minf(_holder.position.x + ART.x * k - xs * 0.7, vs.x - xs - 4.0), maxf(4.0, _holder.position.y - xs * 0.1))
	_root.add_child(xb)
	_me = Control.new()
	_me.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_me)
	var c0 = cache.get(board())
	if c0 != null: _fill(c0.msg)
	else: _status.text = "Carregando o ranking…"

func set_tab(t: String):
	tab = t
	_rebuild()
	_request()

func set_chess(b: String):
	chess_board = b
	_rebuild()
	_request()

func _request():
	var b := board()
	var c = cache.get(b)
	if c != null and Time.get_ticks_msec() - int(c.at) < 30000:
		_fill(c.msg)
		return
	waiting = b
	var ok: bool = account != null and bool(account.get("server_ready")) and account.send_server({"type": "leaderboard_get", "board": b})
	if not ok and is_instance_valid(_status): _status.text = "Sem conexão com o servidor. Tente de novo em instantes."

func _on_message(msg: Dictionary):
	if String(msg.get("type", "")) != "leaderboard": return
	var b := String(msg.get("board", ""))
	cache[b] = {"at": Time.get_ticks_msec(), "msg": msg}
	if visible and b == board(): _fill(msg)

func _pct(r: Dictionary) -> String:
	var v := float(r.get("rate", 0.0))
	return ("%d%%" % roundi(v)) if is_equal_approx(v, roundf(v)) else ("%.1f%%" % v).replace(".", ",")

func _fill(msg: Dictionary):
	if not is_instance_valid(_list): return
	waiting = ""
	for ch in _list.get_children(): ch.queue_free()
	for ch in _me.get_children(): ch.queue_free()
	var rows: Array = msg.get("rows", []) if msg.get("rows") is Array else []
	var minm := int(msg.get("min_matches", 5))
	if not bool(msg.get("available", false)):
		_status.text = "Ranking deste modo em breve." if String(msg.get("error", "")) != "server_error" else "Erro temporário no servidor. Tente de novo."
		return
	_status.text = "" if not rows.is_empty() else "Ninguém com %d partidas ainda. Jogue e seja o primeiro!" % minm
	for r in rows: _list.add_child(_row(r))
	# SUA POSIÇÃO
	var me = msg.get("me")
	var lead := "SUA POSIÇÃO: "
	var rest := ""
	if me is Dictionary:
		if int(me.get("pos", 0)) > 0:
			rest = "%dº · %s · %dV %dD %dE" % [int(me.pos), _pct(me), int(me.wins), int(me.losses), int(me.draws)]
		else:
			var miss := int(me.get("missing", 0))
			lead = ""
			rest = ("Faltam %d partida%s para você entrar no ranking." % [miss, "" if miss == 1 else "s"]) if miss > 0 else "Você ainda não está no top."
	elif account == null or String(account.get("user_id")) == "":
		lead = ""
		rest = "Entre na sua conta para aparecer no ranking."
	if lead.is_empty() and rest.is_empty(): return
	var l1 := _text(_me, lead, 140.0, 646.0, 40.0, CREAM, F_BOLD, false, 760.0, 4)
	var w1 := F_BOLD.get_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, -1, l1.get_theme_font_size("font_size")).x / k
	_text(_me, rest, 140.0 + w1, 646.0, 40.0 if not lead.is_empty() else 30.0, GOLD, F_BOLD, false, 760.0 - w1, 4)

func _row(r: Dictionary) -> Control:
	var pos := int(r.get("pos", 0))
	var mine: bool = account != null and String(r.get("user_id", "")) == String(account.get("user_id"))
	var row := Control.new()
	row.custom_minimum_size = Vector2(LIST.size.x, ROW_H) * k
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := "row%d.png" % pos if pos >= 1 and pos <= 3 else "row.png"
	_tex(row, plate, Rect2(0, -2, 2000, 88), Color(1.1, 1.08, 1.0) if mine and pos > 3 else Color.WHITE)
	if pos > 3 or pos < 1:
		_text(row, "%dº" % pos, 79.0, 42.0, 38.0, CREAM)
	# retrato redondo + anel dourado
	var av := TextureRect.new()
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	av.material = _round_mat
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hub != null and hub.has_method("avatar_texture_for"): av.texture = hub.avatar_texture_for(r)
	av.position = Vector2(184, 9) * k
	av.size = Vector2(68, 68) * k
	row.add_child(av)
	_tex(row, "ring.png", Rect2(168, 0, 98, 86))
	_text(row, String(r.get("nickname", "Jogador")), 282.0, 42.0, 38.0, GOLD if mine else CREAM, F_BOLD, false, 820.0, 4)
	var lg = r.get("league")
	if tab == "xadrez" and lg != null:
		var li := clampi(int(lg), 0, LEAGUES.size() - 1)
		_tex(row, "liga_madeira.png" if li == 0 else "liga_ferro.png", Rect2(1130, 6, 72, 74), LEAGUE_TINT[li])
		_text(row, "%s · %d PL" % [LEAGUES[li].to_upper(), int(r.get("pl", 0))], 1212.0, 42.0, 26.0, CREAM, F_SEMI, false, 330.0, 3)
	else:
		_text(row, "—", 1290.0, 42.0, 30.0, Color("9aa6bb"))
	_text(row, str(int(r.get("wins", 0))), 1564.0, 42.0, 42.0, Color("5fd47a"))
	_text(row, str(int(r.get("losses", 0))), 1669.0, 42.0, 42.0, Color("e8475a"))
	_text(row, str(int(r.get("draws", 0))), 1772.0, 42.0, 42.0, Color("9db8e0"))
	_text(row, _pct(r), 1897.0, 42.0, 40.0, GOLD)
	return row
