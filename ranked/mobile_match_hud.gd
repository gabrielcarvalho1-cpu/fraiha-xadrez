extends Node
## R53 · HUD da PARTIDA no CELULAR (em pé e deitado), no visual das referências aprovadas
## (tools/ui_ref/mobile/mob_partida_portrait.png e mob_partida_landscape.png → ranked/art/mob_hud_*.png,
## tools/mobile_match_hud.py). Vale nas partidas contra o computador, Casual e Ranqueado no celular.
## Só APRESENTAÇÃO: o tabuleiro continua sendo o mesmo grid do jogo; os dados dos cartões (retrato, nome, liga/PL,
## relógio, material, voz) são os do jogo (faixas da ranked_ui); todos os botões chamam as MESMAS ações de
## sempre (os botões antigos do celular continuam existindo, escondidos, como fonte das ações).
##   · EM PÉ: cartão do adversário · tabuleiro · cartão do jogador; embaixo INÍCIO · AÇÕES · CHAT.
##   · DEITADO: tabuleiro na altura inteira, no meio; cartões do adversário (em cima) e do jogador (embaixo) na
##     coluna da esquerda; à direita CHAT e a aba AÇÕES. Painel fechado não reserva coluna: o tabuleiro manda.
## AÇÕES abre um painel com as ações que existem NAQUELA partida (desistir/jogar de novo, marcar, analisar, música,
## efeitos, voz, tela cheia). Fim de partida, promoção ou resultado fecham o painel (o resultado tem prioridade).
## Monta/posiciona no layout do stage (resize, giro, troca de modo) — nada é recriado por quadro.
const MobileLayout := preload("res://ui_v022/mobile_layout.gd")
const ModeSound := preload("res://ui_v022/mode_sound.gd")
const VoiceGlyph := preload("res://voice/voice_glyph.gd")
const Kit := preload("res://ui_kit/kit.gd")
const FONT_TITLE := preload("res://account/fonts/Cinzel-Bold.woff")
const SkinRef := preload("res://ranked/board_skin.gd")
const ART := "res://ranked/art/mob_hud_%s.png"
const GOLD := Color("f4ce7f")
const CREAM := Color("f3ede0")

## ---- referência EM PÉ (941 x 1672) ----
const P_W := 941.0
const P_CORE := Vector2(92.0, 849.0)          # moldura de madeira do tabuleiro (o que precisa caber na largura)
const P_BOARD := Rect2(123.5, 250.5, 687.5, 667.0)
const P_BLOCK := Vector2(50.0, 1085.0)        # do cartão do adversário ao fim do cartão do jogador
const P_NAV_Y := 1480.0                       # topo do recorte da barra de baixo
const P_NAV_BUTTONS := 160.0                  # da borda do recorte ao pé dos botões
const P_NAV := {"home": Rect2(208, 1503, 164, 125), "actions": Rect2(392, 1490, 164, 150), "chat": Rect2(570, 1503, 164, 125)}
const P_CARD := {
	"top": {"card": Rect2(128, 64, 714, 118), "avatar": Rect2(167, 88, 76, 76), "round": true,
		"name": Rect2(262, 84, 206, 44), "name_fs": 34.0, "sub": Rect2(264, 128, 206, 30), "sub_fs": 23.0,
		"material": Rect2(470, 106, 136, 38), "clock": Rect2(684, 92, 134, 64), "clock_fs": 50.0},
	"bottom": {"card": Rect2(86, 962, 772, 120), "avatar": Rect2(118, 982, 96, 82), "round": false,
		"name": Rect2(238, 984, 236, 44), "name_fs": 34.0, "sub": Rect2(240, 1028, 236, 30), "sub_fs": 23.0,
		"material": Rect2(480, 1006, 142, 38), "clock": Rect2(698, 990, 126, 64), "clock_fs": 50.0},
}
const P_PANEL := Rect2(20, 1100, 901, 390)    # painel AÇÕES aberto (base colada na barra de baixo)
const P_TILE := Vector2(180, 126)
const P_TILE_GAP := Vector2(22, 12)
const P_TILE_TOP := 92.0
## ---- referência DEITADO (1672 x 941) + moldura recortada da referência em pé (750 x 772) ----
const L_W := 1672.0
const L_H := 941.0
const F_SIZE := Vector2(750, 772)
const F_BOARD := Rect2(27.5, 70.5, 687.5, 667.0)

var stage
var on := false
var orient := ""              # "p" | "l"
var wood := true              # tema Madeira: cenário + moldura da arte; outros temas: o cenário do tema fica
var k := 1.0                  # px de tela por px da referência
var off := Vector2.ZERO       # canto da referência na tela
var bg: BgArt
var layer: CanvasLayer
var root: Control
var plates := {}              # cartões soltos (deitado ou tema ≠ Madeira)
var plate_layer: CanvasLayer
var panel_layer: CanvasLayer
var sheet: PanelContainer     # contra o computador (em pé): lista completa de lances (LANCES)
var sheet_text: RichTextLabel
var nav: Control              # barra de baixo (em pé)
var nav_buttons := {}
var corner := {}              # deitado: voltar, opções, chat, aba AÇÕES
var panel: Control
var panel_art: NinePatchRect
var tiles_box: Control
var tiles := []               # [Button, id]
var moves: RichTextLabel      # contra o computador: últimos lances
var link: Label
var _orig := {}
var _key := ""
var _moves_n := -1
var _texts := {}

func setup(owner_stage) -> void:
	stage = owner_stage
	name = "MobileMatchHud"
	bg = BgArt.new()
	bg.name = "MobileMatchArt"
	bg.z_index = -15
	bg.visible = false
	stage.add_child(bg)
	layer = CanvasLayer.new()
	layer.name = "MobileMatchHudLayer"
	layer.layer = 41          # acima dos botões antigos (40), abaixo das faixas/resultado do Ranked (45+)
	stage.add_child(layer)
	root = Control.new()
	root.name = "HudRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	_build_plates()
	_build_nav()
	_build_corner()
	_build_panel()
	moves = RichTextLabel.new()
	moves.name = "HudMoves"
	moves.bbcode_enabled = true
	moves.scroll_active = false
	moves.clip_contents = true
	var ms := StyleBoxFlat.new()
	ms.bg_color = Color(0.03, 0.08, 0.05, 0.86)
	ms.border_color = Color(0.79, 0.6, 0.27, 0.7)
	ms.set_border_width_all(1)
	ms.set_corner_radius_all(6)
	for side in ["left", "right", "top", "bottom"]: ms.set("content_margin_" + side, 6)
	moves.add_theme_stylebox_override("normal", ms)
	moves.mouse_filter = Control.MOUSE_FILTER_IGNORE
	moves.add_theme_font_override("normal_font", Kit.SERIF)
	moves.add_theme_font_override("bold_font", FONT_TITLE)
	moves.add_theme_color_override("default_color", Color("efe6d2"))
	root.add_child(moves)
	sheet = PanelContainer.new()
	sheet.name = "HudMovesSheet"
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.03, 0.08, 0.05, 0.95)
	ss.border_color = Color("c99a45")
	ss.set_border_width_all(2)
	ss.set_corner_radius_all(8)
	for side in ["left", "right", "top", "bottom"]: ss.set("content_margin_" + side, 12)
	sheet.add_theme_stylebox_override("panel", ss)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet_text = RichTextLabel.new()
	sheet_text.bbcode_enabled = true
	sheet_text.scroll_following = true
	sheet_text.add_theme_font_override("normal_font", Kit.SERIF)
	sheet_text.add_theme_font_override("bold_font", FONT_TITLE)
	sheet_text.add_theme_color_override("default_color", Color("efe6d2"))
	sheet_text.add_theme_font_size_override("normal_font_size", 17)
	sheet_text.add_theme_font_size_override("bold_font_size", 19)
	sheet.add_child(sheet_text)
	sheet.gui_input.connect(func(ev): if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed): sheet.hide())
	root.add_child(sheet)
	sheet.hide()
	layer.hide()

