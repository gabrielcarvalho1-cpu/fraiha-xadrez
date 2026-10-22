extends "res://ui_v022/home_modal.gd"
## R139 · TABULEIRO E PEÇAS — escolha das CORES do tabuleiro padrão (Madeira): casas e peças. A arte não muda.
## Grátis: algumas cores + Peças clássicas · Ligas: a cor de cada liga conquistada · Fundador / Club: exclusivos.
## Prévia ao vivo à esquerda (PC) ou em cima (celular); escolha salva na hora (hub.set_board_colors).
const BoardColors := preload("res://cosmetics/board_colors.gd")
const SkinRef := preload("res://ranked/board_skin.gd")
const LOCK_TEX := preload("res://ui_kit/pages/ico_cadeado.png")

var preview: Control
var preview_casas: TextureRect
var preview_pieces: Control
var casas_grid: GridContainer
var pecas_grid: GridContainer
var status: Label
var scroll: ScrollContainer
var _main: BoxContainer

func setup(p_hub):
	build(p_hub, "TABULEIRO E PEÇAS")
	name = "BoardColorsUI"
	_main = HBoxContainer.new()
	_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main.add_theme_constant_override("separation", 22)
	body.add_child(_main)
	# prévia
	preview = Control.new()
	preview.name = "BoardPreview"
	preview.clip_contents = false   # R161 · as peças altas da fileira de cima saem um pouco da casa (sem corte)
	_main.add_child(preview)
	preview_casas = TextureRect.new()
	preview_casas.texture = BoardColors.casas()
	preview_casas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_casas.stretch_mode = TextureRect.STRETCH_SCALE
	preview_casas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	preview_casas.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.add_child(preview_casas)
	preview_pieces = Control.new()
	preview_pieces.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_pieces.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	preview_pieces.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_pieces.draw.connect(_draw_preview_pieces)
	preview.add_child(preview_pieces)
	var frame_line := Panel.new()
	frame_line.name = "FrameLine"
	var st := StyleBoxFlat.new()
	st.draw_center = false
	st.border_color = Color("c99a45")
	st.set_border_width_all(3)
	frame_line.add_theme_stylebox_override("panel", st)
	frame_line.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(frame_line)
	preview.move_child(preview_pieces, -1)   # R161 · peças por cima do fio dourado (a ponta do rei e da dama não somem)
	# listas
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_main.add_child(scroll)
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)   # R142 · celular: arrastar em cima das amostras rola a lista
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)
	col.add_child(_heading("CASAS"))
	casas_grid = GridContainer.new()
	casas_grid.add_theme_constant_override("h_separation", 10)
	casas_grid.add_theme_constant_override("v_separation", 10)
	col.add_child(casas_grid)
	col.add_child(_heading("PEÇAS"))
	pecas_grid = GridContainer.new()
	pecas_grid.add_theme_constant_override("h_separation", 10)
	pecas_grid.add_theme_constant_override("v_separation", 10)
	col.add_child(pecas_grid)
	status = label("", 15, DIM, true)
	status.custom_minimum_size.x = 10.0
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(status)
	if hub != null and hub.has_signal("board_colors_changed"): hub.board_colors_changed.connect(refresh)

func _heading(t: String) -> Control:
	var l := label(t, 20, GOLD)
	l.name = "Heading_" + t
	return l

func open():
	refresh()
	super.open()

func refresh():
	if hub == null: return
	_rebuild(casas_grid, BoardColors.BOARDS, true)
	_rebuild(pecas_grid, BoardColors.PIECES, false)
	preview_casas.material = BoardColors.board_material(hub.effective_board_color())
	preview_pieces.queue_redraw()
	if status.text.is_empty() or not status.has_meta("lock"):
		status.text = "Vale para todas as partidas. Só a cor muda." if narrow() else "A escolha vale para todas as partidas. Só a cor muda: o tabuleiro e as peças continuam os da Madeira."
	status.remove_meta("lock")

