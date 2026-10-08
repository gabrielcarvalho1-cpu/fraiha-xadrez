extends Control
## R53 · Páginas do CELULAR no visual das referências aprovadas (tools/ui_ref/mobile/mob_*.jpg).
## O painel é montado com as peças recortadas da referência (ui_kit/mobile/*.png, tools/mobile_ref_pages.py),
## por cima do cenário do FRAIHA (a mesma cena da Home do celular). Coordenadas medidas na referência (900 px
## de largura) e convertidas por `s` = largura do painel / 900. O que é vivo (textos, listas, números) é do jogo;
## as ações são as mesmas do hub (nada de regra nova aqui). Painel maior que a tela: rola com o dedo.
## Monta uma vez por página e de novo só quando a largura muda (girar o celular) — nada por quadro.
const Mobile = preload("res://ui_v022/mobile_layout.gd")
const Kit = preload("res://ui_kit/kit.gd")
# cenário: o lado direito da Home (castelo, cachoeira, placas) — só cena, sem nenhuma moldura de menu atrás
# do painel; a textura já está carregada pela Home (main_hub.FOREST), nada novo é lido do disco.
const SCENE = preload("res://ui_v022/assets/home_forest_v8.png")
const SCENE_REGION := Rect2(1100, 250, 572, 691)
const GLOW = preload("res://ui_v022/home_button_glow.gdshader")
const REF_W := 900.0
const MAX_W := 460.0
const PAGES := ["mais", "about", "history", "ranking"]
const CREAM := Color("efe6cf")
const GOLD := Color("f5cf6a")
const INK := Color("2b1d0e")

var hub
var mobile
var page_id := ""
var scenery: TextureRect
var dim: ColorRect
var scroll: ScrollContainer
var body: Control
var panel: Control
var s := 1.0
var _w := -1.0
var _full := Rect2()
# painel que cresce com o conteúdo: topo fixo + linhas repetidas + fim
var _content: Control = null
var _tiles: Control = null
var _tile_tex: Texture2D = null
var _end: TextureRect = null
var _top_h := 0.0
var _end_h := 0.0
var _end_room := 0.0
var _content_pad := 0.0

func setup(owner_hub, owner_mobile):
	hub = owner_hub
	mobile = owner_mobile
	name = "MobileRefPage"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	scenery = TextureRect.new()
	scenery.name = "RefScenery"
	var t := AtlasTexture.new()
	t.atlas = SCENE
	t.region = SCENE_REGION
	scenery.texture = t
	scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scenery.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scenery)
	dim = ColorRect.new()
	dim.name = "RefDim"
	dim.color = Color(0.01, 0.02, 0.015, 0.62)   # cena escurecida (como os painéis do PC): o painel é o foco
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	scroll = ScrollContainer.new()
	scroll.name = "RefScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	body = Control.new()
	body.name = "RefBody"
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(body)

static func handles(id: String) -> bool:
	return id in PAGES

func open(id: String):
	page_id = id
	_w = -1.0
	visible = true
	if _full.size.x > 0.0: layout(_full)

func close():
	visible = false
	page_id = ""
	_clear()

## full = a tela inteira, nas coordenadas do pai (a Home do celular).
func layout(full: Rect2):
	_full = full
	position = full.position
	size = full.size
	scenery.size = full.size
	dim.size = full.size
	scroll.size = full.size
	if not visible or page_id.is_empty(): return
	var w := minf(full.size.x, MAX_W)
	if absf(w - _w) > 0.5:
		_w = w
		s = w / REF_W
		_build()
	_place()

func _clear():
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	panel = null
	_content = null
	_tiles = null
	_end = null

func _build():
	_clear()
	panel = Control.new()
	panel.name = "RefPanel_" + page_id
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.size.x = _w
	body.add_child(panel)
	match page_id:
		"mais": _build_mais()
		"about": _build_about()
		"history": _build_history()
		"ranking": _build_ranking()
	scroll.scroll_vertical = 0

## Remonta a página atual mantendo a rolagem (ex.: tocou numa liga) — uma vez por toque, não por quadro.
func refresh():
	if not visible or panel == null: return
	var sv := scroll.scroll_vertical
	_build()
	_place()
	await get_tree().process_frame
	scroll.scroll_vertical = sv