static func tex(n: String) -> Texture2D:
	return load(ART % n)

# ------------------------------------------------------------------ quando vale
func wanted() -> bool:
	if stage == null or stage.game == null or not stage.game.visible: return false
	if not MobileLayout.active(stage.get_viewport()): return false
	return stage.mode in ["bot", "ranked", "casual"]

## A ranked_ui cujas faixas (cartões) valem nesta partida: Casual tem as suas; Ranked e bot usam as do Ranked.
func ui():
	return stage.casual_ui if stage.mode == "casual" else stage.ranked_ui

func before_layout() -> void:
	if on and not wanted(): restore()

func after_layout() -> void:
	if wanted(): apply()

# ------------------------------------------------------------------ registro / desfazer (como a pele do PC)
func _rec(obj: Object, prop: String, val) -> void:
	if obj == null: return
	var key := "%d|%s" % [obj.get_instance_id(), prop]
	if not _orig.has(key): _orig[key] = [obj, "p", prop, obj.get(prop)]
	obj.set(prop, val)

func _ov(ctrl: Control, what: String, nm: String, val) -> void:
	var key := "%d|%s|%s" % [ctrl.get_instance_id(), what, nm]
	if not _orig.has(key):
		var had := false
		var old = null
		match what:
			"style": had = ctrl.has_theme_stylebox_override(nm); old = ctrl.get_theme_stylebox(nm) if had else null
			"font": had = ctrl.has_theme_font_override(nm); old = ctrl.get_theme_font(nm) if had else null
			"size": had = ctrl.has_theme_font_size_override(nm); old = ctrl.get_theme_font_size(nm) if had else null
			"color": had = ctrl.has_theme_color_override(nm); old = ctrl.get_theme_color(nm) if had else null
			"const": had = ctrl.has_theme_constant_override(nm); old = ctrl.get_theme_constant(nm) if had else null
		_orig[key] = [ctrl, what, nm, old, had]
	match what:
		"style": ctrl.add_theme_stylebox_override(nm, val)
		"font": ctrl.add_theme_font_override(nm, val)
		"size": ctrl.add_theme_font_size_override(nm, int(val))
		"color": ctrl.add_theme_color_override(nm, val)
		"const": ctrl.add_theme_constant_override(nm, int(val))

func restore() -> void:
	close_actions()
	for key in _orig:
		var e: Array = _orig[key]
		var obj = e[0]
		if not is_instance_valid(obj): continue
		if e[1] == "p":
			obj.set(e[2], e[3])
			continue
		var ctrl: Control = obj
		var had: bool = e[4]
		match e[1]:
			"style":
				if had: ctrl.add_theme_stylebox_override(e[2], e[3])
				else: ctrl.remove_theme_stylebox_override(e[2])
			"font":
				if had: ctrl.add_theme_font_override(e[2], e[3])
				else: ctrl.remove_theme_font_override(e[2])
			"size":
				if had: ctrl.add_theme_font_size_override(e[2], e[3])
				else: ctrl.remove_theme_font_size_override(e[2])
			"color":
				if had: ctrl.add_theme_color_override(e[2], e[3])
				else: ctrl.remove_theme_color_override(e[2])
			"const":
				if had: ctrl.add_theme_constant_override(e[2], e[3])
				else: ctrl.remove_theme_constant_override(e[2])
	_orig.clear()
	for u in [stage.ranked_ui, stage.casual_ui]:
		if u == null: continue
		for key in ["top", "bottom"]:
			var ck = u.strips[key].clock
			if is_instance_valid(ck): ck.set_bare(false)
	on = false
	orient = ""
	_texts.clear()
	bg.visible = false
	layer.hide()
	_hide_plates()
	if sheet != null: sheet.hide()
	if stage.material_hud != null: stage.material_hud.queue_redraw()

# ------------------------------------------------------------------ geometria
func R(r: Rect2) -> Rect2:
	return Rect2(off + r.position * k, r.size * k)

# ------------------------------------------------------------------ aplicar
func apply() -> void:
	var vp: Viewport = stage.get_viewport()
	var vs: Vector2 = vp.get_visible_rect().size
	var safe: Rect2 = MobileLayout.safe_rect(vp)
	orient = "p" if MobileLayout.is_portrait(vp) else "l"
	wood = String(stage.game.visual_theme) == "wood"
	on = true
	layer.show()
	# a interface antiga do celular sai de cena (os botões continuam existindo: são a fonte das ações)
	for n in [stage.bot_info, stage.mobile_status, stage.player_card, stage.home_button, stage.mobile_actions]:
		if n != null: _rec(n, "visible", false)
	# a floresta pintada (só a Madeira a mostra) sai: na Madeira o fundo é a arte da referência; nos outros temas
	# o tema já a esconde e mostra a arena dele
	_rec(stage.forest, "visible", false)
	var env = stage.game.get_node_or_null("ForestEnvironment")
	if env != null: _rec(env, "visible", not wood)
	var g = stage.game
	_rec(g, "hide_status", true)
	_rec(g, "piece_override", SkinRef.PECAS if wood else {})   # Madeira: as peças pixel art da arte; outro tema: as dele
	var board: Rect2
	if orient == "p": board = _layout_portrait(vs, safe)
	else: board = _layout_landscape(vs, safe)
	g.scale = Vector2(board.size.x / g.BOARD, board.size.y / g.BOARD)
	g.position = board.position - g.ORIGIN * g.scale
	g.update_presentation(Rect2(-g.position / g.scale.x, vs / g.scale.x))
	g.queue_redraw()
	bg.queue_redraw()
	# outro tema: a arena do tema (theme_manager) continua no fundo, colada ao tabuleiro na posição nova
	if not wood and is_instance_valid(stage.theme_manager): stage.theme_manager.layout()
	_texts.clear()   # posições novas: os textos vivos são reencaixados no próximo quadro
	if stage.mobile_promotion != null:
		stage.mobile_promotion.position = board.get_center() - stage.mobile_promotion.size / 2.0
	_layout_chat(board, safe)
	refresh_actions()
	_key = ""
	_process(0.0)