func _rebuild(grid: GridContainer, list: Array, is_board: bool):
	for c in grid.get_children():
		grid.remove_child(c)   # sai já: as novas ficam com o mesmo nome (Casas_<id> / Pecas_<id>)
		c.queue_free()
	var cur: String = hub.board_color_pref if is_board else hub.piece_color_pref
	for e in list:
		var id: String = e[0]
		var reason := BoardColors.lock_reason(String(e[4]), hub)
		grid.add_child(_swatch(id, String(e[1]), is_board, id == cur and reason.is_empty(), reason))

func _swatch(id: String, nome: String, is_board: bool, selected: bool, reason: String) -> Button:
	var b := Button.new()
	b.name = ("Casas_" if is_board else "Pecas_") + id
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = reason if not reason.is_empty() else nome
	for pair in [["normal", 0.0], ["hover", 0.08], ["pressed", -0.04]]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("15213a").lightened(maxf(0.0, pair[1])).darkened(maxf(0.0, -pair[1]))
		s.border_color = Color("ffe08a") if selected else Color("6d5a32")
		s.set_border_width_all(4 if selected else 2)
		s.set_corner_radius_all(4)
		b.add_theme_stylebox_override(pair[0], s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var w := _cell_w()
	b.custom_minimum_size = Vector2(w, w * 0.62 + ts(14) * (2.7 if narrow() else 1.6) + 10)
	var pic: Control
	if is_board:
		var t := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = BoardColors.casas()
		at.region = Rect2(160, 160, 160, 80)   # duas casas lado a lado (clara e escura)
		t.texture = at
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		t.material = BoardColors.board_material(id)
		pic = t
	else:
		var d := Control.new()
		d.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		d.draw.connect(func(): _draw_pair(d, id))
		pic = d
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.position = Vector2(6, 6)
	pic.size = Vector2(w - 12, w * 0.62 - 6)
	if not reason.is_empty(): pic.modulate = Color(0.55, 0.55, 0.55)
	b.add_child(pic)
	var l := label(nome, 14, Color("ffe7a6") if selected else (CREAM if reason.is_empty() else DIM), true)
	var lf: Font = l.get_theme_font("font")
	var lfs := ts(14)
	# nome inteiro: diminui a letra até caber; no celular pode usar duas linhas (quebra entre palavras)
	var max_lines := 2 if narrow() else 1
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if max_lines > 1 else TextServer.AUTOWRAP_OFF
	l.clip_text = false
	while lfs > 9 and _lines_needed(lf, nome, lfs, w - 10.0) > max_lines: lfs -= 1
	l.add_theme_font_size_override("font_size", lfs)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(4, w * 0.62 + 2)
	l.size = Vector2(w - 8, ts(14) * (2.6 if narrow() else 1.5))
	b.add_child(l)
	if not reason.is_empty():
		var lk := TextureRect.new()
		lk.texture = LOCK_TEX
		lk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lk.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ls := w * 0.26
		lk.size = Vector2(ls, ls)
		lk.position = Vector2((w - ls) / 2.0, (w * 0.62 - ls) / 2.0 + 3)
		b.add_child(lk)
	b.pressed.connect(func(): if not selected: _pick(id, is_board, reason, nome))   # R176 · a cor em uso não pergunta
	return b

## quantas linhas o nome ocupa nessa largura (quebrando só entre palavras; palavra maior que a linha = não cabe)
static func _lines_needed(f: Font, t: String, fs: int, width: float) -> int:
	var n := 1
	var cur := 0.0
	var space := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	for word in t.split(" "):
		var ww := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if ww > width: return 99
		if cur == 0.0: cur = ww
		elif cur + space + ww <= width: cur += space + ww
		else:
			n += 1
			cur = ww
	return n

func _pick(id: String, is_board: bool, reason: String, nome: String):
	if not reason.is_empty():
		status.text = "%s: %s." % [nome, reason]
		status.set_meta("lock", true)
		status.add_theme_color_override("font_color", Color("f2b27a"))
		return
	status.remove_theme_color_override("font_color")
	status.add_theme_color_override("font_color", DIM)
	status.text = ""
	# R176 · pergunta antes de trocar (a cor já em uso não pergunta)
	preload("res://ui_kit/confirm_box.gd").ask_change(self, "as cores do tabuleiro" if is_board else "as cores das peças", nome, func():
		if is_board: hub.set_board_colors(id, "")
		else: hub.set_board_colors("", id))

var _list_w := 600.0   # largura da coluna das listas (calculada no _layout pelo tamanho da janela)
func _cell_w() -> float:
	return clampf((_list_w - 18.0 - 10.0 * float(_cols() - 1)) / float(_cols()), 70.0, 190.0)

func _cols() -> int:
	return 3 if narrow() else 5

## peças da prévia: posição inicial (só as duas fileiras de cada lado)
func _pieces_dict() -> Dictionary:
	var id: String = hub.effective_piece_color()
	if id == BoardColors.CLASSICAS:
		var out := {}
		var tex := _classic()
		for code in tex: out[code] = [tex[code], Rect2()]
		return out
	return BoardColors.pieces(id, SkinRef.PECAS)

func _classic() -> Dictionary:
	var st = hub.get_parent() if hub != null else null
	var tm = st.get("theme_manager") if st != null else null
	return tm.classic_pieces if tm != null else {}

func _draw_preview_pieces():
	var d := _pieces_dict()
	var cs := preview_pieces.size.x / 8.0
	var back := ["R", "N", "B", "Q", "K", "B", "N", "R"]
	for x in 8:
		for row in [[0, "b" + back[x]], [1, "bP"], [6, "wP"], [7, "w" + back[x]]]:
			_draw_piece(preview_pieces, d, row[1], Rect2(Vector2(x, row[0]) * cs, Vector2(cs, cs)))

func _draw_pair(c: Control, id: String):
	var d := BoardColors.pieces(id, SkinRef.PECAS) if id != BoardColors.CLASSICAS else {}
	if id == BoardColors.CLASSICAS:
		var tex := _classic()
		for code in tex: d[code] = [tex[code], Rect2()]
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("0f1729"))
	var h := c.size.y
	# dois reis lado a lado, a mesma escala da partida (célula = 80% da altura, base perto do pé da amostra)
	var cell := h * 0.95
	# base dos reis perto do pé da amostra (centrados na altura)
	var top := h * 0.97 - cell * 0.5 - cell * 28.0 / 75.0
	_draw_piece(c, d, "wK", Rect2(Vector2(c.size.x / 2.0 - cell * 0.92, top), Vector2(cell, cell)))
	_draw_piece(c, d, "bK", Rect2(Vector2(c.size.x / 2.0 - cell * 0.08, top), Vector2(cell, cell)))