## Centraliza o painel; se couber na tela fica no meio, senão começa no topo (abaixo do entalhe) e rola.
func _place():
	if panel == null: return
	var area := Mobile.safe_rect(get_viewport())
	var top_in := maxf(0.0, area.position.y - _full.position.y - 8.0)
	var bottom_in := maxf(0.0, _full.end.y - area.end.y - 8.0)
	var room := _full.size.y - top_in - bottom_in
	var ph := panel.size.y
	var y := top_in + maxf(0.0, (room - ph) / 2.0)
	panel.position = Vector2(roundf((_full.size.x - _w) / 2.0), roundf(y))
	body.custom_minimum_size = Vector2(_full.size.x, y + ph + bottom_in)

# ------------------------------------------------------------------ peças
func R(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(x * s, y * s, w * s, h * s)

static func tex(n: String) -> Texture2D:
	var p := "res://ui_kit/mobile/%s.png" % n
	return load(p) if ResourceLoader.exists(p) else null

func _band(parent: Control, n: String, y: float) -> TextureRect:
	var t := tex(n)
	var r := TextureRect.new()
	r.name = "Band_" + n
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := t.get_size().y if t != null else 0.0
	r.position = Vector2(0, y * s)
	r.size = Vector2(_w, h * s)
	parent.add_child(r)
	return r

func _label(parent: Control, text: String, rect: Rect2, px: float, color: Color, font: Font, align := HORIZONTAL_ALIGNMENT_CENTER, outline := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", maxi(9, int(round(px * s))))
	l.add_theme_color_override("font_color", color)
	if outline > 0.0:
		l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.0, 0.9))
		l.add_theme_constant_override("outline_size", maxi(1, int(round(outline * s))))
	parent.add_child(l)
	return l