# ---------- EM PÉ
func _layout_portrait(vs: Vector2, safe: Rect2) -> Rect2:
	var core_w := P_CORE.y - P_CORE.x
	k = minf(vs.x / core_w, safe.size.y / (P_BLOCK.y - P_BLOCK.x + P_NAV_BUTTONS))
	var ox := vs.x / 2.0 - P_W / 2.0 * k
	var nav_top := safe.end.y - P_NAV_BUTTONS * k
	var slack := maxf(0.0, nav_top - safe.position.y - (P_BLOCK.y - P_BLOCK.x) * k)
	# a sobra fica embaixo do cartão do jogador: é onde o painel AÇÕES abre (como na referência) sem cobrir nada
	var block_top := safe.position.y + maxf(0.0, slack - P_PANEL.size.y * k) * 0.4
	off = Vector2(ox, block_top - P_BLOCK.x * k)
	bg.mode = "p"
	bg.wood = wood
	bg.full = Rect2(Vector2.ZERO, vs)
	bg.top_rect = Rect2(off, Vector2(P_W, 1092.0) * k)
	bg.visible = true
	# barra de baixo
	nav.show()
	nav.position = Vector2(ox, nav_top)
	nav.size = Vector2(P_W, 192.0) * k
	var nav_art: TextureRect = nav.get_node("Art")
	nav_art.size = nav.size
	for id in nav_buttons:
		var b: Button = nav_buttons[id]
		var r: Rect2 = P_NAV[id]
		b.position = Vector2(r.position.x, r.position.y - P_NAV_Y) * k
		b.size = r.size * k
		_fit_nav_button(b)
	for id in corner: corner[id].hide()
	var third: Button = nav_buttons.chat
	var bot_mode: bool = stage.mode == "bot"
	(third.get_node("Caption") as Label).text = "LANCES" if bot_mode else "CHAT"
	(third.get_node("Icon") as TextureRect).texture = tex("ico_mark" if bot_mode else "ico_chat")
	third.tooltip_text = "Lances da partida" if bot_mode else "Chat da partida"
	var br := R(P_BOARD)
	_set_rect(sheet, br.grow(-br.size.x * 0.04))
	# cartões
	for key in ["top", "bottom"]:
		var spec: Dictionary = P_CARD[key]
		var p: Dictionary = plates[key]
		for n in p.values(): n.hide()
		if not wood:
			p.flat.show()
			p.box.show()
			p.ring.visible = bool(spec.round)
			_set_rect(p.flat, R(spec.card))
			_set_rect(p.box, R(Rect2(spec.card.end.x - 236.0, spec.card.position.y + 8.0, 230.0, 102.0)))
			var ar: Rect2 = R(spec.avatar)
			_set_rect(p.ring, Rect2(ar.get_center() - ar.size * 0.66, ar.size * 1.32))
		_skin_strip(key, R(spec.card), R(spec.avatar), bool(spec.round), R(spec.name), spec.name_fs * k, R(spec.sub), spec.sub_fs * k, R(spec.clock), spec.clock_fs * k, R(spec.material))
	# painel AÇÕES: base colada na barra de baixo, na largura da tela
	_layout_panel_portrait(_panel_base(safe))
	# aviso de conexão (Ranked/Casual) logo abaixo do cartão do adversário
	link = ui().link_label
	link.position = R(Rect2(40, 186, 860, 40)).position
	link.size = R(Rect2(40, 186, 860, 40)).size
	# lances (contra o computador): na sobra entre o cartão do jogador e a barra
	var mv_top := off.y + 1086.0 * k
	moves.visible = stage.mode == "bot" and nav_top - mv_top >= 26.0
	if moves.visible:
		var h := minf(nav_top - mv_top - 6.0, 44.0)
		moves.position = Vector2(safe.position.x + 6.0, mv_top + (nav_top - mv_top - h) / 2.0)
		moves.size = Vector2(safe.size.x - 12.0, h)
		moves.autowrap_mode = TextServer.AUTOWRAP_OFF          # uma linha só (os lances mais novos)
		_style_moves(clampf(h * 0.42, 12.0, 17.0))
	return R(P_BOARD)

# ---------- DEITADO
func _layout_landscape(vs: Vector2, safe: Rect2) -> Rect2:
	# tabuleiro na altura inteira, no meio; as colunas laterais ficam com pelo menos 128 px
	var kf := minf(vs.y / F_SIZE.y, maxf(0.2, (vs.x - 2.0 * (128.0 + 20.0)) / F_SIZE.x))
	k = kf
	var frame := Rect2(Vector2(vs.x / 2.0 - F_SIZE.x * kf / 2.0, (vs.y - F_SIZE.y * kf) / 2.0), F_SIZE * kf)
	off = frame.position
	var kb := maxf(vs.x / L_W, vs.y / L_H)
	bg.mode = "l"
	bg.wood = wood
	bg.full = Rect2(Vector2.ZERO, vs)
	bg.top_rect = Rect2((vs - Vector2(L_W, L_H) * kb) / 2.0, Vector2(L_W, L_H) * kb)
	bg.frame_rect = frame
	bg.visible = true
	nav.hide()
	sheet.hide()
	# botões dos cantos (tamanho da referência, na escala da tela)
	var bs := clampf(vs.y * 0.115, 38.0, 54.0)
	_set_rect(corner.back, Rect2(safe.position + Vector2(0, 0), Vector2(bs, bs)))
	_set_rect(corner.chat, Rect2(Vector2(safe.end.x - bs, safe.position.y), Vector2(bs, bs)))
	_set_rect(corner.gear, Rect2(Vector2(safe.end.x - 2.0 * bs - 8.0, safe.position.y), Vector2(bs, bs)))
	var tab_h := clampf(vs.y * 0.42, 120.0, 190.0)
	var tab_w := tab_h * 86.0 / 294.0
	_set_rect(corner.tab, Rect2(Vector2(vs.x - tab_w, (vs.y - tab_h) / 2.0), Vector2(tab_w, tab_h)))
	corner.back.show()
	corner.gear.show()
	corner.tab.show()
	# cartões na coluna da esquerda: adversário em cima, jogador embaixo
	var col_x := safe.position.x
	var col_w := frame.position.x - 6.0 - col_x
	var s := clampf(col_w / 220.0, 0.6, 1.25)
	var ch := 160.0 * s
	var top_y := safe.position.y + bs + 6.0
	var rects := {"top": Rect2(col_x, top_y, col_w, ch), "bottom": Rect2(col_x, maxf(top_y + ch + 6.0, safe.end.y - ch), col_w, ch)}
	for key in ["top", "bottom"]:
		var c: Rect2 = rects[key]
		var p: Dictionary = plates[key]
		var pad := 10.0 * s
		var a := 54.0 * s
		var av := Rect2(c.position + Vector2(pad + 2.0 * s, pad + 2.0 * s), Vector2(a, a))
		var cb := Rect2(c.position.x + pad, av.end.y + 6.0 * s, c.size.x - 2.0 * pad, 44.0 * s)
		for n in p.values(): n.hide()
		p.card.show()
		p.clock.show()
		p.ring.show()
		_set_rect(p.card, c)
		_set_rect(p.clock, cb)
		var hg: TextureRect = p.clock.get_node("Hourglass")
		hg.position = Vector2(6.0 * s, 5.0 * s)
		hg.size = Vector2(28.0 * s, cb.size.y - 10.0 * s)
		_set_rect(p.ring, Rect2(av.get_center() - av.size * 0.66, av.size * 1.32))
		var nx := av.end.x + 8.0 * s
		var tw := c.end.x - pad - nx
		_skin_strip(key, c, av, true, Rect2(nx, av.position.y + 2.0 * s, tw, 26.0 * s), 19.0 * s,
			Rect2(nx, av.position.y + 30.0 * s, tw, 20.0 * s), 13.0 * s,
			Rect2(cb.position.x + 44.0 * s, cb.position.y + 2.0 * s, cb.size.x - 52.0 * s, cb.size.y - 4.0 * s), 30.0 * s,
			Rect2(c.position.x + pad + 4.0 * s, cb.end.y + 4.0 * s, c.size.x - 2.0 * pad - 8.0 * s, 18.0 * s))
	# painel AÇÕES: sai da aba da direita (por cima do tabuleiro enquanto aberto)
	_layout_panel_landscape(vs, safe, corner.tab.position.x)
	link = ui().link_label
	var rx := frame.end.x + 6.0
	link.position = Vector2(rx, safe.position.y + bs + 8.0)
	link.size = Vector2(maxf(60.0, corner.tab.position.x - rx - 6.0), 60.0)
	moves.visible = stage.mode == "bot"
	if moves.visible:
		moves.position = Vector2(rx + 4.0, safe.position.y + bs + 10.0)
		moves.size = Vector2(maxf(60.0, corner.tab.position.x - rx - 10.0), corner.tab.position.y - moves.position.y - 6.0)
		moves.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_moves(clampf(vs.y * 0.036, 11.0, 16.0))
	return Rect2(frame.position + F_BOARD.position * kf, F_BOARD.size * kf)

