extends Control
## R53 · JOGAR RANQUEADO no celular, no visual da referência aprovada (tools/ui_ref/mobile/mob_ranqueado.jpg).
## Painel com as peças recortadas da referência (ui_kit/mobile/rk_*.png) por cima do cenário do FRAIHA:
## um cartão por ritmo ABERTO (o Admin pode fechar ritmos), com brasão da liga, nome, minutos, liga e PL,
## barra de PL e V · D · E · partidas · % — tudo do estado real da conta (account.ranked). BUSCAR PARTIDA e
## VOLTAR repassam para os botões reais da ranked_ui (mesmas ações e regras). Monta quando a tela abre,
## quando a lista muda e quando a largura muda (giro) — nada por quadro.
const RefPage = preload("res://ui_v022/mobile_ref_page.gd")
const Mobile = preload("res://ui_v022/mobile_layout.gd")
const Kit = preload("res://ui_kit/kit.gd")
const ThemeCatalog = preload("res://cosmetics/theme_catalog.gd")
const Catalog = preload("res://league/catalog.gd")
const TITLE_FONT = preload("res://account/fonts/Cinzel-Bold.woff")
const REF_W := 900.0
const MAX_W := 460.0
const TOP_H := 545.0
const CARD_H := 414.0
const CARD_BOTTOM := 395.0   # fim da moldura do cartão (o resto da peça é o vão até o próximo)
const END_H := 240.0
const CREAM := Color("efe6cf")

var ui            # ranked_ui dona
var scenery: TextureRect
var dim: ColorRect
var scroll: ScrollContainer
var body: Control
var panel: Control
var notice_label: Label = null
var s := 1.0
var _w := -1.0

func setup(owner):
	ui = owner
	name = "MobileRankedArt"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	scenery = TextureRect.new()
	scenery.texture = load(RefPage.SCENE_PATH)   # R89 · recorte pequeno (antes: atlas de 6 MB)
	scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scenery.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scenery)
	dim = ColorRect.new()
	dim.color = Color(0.014, 0.019, 0.029, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	scroll = ScrollContainer.new()
	scroll.name = "RankedArtScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(body)
	get_viewport().size_changed.connect(func(): if visible: layout())

func open():
	visible = true
	_w = -1.0
	layout()
	scroll.scroll_vertical = 0

func close():
	visible = false

## Remonta (lista de ritmos mudou / estado da conta mudou) mantendo a rolagem.
func rebuild():
	if not visible: return
	var sv := scroll.scroll_vertical
	_w = -1.0
	layout()
	scroll.scroll_vertical = sv

## Aviso da ranked_ui (servidor de teste / erro da fila): plaquinha fixa no pé da tela (não rola), só com texto.
func set_notice(text: String):
	if not is_instance_valid(notice_label):
		notice_label = Label.new()
		notice_label.name = "RankedArtNotice"
		notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		notice_label.add_theme_font_override("font", Kit.SERIF_BOLD)
		notice_label.add_theme_font_size_override("font_size", 14)
		notice_label.add_theme_color_override("font_color", Color("ffb08f"))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.042, 0.066, 0.113, 0.94)
		sb.border_color = Color("c99a45")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		for side in ["left", "right", "top", "bottom"]: sb.set("content_margin_" + side, 8)
		notice_label.add_theme_stylebox_override("normal", sb)
		add_child(notice_label)
	notice_label.text = text
	notice_label.visible = not text.is_empty()
	var full := get_viewport().get_visible_rect().size
	var area := Mobile.safe_rect(get_viewport())
	var w := minf(full.x - 24.0, 420.0)
	var h := Kit.SERIF_BOLD.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w - 16.0, 14).y + 18.0
	notice_label.size = Vector2(w, 0)   # largura primeiro: a altura mínima de texto que quebra depende dela
	notice_label.size = Vector2(w, h)
	notice_label.position = Vector2((full.x - w) / 2.0, area.end.y - h - 6.0)

func layout():
	var full := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = full
	scenery.size = full
	dim.size = full
	scroll.size = full
	var w := minf(full.x, MAX_W)
	if absf(w - _w) > 0.5:
		_w = w
		s = w / REF_W
		_build()
	_place()

func _place():
	if panel == null: return
	var full := get_viewport().get_visible_rect().size
	var area := Mobile.safe_rect(get_viewport())
	var top_in := maxf(0.0, area.position.y - 8.0)
	var bottom_in := maxf(0.0, full.y - area.end.y - 8.0)
	var room := full.y - top_in - bottom_in
	var y := top_in + maxf(0.0, (room - panel.size.y) / 2.0)
	panel.position = Vector2(roundf((full.x - _w) / 2.0), roundf(y))
	body.custom_minimum_size = Vector2(full.x, y + panel.size.y + bottom_in)