## Área de toque transparente sobre o botão desenhado na arte; ao tocar, o próprio botão reluz.
func _hot(parent: Control, art: TextureRect, rect_ref: Rect2, _art_y: float, caption: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = "Ref_" + caption.replace(" ", "_")
	b.text = caption
	for st in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(c, Color(0, 0, 0, 0))
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.position = Vector2(rect_ref.position.x, rect_ref.position.y) * s
	b.size = rect_ref.size * s
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(b)
	if art != null and art.texture != null:
		var g := TextureRect.new()
		g.name = "RefHover"
		var at := AtlasTexture.new()
		at.atlas = art.texture
		# recorte da textura da peça embaixo do botão (a peça pode estar deslocada/escalada no painel)
		var k: Vector2 = art.texture.get_size() / (art.size / s)
		at.region = Rect2((rect_ref.position - art.position / s) * k, rect_ref.size * k)
		g.texture = at
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.size = b.size
		var m := ShaderMaterial.new()
		m.shader = GLOW
		g.material = m
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.hide()
		b.add_child(g)
		b.button_down.connect(func(): g.show())
		b.button_up.connect(func(): g.hide())
	b.pressed.connect(action)
	b.pressed.connect(func():
		var audio = hub.get_parent().get_node_or_null("GameAudio") if hub.get_parent() != null else null
		if audio != null: audio.play_cue("ui"))
	return b

## Painel que cresce: topo (fixo) + linhas lisas do miolo repetidas + fim. O conteúdo (VBox) começa em
## content_y (ref) e o painel acompanha a altura dele (sinal resized — sem checagem por quadro).
func _grow_panel(top: String, tile: String, end: String, end_room: float, content: Control, pad: float):
	var t := _band(panel, top, 0)
	_top_h = t.texture.get_size().y if t.texture != null else 0.0
	_tile_tex = tex(tile)
	_tiles = Control.new()
	_tiles.name = "Tiles"
	_tiles.clip_contents = true
	_tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tiles.position = Vector2(0, _top_h * s)
	_tiles.size = Vector2(_w, 0)
	panel.add_child(_tiles)
	_end = _band(panel, end, _top_h)
	_end_h = _end.texture.get_size().y if _end.texture != null else 0.0
	_end_room = end_room
	_content_pad = pad
	_content = content
	panel.add_child(content)
	content.resized.connect(_restack)
	_restack()

func _restack():
	if _content == null or _tiles == null: return
	var need := (_content.position.y + _content.size.y) / s + _content_pad
	var mid := maxf(0.0, need - _top_h - _end_room)
	var th := _tile_tex.get_size().y if _tile_tex != null else 1.0
	var n := int(ceil(mid / th))
	if _tiles.get_child_count() != n:
		for c in _tiles.get_children():
			_tiles.remove_child(c)
			c.queue_free()
		for i in n:
			var r := TextureRect.new()
			r.texture = _tile_tex
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_SCALE
			r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.position = Vector2(0, i * th * s)
			r.size = Vector2(_w, th * s + 1.0)   # 1 px a mais: sem fresta entre as cópias
			_tiles.add_child(r)
	_tiles.size.y = mid * s
	_end.position.y = (_top_h + mid) * s
	panel.size.y = (_top_h + mid + _end_h) * s
	_place()

func _content_box(x: float, y: float, w: float, sep: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "RefContent"
	v.position = Vector2(x, y) * s
	v.size = Vector2(w * s, 0)
	v.custom_minimum_size.x = w * s
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_theme_constant_override("separation", int(round(sep * s)))
	return v

func _wrap(parent: Control, text: String, px: float, color: Color, font: Font, align := HORIZONTAL_ALIGNMENT_LEFT, spacing := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = align
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", maxi(9, int(round(px * s))))
	l.add_theme_color_override("font_color", color)
	if spacing != 0.0: l.add_theme_constant_override("line_spacing", int(round(spacing * s)))
	parent.add_child(l)
	return l

# ------------------------------------------------------------------ MAIS (ref3)
const MAIS_Y0 := 30.0   # a peça começa na linha 30 da referência
func _build_mais():
	var art := _band(panel, "mais_panel", 0)
	panel.size.y = art.size.y
	var rows := [["VOLTAR", 612.0, 770.0], ["CONFIGURAÇÕES", 806.0, 962.0], ["CONHEÇA O FRAIHA", 1000.0, 1157.0], ["SAIR", 1194.0, 1350.0]]
	for row in rows:
		var title: String = row[0]
		var r := Rect2(92, float(row[1]) - MAIS_Y0, 716, float(row[2]) - float(row[1]))
		var action: Callable
		if title == "VOLTAR": action = func(): hub.back()
		else:
			var src = mobile._source_button(title)
			action = func(): if src != null: src.pressed.emit()
		_hot(panel, art, r, 0.0, title, action)

# ------------------------------------------------------------------ CONHEÇA O FRAIHA (ref4)
const ABOUT_Y0 := 40.0
func _build_about():
	var content := _content_box(140, 750 - ABOUT_Y0, 632, 0)
	content.name = "AboutTopicsMobile"
	var topics: Array = hub.ABOUT_TOPICS
	for i in topics.size():
		var topic: Array = topics[i]
		# linha do título: na 1ª a arte já está no topo do painel; nas outras vem a peça (flor-de-lis + divisória)
		var row := Control.new()
		row.name = "AboutTopicMobile%d" % i
		row.custom_minimum_size = Vector2(632, 120) * s
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(row)
		if i > 0:
			var ink := TextureRect.new()
			ink.texture = tex("about_title_row")
			ink.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ink.stretch_mode = TextureRect.STRETCH_SCALE
			ink.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ink.position = Vector2(-10, 0) * s
			ink.size = Vector2(646, 120) * s
			row.add_child(ink)
		var title := _label(row, String(topic[0]), R(92, 10, 540, 84), 58, GOLD, Kit.SERIF_BOLD, HORIZONTAL_ALIGNMENT_LEFT, 8)
		title.name = "AboutTitleMobile%d" % i
		title.clip_text = true
		var gap := Control.new()
		gap.custom_minimum_size.y = 28 * s
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(gap)
		var txt := RichTextLabel.new()
		txt.name = "AboutTextMobile%d" % i
		txt.bbcode_enabled = true
		txt.fit_content = true
		txt.scroll_active = false
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.add_theme_font_override("normal_font", Kit.SERIF)
		txt.add_theme_font_override("bold_font", Kit.SERIF_BOLD)
		txt.add_theme_font_size_override("normal_font_size", maxi(10, int(round(44 * s))))
		txt.add_theme_font_size_override("bold_font_size", maxi(10, int(round(44 * s))))
		txt.add_theme_color_override("default_color", CREAM)
		txt.add_theme_constant_override("line_separation", int(round(6 * s)))
		txt.text = _about_bbcode(String(topic[1]))
		content.add_child(txt)
		if i < topics.size() - 1:
			var sp := Control.new()
			sp.custom_minimum_size.y = 56 * s
			sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(sp)
	_grow_panel("about_top", "about_tile", "about_end", 40.0, content, 24.0)
	var art: TextureRect = panel.get_node("Band_about_top")
	_hot(panel, art, Rect2(88, 530 - ABOUT_Y0, 728, 118), 0.0, "VOLTAR", func(): hub.back())

## Texto do tópico como na referência: a frase curta de abertura (destaque do PC) não entra; "FRAIHA Xadrez" em ouro.
static func _about_bbcode(t: String) -> String:
	var parts := t.split("\n\n", false, 1)
	var body := parts[1] if parts.size() > 1 and parts[0].length() <= 60 else t
	body = body.replace("[", "[lb]")
	body = body.replace("FRAIHA Xadrez", "[color=#f3c55a][b]FRAIHA Xadrez[/b][/color]")
	return body.replace(" · ", "  •  ")

# ------------------------------------------------------------------ HISTÓRICO DE PARTIDAS (ref2)
const HIST_Y0 := 5.0
func _build_history():
	var content := _content_box(150, 742 - HIST_Y0, 600, 18)
	content.name = "HistoryListMobile"
	hub.history_filter = "all"
	hub.build_history_list(content, true)
	var empty: Label = content.get_node_or_null("HistoryEmpty")
	if empty != null:
		# estado vazio da referência: texto escuro centralizado no pergaminho
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_override("font", Kit.SERIF)
		empty.add_theme_font_size_override("font_size", maxi(10, int(round(42 * s))))
		empty.add_theme_color_override("font_color", INK)
		empty.add_theme_constant_override("line_spacing", int(round(2 * s)))
		empty.text = empty.text.replace(". As ", ".\nAs ")
	for row in content.get_children():
		if row is PanelContainer: _parchment_row(row)
	_grow_panel("hist_top", "hist_tile", "hist_end", 0.0, content, 4.0 if empty != null else 36.0)
	var art: TextureRect = panel.get_node("Band_hist_top")
	_hot(panel, art, Rect2(78, 368 - HIST_Y0, 744, 116), 0.0, "VOLTAR", func(): hub.back())

## Linha do histórico (montada pelo hub, mesma lógica do PC) no pergaminho da referência: moldura marrom fina,
## textos escuros na fonte serifada, botões ANALISAR/REVER do tamanho do celular. Só aparência.
func _parchment_row(row: PanelContainer):
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.32, 0.16, 0.10)
	sb.border_color = Color("9a7742")
	sb.set_border_width_all(maxi(1, int(round(3 * s))))
	sb.set_corner_radius_all(int(round(10 * s)))
	for side in ["left", "right", "top", "bottom"]: sb.set("content_margin_" + side, round(22 * s))
	row.add_theme_stylebox_override("panel", sb)
	var first := true
	for l in row.find_children("*", "Label", true, false):
		var lab: Label = l
		var c: Color = lab.get_theme_color("font_color")
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size.x = 0
		lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		lab.add_theme_font_override("font", Kit.SERIF_BOLD if first else Kit.SERIF)
		lab.add_theme_font_size_override("font_size", maxi(10, int(round((38 if first else 32) * s))))
		var col := INK
		if first:
			# cor do resultado (vitória / derrota / empate) em tom escuro, legível no pergaminho
			col = Color("2f6a1e") if c.g > c.r + 0.1 else (Color("8c2a18") if c.r > c.g + 0.25 else Color("6b4a0e"))
		elif c.g > c.r + 0.15:
			col = Color("2f6a1e")   # "Analisada · precisão"
		lab.add_theme_color_override("font_color", col)
		first = false
	for b in row.find_children("*", "Button", true, false):
		var btn: Button = b
		btn.custom_minimum_size = Vector2(0, round(84 * s))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.add_theme_font_override("font", Kit.SERIF_BOLD)
		btn.add_theme_font_size_override("font_size", maxi(10, int(round(34 * s))))
	for box in row.find_children("*", "BoxContainer", true, false):
		(box as BoxContainer).add_theme_constant_override("separation", int(round(10 * s)))

# ------------------------------------------------------------------ LIGAS E RANKING (ref7)
const ThemeCatalog = preload("res://cosmetics/theme_catalog.gd")
const LIGA_TOP_H := 404.0
const LIGA_ROW_H := 104.0
const LIGA_END_H := 149.0
func _build_ranking():
	var entries: Array = hub.LeagueCatalog.entries(hub.league_profile.data)
	var rows := entries.size() + 1                                   # + PEÇAS CLÁSSICAS
	var top := _band(panel, "ligas_top", 0)
	# faixa do jogador: nome — liga atual · PL (o mesmo texto do cabeçalho do PC)
	var d: Dictionary = hub.league_profile.data
	var cur = hub.LeagueCatalog.entry(d.current_league, d)
	var who := _label(panel, "%s — %s  ·  %d / 100 PL" % [hub.player_name, cur.display_name, int(d.lp)], R(268, 332, 440, 64), 36, Color("f0dcae"), Kit.SERIF_BOLD, HORIZONTAL_ALIGNMENT_LEFT, 5)
	who.name = "RankingHeaderMobile"
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hot(panel, top, Rect2(118, 238, 664, 82), 0.0, "VOLTAR", func(): hub.back())
	for k in rows:
		var y := LIGA_TOP_H + k * LIGA_ROW_H
		_band(panel, "ligas_row%d" % mini(k, 9) if k < 10 else "ligas_row%d" % (4 + k % 2), y)
		var classic := k == entries.size()
		var id: String = "" if classic else String(entries[k].league_id)
		var unlocked: bool = classic or hub.league_unlocked(id)
		var selected: bool = (hub.current_piece_set == "classic") if classic else (unlocked and id == hub.selected_league)
		var mid := TextureRect.new()
		mid.name = "LeagueRow_" + (id if not classic else "classic")
		mid.texture = tex("ligas_mid_" + ("sel" if selected else ("on" if unlocked else "off")))
		mid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mid.stretch_mode = TextureRect.STRETCH_SCALE
		mid.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid.position = Vector2(86, y) * s
		mid.size = Vector2(706, LIGA_ROW_H) * s
		panel.add_child(mid)
		var crest := TextureRect.new()
		crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crest.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if classic:
			crest.texture = load("res://ui_kit/pages/ico_peao_branco.png")
			crest.position = Vector2(150, y + 14) * s
			crest.size = Vector2(84, 76) * s
		else:
			var laurel := TextureRect.new()
			laurel.texture = tex("ligas_laurel")
			laurel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			laurel.stretch_mode = TextureRect.STRETCH_SCALE
			laurel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			laurel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			laurel.position = Vector2(112, y) * s
			laurel.size = Vector2(160, LIGA_ROW_H) * s
			panel.add_child(laurel)
			crest.texture = ThemeCatalog.badge_texture(id)
			crest.position = Vector2(116, y + 1) * s       # a célula do brasão tem margem própria
			crest.size = Vector2(152, 102) * s
		crest.name = "LeagueCrest_" + (id if not classic else "classic")
		panel.add_child(crest)
		var title: String = "PEÇAS CLÁSSICAS" if classic else String(entries[k].display_name).to_upper()
		var col: Color = Color("f3d48c") if unlocked else Color("c9c6bb")
		var px := 40.0
		var room := 225.0
		if classic: px = 34.0
		elif " " in title and Kit.SERIF_BOLD.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x > room:
			title = title.replace(" ", "\n")                         # "GRANDE MESTRE" em duas linhas, como na arte
			px = 36.0
		while px > 28.0 and Kit.SERIF_BOLD.get_string_size(title.get_slice("\n", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x > room: px -= 2.0
		var name_l := _label(panel, title, R(284, y + 4, 250, 96), px, col, Kit.SERIF_BOLD, HORIZONTAL_ALIGNMENT_LEFT, 5)
		name_l.name = "LeagueName_" + (id if not classic else "classic")
		name_l.add_theme_constant_override("line_spacing", int(round(-8 * s)))
		if classic:
			var on: bool = hub.current_piece_set == "classic"
			var sub := _label(panel, "Em uso · toque para desligar" if on else "Usar o conjunto original", R(284, y + 56, 290, 34), 26, Color("cfe7a8") if on else CREAM, Kit.SERIF, HORIZONTAL_ALIGNMENT_LEFT, 0)
			sub.name = "ClassicPiecesSubMobile"
			name_l.position.y = (y + 10) * s
			name_l.size.y = 50 * s
			_hot(panel, mid, Rect2(86, y, 706, LIGA_ROW_H), y, "PEÇAS CLÁSSICAS", func():
				hub._toggle_classic_pieces()
				refresh())
		else:
			_hot(panel, mid, Rect2(86, y, 706, LIGA_ROW_H), y, "LIGA " + title.replace("\n", " "), func():
				hub._select_league(id)
				refresh())
	_band(panel, "ligas_end", LIGA_TOP_H + rows * LIGA_ROW_H)
	panel.size.y = (LIGA_TOP_H + rows * LIGA_ROW_H + LIGA_END_H) * s