func _set_rect(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = r.size

## Faixa (cartão) da ranked_ui nos lugares do cartão da arte: só posição/tamanho/fonte; os dados são dela.
func _skin_strip(key: String, card: Rect2, avatar: Rect2, round: bool, name_r: Rect2, name_fs: float, sub_r: Rect2, sub_fs: float, clock_r: Rect2, clock_fs: float, mat_r: Rect2) -> void:
	var u = ui()
	if u == null: return
	var s: Dictionary = u.strips[key]
	var bgc: Control = s.bg
	_ov(bgc, "style", "panel", StyleBoxEmpty.new())
	_set_rect(bgc, card)
	_rec(s.plaque, "visible", false)
	var pt: Control = s.portrait
	_rec(pt, "top_level", true)
	_rec(pt, "custom_minimum_size", avatar.size)
	_set_rect(pt, avatar)
	var pbg = pt.get_node_or_null("PortraitBg")
	if pbg != null: _rec(pbg, "visible", not round)
	if pt.avatar_rect != null: _rec(pt.avatar_rect, "material", stage.board_skin._circle if round else null)
	for pair in [[s.name, name_r, name_fs, FONT_TITLE, Color("f6f1e6"), 4], [s.sub, sub_r, sub_fs, SkinRef.FONT_SEMI, Color("f3d27e"), 3]]:
		var l: Label = pair[0]
		_rec(l, "top_level", true)
		_rec(l, "autowrap_mode", TextServer.AUTOWRAP_OFF)
		_rec(l, "clip_text", true)
		_rec(l, "max_lines_visible", -1)
		_rec(l, "vertical_alignment", VERTICAL_ALIGNMENT_CENTER)
		_ov(l, "font", "font", pair[3])
		_ov(l, "size", "font_size", maxi(9, int(round(float(pair[2])))))
		_ov(l, "color", "font_color", pair[4])
		_ov(l, "const", "outline_size", int(pair[5]))
		_ov(l, "color", "font_outline_color", Color(0, 0, 0, 0.6))
		_set_rect(l, pair[1])
		l.set_meta("hud_fs", float(pair[2]))
	_rec(s.sub, "visible", true)
	# brasão da liga antes do texto da 2ª linha (o texto anda para a direita quando o brasão aparece)
	_rec(s.emblem, "top_level", true)
	_rec(s.emblem, "custom_minimum_size", Vector2(sub_r.size.y, sub_r.size.y))
	_set_rect(s.emblem, Rect2(sub_r.position, Vector2(sub_r.size.y, sub_r.size.y)))
	s.sub.set_meta("hud_rect", sub_r)
	_rec(s.seal, "top_level", true)
	s.seal.size = Vector2(name_r.size.y, name_r.size.y) * 0.8
	var ck = s.clock
	_rec(ck, "top_level", true)
	_rec(ck, "custom_minimum_size", clock_r.size)
	_set_rect(ck, clock_r)
	ck.set_bare(true)
	var cpx := int(round(clock_fs))
	while cpx > 10 and FONT_TITLE.get_string_size("00:00", HORIZONTAL_ALIGNMENT_LEFT, -1, cpx).x > clock_r.size.x - 4.0: cpx -= 1
	ck.set_font_size(cpx)
	while cpx > 10 and ck.get_combined_minimum_size().x > clock_r.size.x + 0.5:   # o rótulo do relógio tem margem própria
		cpx -= 1
		ck.set_font_size(cpx)
	_set_rect(ck, clock_r)
	var mh = stage.material_hud
	if mh != null:
		_rec(mh, "skin", true)
		_rec(mh, "compact", true)
		mh.skin_font = clampf(mat_r.size.y * 0.48, 10.0, 18.0)
		if key == "top": mh.top_rect = mat_r
		else: mh.bottom_rect = mat_r
		mh.queue_redraw()

# ------------------------------------------------------------------ chat
func _layout_chat(board: Rect2, safe: Rect2) -> void:
	var c = stage.match_chat
	if c == null or not c.active() or not c.open_mobile: return
	if orient == "p":
		var top := board.position.y
		var bottom := nav.position.y - 4.0
		c.panel.position = Vector2(safe.position.x, top)
		c.panel.size = Vector2(safe.size.x, maxf(160.0, bottom - top))
	else:
		var w := minf(420.0, safe.size.x * 0.5)
		c.panel.position = Vector2(corner.tab.position.x - w - 6.0, safe.position.y + 4.0)
		c.panel.size = Vector2(w, safe.size.y - 8.0)

## Botão da direita da barra: CHAT nas partidas online; contra o computador (sem chat) é LANCES.
func _third_pressed() -> void:
	if stage.mode == "bot":
		close_actions()
		sheet.visible = not sheet.visible
		if sheet.visible: _fill_sheet()
		return
	toggle_chat()

func _fill_sheet() -> void:
	var log: Array = stage.bot_controller.san_log
	var t := "[b][color=#f3d27e]LANCES[/color][/b]   [color=#a8a294](toque para fechar)[/color]\n"
	if log.is_empty(): t += "\n[color=#a8a294]A partida começa com as BRANCAS.[/color]"
	else:
		t += "[table=3]"
		for i in range(0, log.size(), 2):
			t += "[cell][color=#a8a294]%d.[/color]   [/cell][cell]%s      [/cell][cell]%s[/cell]" % [i / 2 + 1, String(log[i]).replace("[", "("), String(log[i + 1]).replace("[", "(") if i + 1 < log.size() else ""]
		t += "[/table]"
	sheet_text.text = t

func toggle_chat() -> void:
	var c = stage.match_chat
	if c == null or not c.active(): return
	close_actions()
	c.set_mobile_open(not c.open_mobile)

# ------------------------------------------------------------------ construção (uma vez)
func _build_plates() -> void:
	plate_layer = CanvasLayer.new()
	plate_layer.name = "MobileMatchPlates"
	plate_layer.layer = 39       # abaixo do material (40) e das faixas (45): o cartão é o fundo deles
	stage.add_child(plate_layer)
	for key in ["top", "bottom"]:
		var flat := TextureRect.new()                 # em pé (tema ≠ Madeira): o cartão inteiro da arte, na proporção dela
		flat.name = "HudCardFlat_" + key
		flat.texture = tex("card")
		flat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flat.stretch_mode = TextureRect.STRETCH_SCALE
		flat.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate_layer.add_child(flat)
		var box := TextureRect.new()
		box.name = "HudClockBoxFlat_" + key
		box.texture = tex("clockbox")
		box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		box.stretch_mode = TextureRect.STRETCH_SCALE
		box.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate_layer.add_child(box)
		var card := NinePatchRect.new()               # deitado: cartão que cresce (cantos da arte)
		card.name = "HudCard_" + key
		card.texture = tex("card")
		card.patch_margin_left = 24; card.patch_margin_right = 24; card.patch_margin_top = 20; card.patch_margin_bottom = 20
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		plate_layer.add_child(card)
		var clock := Panel.new()                      # deitado: caixa do relógio no estilo da arte + ampulheta
		clock.name = "HudClockBox_" + key
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("0b2418")
		sb.border_color = Color("c99a45")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 2
		clock.add_theme_stylebox_override("panel", sb)
		clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate_layer.add_child(clock)
		var hg := TextureRect.new()
		hg.name = "Hourglass"
		hg.texture = tex("ico_hourglass")
		hg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		hg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clock.add_child(hg)
		var ring := TextureRect.new()
		ring.name = "HudRing_" + key
		ring.texture = tex("ring")
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.stretch_mode = TextureRect.STRETCH_SCALE
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		plate_layer.add_child(ring)
		plates[key] = {"flat": flat, "box": box, "card": card, "clock": clock, "ring": ring}
		for n in plates[key].values(): n.hide()

func _hide_plates() -> void:
	for key in plates:
		for n in plates[key].values(): n.hide()

func _build_nav() -> void:
	nav = Control.new()
	nav.name = "HudNav"
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(nav)
	var art := TextureRect.new()
	art.name = "Art"
	art.texture = tex("p_nav")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_child(art)
	for spec in [["home", "INÍCIO", "ico_home"], ["actions", "AÇÕES", "ico_bars"], ["chat", "CHAT", "ico_chat"]]:
		var b := _flat_button("Hud_" + String(spec[0]))
		var ic := TextureRect.new()
		ic.name = "Icon"
		ic.texture = tex(String(spec[2]))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		var l := Label.new()
		l.name = "Caption"
		l.text = String(spec[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", FONT_TITLE)
		l.add_theme_color_override("font_color", Color("f6e7bf"))
		l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0, 0.85))
		l.add_theme_constant_override("outline_size", 3)
		b.add_child(l)
		var badge := Label.new()
		badge.name = "Badge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color("b3261e")
		bs.set_corner_radius_all(99)
		badge.add_theme_stylebox_override("normal", bs)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.hide()
		b.add_child(badge)
		nav.add_child(b)
		nav_buttons[spec[0]] = b
	nav_buttons.home.pressed.connect(_go_home)
	nav_buttons.actions.pressed.connect(toggle_actions)
	nav_buttons.chat.pressed.connect(_third_pressed)
	nav.hide()

func _fit_nav_button(b: Button) -> void:
	var ic: TextureRect = b.get_node("Icon")
	var l: Label = b.get_node("Caption")
	var h := b.size.y
	ic.position = Vector2(0, h * 0.14)
	ic.size = Vector2(b.size.x, h * 0.42)
	l.position = Vector2(0, h * 0.58)
	l.size = Vector2(b.size.x, h * 0.3)
	l.add_theme_font_size_override("font_size", maxi(10, int(round(h * 0.2))))
	var badge: Label = b.get_node("Badge")
	badge.add_theme_font_size_override("font_size", maxi(9, int(round(h * 0.15))))
	badge.size = Vector2(h * 0.28, h * 0.28)
	badge.position = Vector2(b.size.x * 0.68, h * 0.08)

func _build_corner() -> void:
	for spec in [["back", "l_back"], ["gear", "l_gear"], ["chat", "l_chat"], ["tab", "l_tab"]]:
		var b := _flat_button("HudCorner_" + String(spec[0]))
		var art := TextureRect.new()
		art.name = "Art"
		art.texture = tex(String(spec[1]))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(art)
		root.add_child(b)
		corner[spec[0]] = b
		b.hide()
	var badge := Label.new()
	badge.name = "Badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color("b3261e")
	bs.set_corner_radius_all(99)
	badge.add_theme_stylebox_override("normal", bs)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_font_size_override("font_size", 11)
	badge.size = Vector2(18, 18)
	badge.position = Vector2(-4, -4)
	badge.hide()
	corner.chat.add_child(badge)
	corner.back.pressed.connect(_go_home)
	corner.gear.pressed.connect(toggle_actions)      # opções da partida = o mesmo painel AÇÕES
	corner.chat.pressed.connect(toggle_chat)
	corner.tab.pressed.connect(toggle_actions)
	corner.gear.tooltip_text = "Opções da partida"
	corner.tab.tooltip_text = "Ações da partida"

func _flat_button(nm: String) -> Button:
	var b := Button.new()
	b.name = nm
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.button_down.connect(func(): b.modulate = Color(1.25, 1.18, 1.0))
	b.button_up.connect(func(): b.modulate = Color.WHITE)
	b.pressed.connect(func():
		var audio = stage.get_node_or_null("GameAudio")
		if audio != null: audio.play_cue("ui"))
	return b

func _go_home() -> void:
	close_actions()
	stage.home_button.pressed.emit()   # mesma confirmação de sempre (desistir/abandonar quando é o caso)

# ------------------------------------------------------------------ painel AÇÕES
func _build_panel() -> void:
	# camada própria acima das faixas dos jogadores (45): aberto, o painel recebe o toque mesmo por cima de um
	# cartão; resultado, confirmações e promoção fecham o painel (prioridade deles)
	panel_layer = CanvasLayer.new()
	panel_layer.name = "MobileMatchActions"
	panel_layer.layer = 46
	stage.add_child(panel_layer)
	panel = Control.new()
	panel.name = "HudActions"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_layer.add_child(panel)
	panel_art = NinePatchRect.new()
	panel_art.texture = tex("panel")
	panel_art.patch_margin_left = 60; panel_art.patch_margin_right = 60; panel_art.patch_margin_top = 90; panel_art.patch_margin_bottom = 40
	panel_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	panel.add_child(panel_art)
	var plaque := TextureRect.new()
	plaque.name = "Plaque"
	plaque.texture = tex("plaque")
	plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plaque.stretch_mode = TextureRect.STRETCH_SCALE
	plaque.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(plaque)
	var close := _flat_button("HudActionsClose")
	var ca := TextureRect.new()
	ca.texture = tex("close")
	ca.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ca.stretch_mode = TextureRect.STRETCH_SCALE
	ca.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ca.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ca.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	close.add_child(ca)
	close.pressed.connect(close_actions)
	panel.add_child(close)
	tiles_box = Control.new()
	tiles_box.name = "Tiles"
	tiles_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(tiles_box)
	# ações possíveis; cada uma aparece só quando existe naquela partida (refresh_actions)
	for id in ["resign", "mark", "analyze", "music", "fx", "mic", "ear", "leave", "full"]:
		var b := _flat_button("Action_" + id)
		var t := NinePatchRect.new()
		t.name = "Tile"
		t.texture = tex("tile")
		t.patch_margin_left = 18; t.patch_margin_right = 18; t.patch_margin_top = 18; t.patch_margin_bottom = 18
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(t)
		var ic := ActionIcon.new()
		ic.name = "Icon"
		ic.hud = self
		ic.id = id
		b.add_child(ic)
		var l := Label.new()
		l.name = "Caption"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", Kit.SERIF_BOLD)
		l.add_theme_color_override("font_color", Color("f3ead2"))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("outline_size", 3)
		l.add_theme_constant_override("line_spacing", -3)
		b.add_child(l)
		var aid: String = id
		b.pressed.connect(func(): _do_action(aid))
		tiles_box.add_child(b)
		tiles.append([b, id])
	panel.hide()

func panel_rect_for(n: int) -> Vector2:
	return Vector2(mini(4, maxi(1, n)), ceili(float(maxi(1, n)) / 4.0))

func _panel_base(safe: Rect2) -> Rect2:
	var h := P_PANEL.size.y * k
	return Rect2(Vector2(safe.position.x, nav.position.y + (1490.0 - P_NAV_Y) * k - h), Vector2(safe.size.x, h))

func _layout_panel_portrait(base: Rect2) -> void:
	var shown := _shown_tiles()
	var grid := panel_rect_for(shown.size())
	var rows := int(grid.y)
	var extra := (rows - 2) * (P_TILE.y + P_TILE_GAP.y) * k
	var r := Rect2(base.position - Vector2(0, maxf(0.0, extra)), base.size + Vector2(0, maxf(0.0, extra)))
	_set_rect(panel, r)
	panel_art.position = Vector2.ZERO
	panel_art.size = r.size
	var plaque: TextureRect = panel.get_node("Plaque")
	plaque.size = Vector2(274, 84) * k
	plaque.position = Vector2(r.size.x / 2.0 - plaque.size.x / 2.0, 0)
	var close: Button = panel.get_node("HudActionsClose")
	close.size = Vector2(84, 82) * k
	close.position = Vector2(r.size.x - close.size.x - 6.0 * k, 12.0 * k)
	var cols := int(grid.x)
	var gap := P_TILE_GAP * k
	# 4 ladrilhos por linha cabendo na largura (margens da moldura: 40 px da arte de cada lado)
	var tw := minf(P_TILE.x * k, (r.size.x - 80.0 * k - 3.0 * gap.x) / 4.0)
	var th := clampf((r.size.y - P_TILE_TOP * k - 28.0 * k - (rows - 1) * gap.y) / rows, tw * 0.62, tw * 1.05)
	var x0 := (r.size.x - (cols * tw + (cols - 1) * gap.x)) / 2.0
	_place_tiles(shown, Vector2(x0, P_TILE_TOP * k), Vector2(tw, th), gap, cols)

func _layout_panel_landscape(vs: Vector2, safe: Rect2, right: float) -> void:
	var shown := _shown_tiles()
	var grid := panel_rect_for(shown.size())
	var cols := int(grid.x)
	var rows := int(grid.y)
	var th := clampf((safe.size.y - 70.0) / 2.6, 58.0, 86.0)
	var tw := th * P_TILE.x / P_TILE.y
	var gap := Vector2(8, 8)
	var head := th * 0.62
	var w := cols * tw + (cols - 1) * gap.x + 40.0
	var h := head + rows * th + (rows - 1) * gap.y + 22.0
	h = minf(h, safe.size.y)
	var r := Rect2(Vector2(maxf(safe.position.x, right - w - 4.0), safe.position.y + (safe.size.y - h) / 2.0), Vector2(w, h))
	_set_rect(panel, r)
	panel_art.position = Vector2.ZERO
	panel_art.size = r.size
	var plaque: TextureRect = panel.get_node("Plaque")
	plaque.size = Vector2(274, 84) * (head / 84.0) * 1.1
	plaque.position = Vector2(r.size.x / 2.0 - plaque.size.x / 2.0, -plaque.size.y * 0.18)
	var close: Button = panel.get_node("HudActionsClose")
	close.size = Vector2(head, head) * 0.9
	close.position = Vector2(r.size.x - close.size.x - 6.0, 4.0)
	_place_tiles(shown, Vector2(20.0, head), Vector2(tw, th), gap, cols)

func _place_tiles(shown: Array, origin: Vector2, size: Vector2, gap: Vector2, cols: int) -> void:
	for t in tiles: t[0].visible = false
	for i in shown.size():
		var b: Button = shown[i]
		b.visible = true
		b.position = origin + Vector2(i % cols, i / cols) * (size + gap)
		b.size = size
		var ic: Control = b.get_node("Icon")
		ic.position = Vector2(size.x * 0.3, size.y * 0.1)
		ic.size = Vector2(size.x * 0.4, size.y * 0.44)
		var l: Label = b.get_node("Caption")
		l.position = Vector2(4, size.y * 0.54)
		l.size = Vector2(size.x - 8, size.y * 0.42)
		var fs := maxi(10, int(round(size.y * 0.17)))
		while fs > 9 and Kit.SERIF_BOLD.get_string_size(l.text.split("\n")[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 10: fs -= 1
		l.add_theme_font_size_override("font_size", fs)

## As ações que existem AGORA nesta partida: a fonte da verdade são os botões antigos do celular (as mesmas
## regras de visibilidade de sempre: _process e _refresh_analysis_buttons do stage) e o controle de voz.
func _available() -> Dictionary:
	var st = stage
	var mv = st.mobile_voice
	var voice_on: bool = mv != null and mv.visible
	return {
		"resign": st.mobile_restart != null and st.mobile_restart.visible,
		"mark": st.mobile_mark != null and st.mobile_mark.visible,
		"analyze": st.mobile_analyze != null and st.mobile_analyze.visible,
		"music": true, "fx": true,
		"mic": voice_on,
		"ear": voice_on and mv.ear.visible,
		"leave": voice_on and mv.off.visible,
		"full": st.mobile_fullscreen != null and st.mobile_fullscreen.visible,
	}

func _caption(id: String) -> String:
	var st = stage
	match id:
		"resign":
			if st.mode == "bot" and st.game.game_over: return "Jogar de novo"
			return "Desistir" if st.mode in ["ranked", "casual"] or (st.mode == "bot" and st.bot_controller.in_match()) else "Reiniciar"
		"mark": return "Marcar /\nRevisar"
		"analyze": return "Analisar"
		"music": return "Música" + (": NÃO" if ModeSound.music_muted(st.hub) else "")
		"fx": return "Efeitos" + (": NÃO" if ModeSound.effects_muted(st.hub) else "")
		"mic":
			var vs: String = String(st.voice.state) if st.voice != null else ""
			return {"CONNECTED": "Microfone", "MUTED": "Microfone:\nmudo", "ERROR": "Voz: tentar\nde novo"}.get(vs, "Entrar\nna voz")
		"ear": return "Ouvir voz" + (": NÃO" if st.voice != null and st.voice.speaker_muted else "")
		"leave": return "Sair da voz"
		"full": return "Tela cheia"
	return id

func _shown_tiles() -> Array:
	var av := _available()
	var out := []
	for t in tiles:
		var b: Button = t[0]
		var id: String = t[1]
		if av.get(id, false):
			var l: Label = b.get_node("Caption")
			var cap := _caption(id)
			if l.text != cap: l.text = cap
			out.append(b)
	return out

func _do_action(id: String) -> void:
	var st = stage
	var mv = st.mobile_voice
	match id:
		"resign":
			close_actions()
			st.mobile_restart.pressed.emit()
		"mark":
			st.mobile_mark.pressed.emit()
		"analyze":
			close_actions()
			st.mobile_analyze.pressed.emit()
		"music": ModeSound.toggle_music(st.hub)
		"fx": ModeSound.toggle_effects(st.hub)
		"mic": if mv != null: mv.mic.pressed.emit()
		"ear": if mv != null: mv.ear.pressed.emit()
		"leave": if mv != null: mv.off.pressed.emit()
		"full": st.mobile_fullscreen.pressed.emit()
	refresh_actions()

func is_open() -> bool:
	return panel.visible

func open() -> void:
	if not on: return
	var c = stage.match_chat
	if c != null and c.open_mobile: c.set_mobile_open(false)
	sheet.hide()
	panel.set_meta("opened_over", stage.game.game_over)   # aberto já no fim (jogar de novo / analisar): fica
	panel.show()
	refresh_actions()

func close_actions() -> void:
	if panel != null: panel.hide()
	_key = ""

func toggle_actions() -> void:
	if panel.visible: close_actions()
	else: open()

## Refaz os ladrilhos do painel (estado de som, voz, desistir/jogar de novo) — no toque, nunca por quadro.
func refresh_actions() -> void:
	if not on: return
	var vp: Viewport = stage.get_viewport()
	if orient == "p":
		_layout_panel_portrait(_panel_base(MobileLayout.safe_rect(vp)))
	elif orient == "l":
		_layout_panel_landscape(vp.get_visible_rect().size, MobileLayout.safe_rect(vp), corner.tab.position.x)
	for t in tiles:
		var ic: Control = t[0].get_node("Icon")
		ic.queue_redraw()
	if orient == "p":
		nav_buttons.actions.get_node("Icon").modulate = Color(1.3, 1.2, 1.0) if panel.visible else Color.WHITE

# ------------------------------------------------------------------ a cada quadro (barato: só confere mudanças)
func _process(_d) -> void:
	if stage == null: return
	# entrou/saiu de uma partida no celular, ou o tema mudou: o layout do stage refaz tudo (1 vez)
	if wanted() != on or (on and (String(stage.game.visual_theme) == "wood") != wood):
		stage._layout()
		return
	if not on: return
	var st = stage
	# resultado/fim/promoção têm prioridade: o painel AÇÕES fecha sozinho
	if panel.visible:
		var u = ui()
		var res_up: bool = st.result_overlay != null and st.result_overlay.is_showing()
		var ui_up: bool = u != null and u.panel_open()
		var over: bool = st.game.game_over and not panel.get_meta("opened_over", false)
		if res_up or ui_up or st.game.promotion_pending or over:
			close_actions()
	var c = st.match_chat
	var chat_on: bool = c != null and c.active()
	var unread: int = int(c.unread) if chat_on else 0
	var key := "%s|%s|%s|%s|%s|%s" % [chat_on, unread, st.game.game_over, _available(), ModeSound.music_muted(st.hub), ModeSound.effects_muted(st.hub)]
	if key != _key:
		_key = key
		if orient == "p":
			nav_buttons.chat.visible = chat_on or st.mode == "bot"
			var nb: Label = nav_buttons.chat.get_node("Badge")
			nb.visible = unread > 0
			nb.text = str(unread)
		else:
			corner.chat.visible = chat_on
			var cb: Label = corner.chat.get_node("Badge")
			cb.visible = unread > 0
			cb.text = str(unread)
		if panel.visible: refresh_actions()
	if st.mode == "bot" and st.bot_controller.san_log.size() != _moves_n:
		_moves_n = st.bot_controller.san_log.size()
		moves.text = _moves_line(st.bot_controller.san_log)
		if sheet.visible: _fill_sheet()
	_keep_strips()

## Textos vivos maiores que a caixa da arte encolhem até caber; o selo vem logo depois do nome; o texto da 2ª
## linha anda para a direita quando o brasão da liga aparece. Só quando o texto muda.
func _keep_strips() -> void:
	var u = ui()
	if u == null: return
	for key in ["top", "bottom"]:
		var s: Dictionary = u.strips[key]
		var pt = s.portrait
		if pt.frame_node != null and pt.frame_node.visible: pt.frame_node.visible = false
		if pt.seal_rect.visible: pt.seal_rect.visible = false
		var nm: Label = s.name
		var sub: Label = s.sub
		var sig := "%s|%s|%s|%s" % [nm.text, sub.text, s.emblem.visible, s.seal.visible]
		if _texts.get(key, "") == sig: continue
		_texts[key] = sig
		_fit(nm, FONT_TITLE)
		var sr: Rect2 = sub.get_meta("hud_rect", Rect2(sub.position, sub.size))
		var shift: float = sr.size.y + 4.0 if s.emblem.visible else 0.0
		sub.position = sr.position + Vector2(shift, 0)
		sub.size = Vector2(sr.size.x - shift, sr.size.y)
		_fit(sub, SkinRef.FONT_SEMI)
		var px := nm.get_theme_font_size("font_size")
		var w := minf(FONT_TITLE.get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x, nm.size.x)
		s.seal.position = nm.position + Vector2(w + 6.0, (nm.size.y - s.seal.size.y) / 2.0)

func _fit(l: Label, font: Font) -> void:
	var want := maxi(9, int(round(float(l.get_meta("hud_fs", 16.0)))))
	var px := want
	while px > 9 and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > l.size.x - 2.0: px -= 1
	if l.get_theme_font_size("font_size") != px: l.add_theme_font_size_override("font_size", px)

func _style_moves(fs: float) -> void:
	moves.add_theme_font_size_override("normal_font_size", int(round(fs)))
	moves.add_theme_font_size_override("bold_font_size", int(round(fs + 1.0)))
	_moves_n = -1

func _moves_line(log: Array) -> String:
	var t := "[b][color=#f3d27e]LANCES[/color][/b]   "
	if log.is_empty(): return t + "[color=#a8a294]a partida começa com as BRANCAS[/color]"
	var many := 10 if orient == "l" else 6
	var first := maxi(0, log.size() - many)
	if first % 2 == 1: first -= 1
	if orient == "l": t = "[b][color=#f3d27e]LANCES[/color][/b]\n"
	for i in range(first, log.size()):
		if i % 2 == 0: t += "[color=#a8a294]%d.[/color] " % (i / 2 + 1)
		t += String(log[i]).replace("[", "(").replace("]", ")") + ("\n" if orient == "l" and i % 2 == 1 else "  ")
	return t

# ------------------------------------------------------------------ desenho
## Fundo: a arte da referência atrás do tabuleiro (z −15). Em pé: chão da floresta cobrindo a tela e a arte
## (cartões + tabuleiro) por cima; deitado: o cenário da referência cobrindo a tela e a moldura do tabuleiro no meio.
class BgArt extends Node2D:
	var mode := "p"
	var wood := true
	var full := Rect2()
	var top_rect := Rect2()
	var frame_rect := Rect2()
	var _fill: Texture2D = load("res://ranked/art/mob_hud_fill.png")
	var _top: Texture2D = load("res://ranked/art/mob_hud_p_top.png")
	var _land: Texture2D = load("res://ranked/art/mob_hud_l_art.png")
	var _frame: Texture2D = load("res://ranked/art/mob_hud_frame.png")
	func _draw():
		if mode == "p":
			if wood:
				var ts := _fill.get_size()
				var s := maxf(full.size.x / ts.x, full.size.y / ts.y)
				draw_texture_rect(_fill, Rect2((full.size - ts * s) / 2.0, ts * s), false, Color(0.8, 0.84, 0.8))
				draw_texture_rect(_top, top_rect, false)
			return
		if wood:
			draw_texture_rect(_land, top_rect, false)
			draw_texture_rect(_frame, frame_rect, false)

## Ícone de um ladrilho do painel AÇÕES: os ícones da arte; os que a arte não tem (jogar de novo, analisar,
## fone, sair da voz) são desenhados no mesmo dourado. Estado desligado = ícone apagado + risco.
class ActionIcon extends Control:
	var hud
	var id := ""
	var _tex := {}
	func _init():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _icon(n: String) -> Texture2D:
		if not _tex.has(n): _tex[n] = load("res://ranked/art/mob_hud_ico_%s.png" % n)
		return _tex[n]
	func _draw():
		if hud == null: return
		var st = hud.stage
		var r := Rect2(Vector2.ZERO, size)
		var col := Color("f2c66d")
		var off := false
		match id:
			"resign":
				if st.mode == "bot" and st.game.game_over: _restart(r, col)
				else: _tex_in(_icon("flag"), r)
			"mark": _tex_in(_icon("mark"), r)
			"analyze": _magnifier(r, col)
			"music":
				off = ModeSound.music_muted(st.hub)
				_tex_in(_icon("music"), r, off)
			"fx":
				off = ModeSound.effects_muted(st.hub)
				_tex_in(_icon("fx"), r, off)
			"mic":
				off = st.voice != null and String(st.voice.state) != "CONNECTED"
				_tex_in(_icon("mic"), r, off)
			"ear":
				VoiceGlyph.draw_headphones(self, _square(r), st.voice != null and st.voice.speaker_muted, col)
			"leave":
				var q := _square(r).grow(-r.size.y * 0.1)
				draw_line(q.position, q.end, col, maxf(2.0, r.size.y * 0.08))
				draw_line(Vector2(q.position.x, q.end.y), Vector2(q.end.x, q.position.y), col, maxf(2.0, r.size.y * 0.08))
			"full": _tex_in(_icon("full"), r)
		if off:
			var q := _square(r)
			draw_line(q.position + q.size * 0.15, q.end - q.size * 0.15, Color("e0614b"), maxf(2.0, r.size.y * 0.08))
	func _square(r: Rect2) -> Rect2:
		var s := minf(r.size.x, r.size.y)
		return Rect2(r.get_center() - Vector2(s, s) / 2.0, Vector2(s, s))
	func _tex_in(t: Texture2D, r: Rect2, dim := false):
		if t == null: return
		var ts := t.get_size()
		var s := minf(r.size.x / ts.x, r.size.y / ts.y)
		draw_texture_rect(t, Rect2(r.get_center() - ts * s / 2.0, ts * s), false, Color(0.55, 0.55, 0.55) if dim else Color.WHITE)
	func _restart(r: Rect2, col: Color):
		var c := r.get_center()
		var rad := minf(r.size.x, r.size.y) * 0.36
		var w := maxf(2.0, rad * 0.2)
		draw_arc(c, rad, deg_to_rad(-70), deg_to_rad(220), 24, col, w)
		var e := c + Vector2(cos(deg_to_rad(-70)), sin(deg_to_rad(-70))) * rad
		draw_colored_polygon(PackedVector2Array([e + Vector2(-rad * 0.45, -rad * 0.15), e + Vector2(rad * 0.2, -rad * 0.5), e + Vector2(rad * 0.12, rad * 0.3)]), col)
	func _magnifier(r: Rect2, col: Color):
		var c := r.get_center()
		var rad := minf(r.size.x, r.size.y) * 0.3
		draw_arc(c - Vector2(rad, rad) * 0.25, rad, 0, TAU, 28, col, maxf(2.0, rad * 0.22))
		draw_line(c + Vector2(rad, rad) * 0.45, c + Vector2(rad, rad) * 1.2, col, maxf(3.0, rad * 0.32))