func R(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(x * s, y * s, w * s, h * s)

func _band(n: String, y: float) -> TextureRect:
	var r := TextureRect.new()
	r.name = "Band_" + n
	r.texture = RefPage.tex(n)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h: float = r.texture.get_size().y if r.texture != null else 0.0
	r.position = Vector2(0, y * s)
	r.size = Vector2(_w, h * s)
	panel.add_child(r)
	return r

func _label(text: String, rect: Rect2, px: float, color: Color, font: Font, align := HORIZONTAL_ALIGNMENT_LEFT, outline := 0.0, fit := true) -> Label:
	var l := Label.new()
	l.text = text
	l.clip_text = fit
	if not fit and " " in text and not "\n" in text: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # R177b · frase: quebra na largura
	l.position = rect.position
	l.size = rect.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	# R177b · o texto encolhe até caber na caixa (CONVENCIONAL cortava o L)
	var fs := maxi(8, int(round(px * s)))
	var ow := int(round(outline * s)) * 2
	var widest := func(q: int) -> float:
		var m := 0.0
		for line in text.split("\n"): m = maxf(m, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, q).x)
		return m
	var nl := text.count("\n") + 1
	while fit and fs > 8 and (widest.call(fs) + ow > rect.size.x - 2.0 or (nl > 1 and font.get_height(fs) * nl > rect.size.y + 4.0)): fs -= 1
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	if outline > 0.0:
		l.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.0, 0.9))
		l.add_theme_constant_override("outline_size", maxi(1, int(round(outline * s))))
	panel.add_child(l)
	l.size = rect.size
	return l

## Toque transparente que repassa para o botão real da ranked_ui (mesma ação).
func _hit(rect: Rect2, caption: String, real_name: String, from_footer := false) -> Button:
	var b := Button.new()
	b.name = "Ref_" + caption.replace(" ", "_")
	b.text = caption
	for st in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(c, Color(0, 0, 0, 0))
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.position = rect.position * s
	b.size = rect.size * s
	var hl := ColorRect.new()   # toque: o botão da arte clareia um pouco
	hl.color = Color(1.0, 0.9, 0.55, 0.12)
	hl.size = b.size
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl.hide()
	b.add_child(hl)
	b.button_down.connect(func(): hl.show())
	b.button_up.connect(func(): hl.hide())
	b.pressed.connect(func():
		var src = (ui.footer if from_footer else ui.box).find_child(real_name, true, false)
		if src != null and not src.disabled: src.pressed.emit())
	panel.add_child(b)
	return b