func _draw_piece(c: CanvasItem, d: Dictionary, code: String, cell: Rect2):
	preload("res://cosmetics/board_colors_preview.gd").draw_piece(c, d, code, cell)   # R139 · mesma conta da partida

func _layout():
	super._layout()
	if _main == null: return
	var vertical := portrait()
	if (_main is HBoxContainer) == vertical:
		# troca a direção mantendo os filhos
		var nb: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
		nb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		nb.add_theme_constant_override("separation", 12 if vertical else 22)
		for ch in _main.get_children():
			_main.remove_child(ch)
			nb.add_child(ch)
		body.remove_child(_main)
		body.add_child(nb)
		body.move_child(nb, 0)
		_main.queue_free()
		_main = nb
	var side: float
	# R161 · celular em pé: prévia maior (antes ~1/3 da altura e 72% da largura) e as peças da fileira de cima
	# não são mais cortadas: a prévia tem uma folga em cima (as peças altas passam da casa, como na partida)
	if vertical: side = minf(_body_rect.size.x * 0.92, _body_rect.size.y * 0.44)
	else: side = minf(_body_rect.size.y - ts(16) * 2.4, _body_rect.size.x * 0.42)
	var top := side / 8.0 * 0.32
	side -= top   # a folga de cima cabe no mesmo espaço
	preview.custom_minimum_size = Vector2(side, side + top + 4.0)
	for n in [preview_casas, preview_pieces, preview.get_node_or_null("FrameLine")]:
		if n == null: continue
		n.set_anchors_preset(Control.PRESET_TOP_LEFT)
		n.position = Vector2(0, top)
		n.size = Vector2(side, side)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # sempre quadrada: casas e peças na mesma grade
	_list_w = _body_rect.size.x if vertical else _body_rect.size.x - side - 22.0
	casas_grid.columns = _cols()
	pecas_grid.columns = _cols()
	if visible: call_deferred("refresh")