func _build():
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	panel = Control.new()
	panel.name = "RankedArtPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.size.x = _w
	body.add_child(panel)
	var casual: bool = not ui.rated()
	_band("rk_top_casual" if casual else "rk_top", 0)
	if casual:
		# R177b · JOGAR ONLINE (Casual) no mesmo visual do Ranqueado: a placa de cima sem o texto, com o texto vivo
		var tl := _label("JOGAR\nONLINE", R(150, 222, 600, 166), 84, Color("f6c85a"), TITLE_FONT, HORIZONTAL_ALIGNMENT_CENTER, 8, false)
		tl.name = "CasualTitle"
		tl.add_theme_constant_override("line_spacing", int(round(-38 * s)))
		var sub := _label("Partida casual contra outro jogador. Não vale PL e não altera o Ranked.", R(170, 438, 560, 80), 30, CREAM, Kit.SERIF, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.size = R(170, 438, 560, 80).size
		sub.name = "CasualSub"
	var modes: Array = ui.mode_list()
	var y := TOP_H
	for item in modes:
		if casual: _casual_card(item, y)
		else: _card(item, y)
		y += CARD_H
	if casual and not modes.is_empty() and ui.box.find_child("InviteFriendButton", true, false) != null:
		# CONVIDAR AMIGO: um cartão a mais, com o botão no lugar do BUSCAR PARTIDA
		var inv := _band("rk_card_casual", y)
		inv.name = "CasualInviteCard"
		_label("JOGAR COM UM AMIGO", R(150, y + 40, 600, 70), 50, Color("f6c85a"), TITLE_FONT, HORIZONTAL_ALIGNMENT_CENTER, 6)
		var t2 := _label("Chame um amigo online para uma partida casual.", R(150, y + 130, 600, 90), 32, CREAM, Kit.SERIF, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false)
		t2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t2.size = R(150, y + 130, 600, 90).size
		var cover := _label("CONVIDAR AMIGO", R(230, y + 296, 440, 60), 44, Color("f7ecd2"), TITLE_FONT, HORIZONTAL_ALIGNMENT_CENTER, 5)
		cover.name = "CasualInviteText"
		_cover_btn_text(y)
		_hit(Rect2(140, y + 278, 626, 94), "CONVIDAR AMIGO", "InviteFriendButton")
		move_child_to_top(cover)
		y += CARD_H
	if modes.is_empty():
		# Admin fechou todos os ritmos: o aviso no lugar dos cartões (o cartão vazio da arte por baixo)
		_band("rk_card", y)
		_label(ui.unavailable_title(), R(150, y + 60, 600, 120), 40, Color("f6d27a"), TITLE_FONT, HORIZONTAL_ALIGNMENT_CENTER, 6).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label("Novas filas serão abertas em breve.", R(150, y + 190, 600, 50), 32, CREAM, Kit.SERIF, HORIZONTAL_ALIGNMENT_CENTER)
		y += CARD_H
	var end_y := y - CARD_H + CARD_BOTTOM
	_band("rk_end", end_y)
	_hit(Rect2(96, end_y + 36, 708, 104), "VOLTAR", "BackButton", true)
	panel.size.y = (end_y + END_H) * s
	var warn := ""
	if is_instance_valid(ui.notice): warn = ui.notice.text
	if warn.is_empty() and not ui.account.persistent_backend: warn = "Servidor em modo de teste: resultados NÃO ficam salvos."
	set_notice(warn)
	_place()

func move_child_to_top(n: Control):
	panel.move_child(n, panel.get_child_count() - 1)

## o texto BUSCAR PARTIDA vem pintado na arte do cartão: coberto pela cor do botão para trocar o texto
func _cover_btn_text(y: float):
	# a própria arte do botão (faixa sem texto entre o losango e a palavra) esticada por cima do texto
	var at := AtlasTexture.new()
	at.atlas = load("res://ui_kit/mobile/rk_card_casual.png")
	at.region = Rect2(222, 300, 24, 56)
	var c := TextureRect.new()
	c.name = "BtnTextCover"
	c.texture = at
	c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	c.stretch_mode = TextureRect.STRETCH_SCALE
	c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = Vector2(246, y + 300) * s
	c.size = Vector2(412, 56) * s
	panel.add_child(c)

## R177b · cartão do JOGAR ONLINE (Casual): coroa no lugar do brasão da liga, sem barra de PL
func _casual_card(item: Array, y: float):
	var id: String = item[0]
	var card := _band("rk_card_casual", y)
	card.name = "CasualCard_" + id
	var crest := TextureRect.new()
	crest.name = "CasualCrest_" + id
	crest.texture = load("res://ui_kit/mobile/bots_crown.png")
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crest.position = Vector2(132, y + 30) * s
	crest.size = Vector2(150, 140) * s
	panel.add_child(crest)
	_label(String(item[1]), R(292, y + 24, 470, 66), 56, Color("f6c85a"), TITLE_FONT, HORIZONTAL_ALIGNMENT_LEFT, 7).name = "RankedName_" + id
	_label("%d min por jogador" % int(item[2]), R(294, y + 86, 440, 44), 34, CREAM, Kit.SERIF)
	_label("PARTIDA CASUAL · SEM PL", R(290, y + 133, 460, 48), 32, Color("f4ecd8"), Kit.SERIF_BOLD, HORIZONTAL_ALIGNMENT_LEFT, 3)
	_label("Não altera sua liga nem o Ranked", R(150, y + 196, 600, 44), 30, Color("c9c2ae"), Kit.SERIF, HORIZONTAL_ALIGNMENT_CENTER)
	_hit(Rect2(140, y + 278, 626, 94), "BUSCAR " + id, "Queue_" + id)

func _card(item: Array, y: float):
	var id: String = item[0]
	var stats: Dictionary = ui.account.ranked.get(id, {}) if ui.account.ranked is Dictionary else {}
	var league := clampi(int(stats.get("league", 0)), 0, 10)
	var pl := int(stats.get("pl", 0))
	var card := _band("rk_card", y)
	card.name = "RankedCard_" + id
	var crest := TextureRect.new()
	crest.name = "RankedCrest_" + id
	crest.texture = ThemeCatalog.badge_texture(Catalog.IDS[league])
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crest.position = Vector2(112, y + 10) * s     # a célula do brasão tem margem própria
	crest.size = Vector2(196, 178) * s
	panel.add_child(crest)
	_label(String(item[1]), R(292, y + 24, 470, 66), 56, Color("f6c85a"), TITLE_FONT, HORIZONTAL_ALIGNMENT_LEFT, 7).name = "RankedName_" + id
	_label("%d min por jogador" % int(item[2]), R(294, y + 86, 440, 44), 34, CREAM, Kit.SERIF)
	_label(ui.league_line(league, pl), R(290, y + 133, 460, 48), 34, Color("f4ecd8"), Kit.SERIF_BOLD, HORIZONTAL_ALIGNMENT_LEFT, 3).name = "RankedLeague_" + id
	# barra de PL: a moldura é da arte; o preenchimento é o PL real
	var fill := ColorRect.new()
	fill.name = "RankedBar_" + id
	fill.color = Color("e9b44c")
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.position = Vector2(158, y + 190) * s
	fill.size = Vector2(584.0 * clampf(pl / 100.0, 0.0, 1.0), 22) * s
	panel.add_child(fill)
	var total := int(stats.get("matches", 0))
	var rate := (100.0 * int(stats.get("wins", 0)) / total) if total > 0 else 0.0
	_label("%dV · %dD · %dE · %d partidas · %d%%" % [int(stats.get("wins", 0)), int(stats.get("losses", 0)), int(stats.get("draws", 0)), total, roundi(rate)], R(150, y + 228, 600, 44), 32, Color("e6e0cc"), Kit.SERIF, HORIZONTAL_ALIGNMENT_CENTER).name = "RankedStats_" + id
	_hit(Rect2(140, y + 278, 626, 94), "BUSCAR " + id, "Queue_" + id)
