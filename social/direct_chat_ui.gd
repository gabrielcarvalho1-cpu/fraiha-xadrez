extends CanvasLayer
## R177 · CHAT EXCLUSIVO — canal direto com o administrador (arte do dono: social/art/dchat/frame.png).
## O dono abre pelo Admin → Chat Exclusivo; a janela aparece na hora, em qualquer tela (lobby, partida, menus).
## O jogador conversa, manda emotes e mensagens rápidas (+), e recebe PRESENTES (Coroas ou itens da Loja) que já
## entram na conta. Fechar (X) só esconde: uma mensagem nova do administrador reabre. Servidor: online_v021/support/direct_chat.js
signal opened
signal closed

const REF := Vector2(1448, 1086)
const FRAME := preload("res://social/art/dchat/frame.png")
const ADMIN_AV := preload("res://social/art/dchat/admin_avatar.png")
const PLAYER_AV := preload("res://social/art/dchat/player_avatar.png")
const CROWN := preload("res://social/art/dchat/crown.png")
const FONT_T := preload("res://account/fonts/Cinzel-Bold.woff")
const SERIF := preload("res://ui_kit/fonts/Alegreya-Medium.woff")
const SERIF_B := preload("res://ui_kit/fonts/Alegreya-Bold.woff")
const ShopCatalog := preload("res://economy/crown_store_catalog.gd")
const Cosmetics := preload("res://profile/premium_cosmetics.gd")
const GOLD := Color("f2c75c")
const CREAM := Color("efe4cc")
const MUTED := Color("a99c80")
const TEAL_TXT := Color("e6f6ef")
const QUICK := ["Obrigado!", "Tenho uma dúvida", "Encontrei um problema", "Tudo certo por aqui!", "Pode me ajudar?"]

# regiões da arte (coordenadas da imagem 1448x1086)
const R_CLOSE := Rect2(1289, 155, 76, 76)
const R_PROFILE := Rect2(143, 692, 297, 76)
const R_CHANNEL := Rect2(143, 780, 297, 76)
const R_LIST := Rect2(496, 300, 800, 520)
const R_PLUS := Rect2(480, 857, 66, 66)
const R_INPUT := Rect2(580, 866, 546, 48)
const R_EMOJI := Rect2(1132, 864, 54, 54)
const R_SEND := Rect2(1212, 850, 84, 84)
const R_POP := Rect2(500, 600, 520, 240)   # menus (+ e emotes) abrem por cima da lista, perto do campo

var account
var stage
var hub
var chat := {}
var messages: Array = []
var is_open := false
var ended := false
var k := 1.0
var src := Rect2(Vector2.ZERO, REF)
var origin := Vector2.ZERO
var portrait := false

var root: Control
var dim: ColorRect
var art: TextureRect
var scroll: ScrollContainer
var list: VBoxContainer
var input: LineEdit
var hits := {}
var pop: PanelContainer
var pop_box: Container
var pop_kind := ""
var info: PanelContainer
var status: Label
var _frame_tex: Texture2D
var _portrait: Texture2D
## celular em pé: a arte perde o painel da esquerda (Fraiha / Ver Perfil / Canal Oficial) e a borda esquerda é
## costurada no lugar (0..110 da arte + 440..1448), com emenda suave. Coordenadas: x da arte − 330.
const P_LEFT := 110
const P_CUT := 440
const PORTRAIT_SHIFT := P_CUT - P_LEFT

func _src_image() -> Image:
	var img: Image = FRAME.get_image()
	if img == null: return null
	img = img.duplicate()
	if img.is_compressed(): img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8: img.convert(Image.FORMAT_RGBA8)
	return img

func _land_tex() -> Texture2D:
	if _frame_tex == null:
		var img := _src_image()
		if img == null: _frame_tex = FRAME
		else:
			img.generate_mipmaps()
			_frame_tex = ImageTexture.create_from_image(img)
	return _frame_tex

func _portrait_tex() -> Texture2D:
	if _portrait == null:
		var img := _src_image()
		if img == null: return _land_tex()
		var w := P_LEFT + (int(REF.x) - P_CUT)
		var out := Image.create(w, int(REF.y), false, Image.FORMAT_RGBA8)
		out.blit_rect(img, Rect2i(P_CUT, 0, int(REF.x) - P_CUT, int(REF.y)), Vector2i(P_LEFT, 0))
		var feather := 26
		var left := img.get_region(Rect2i(0, 0, P_LEFT + feather, int(REF.y)))
		for x in range(P_LEFT, P_LEFT + feather):
			var f := 1.0 - float(x - P_LEFT + 1) / float(feather + 1)
			for y in int(REF.y):
				var c := left.get_pixel(x, y)
				c.a *= f
				left.set_pixel(x, y, c)
		out.blend_rect(left, Rect2i(0, 0, P_LEFT + feather, int(REF.y)), Vector2i.ZERO)
		out.generate_mipmaps()
		_portrait = ImageTexture.create_from_image(out)
	return _portrait

func setup(p_stage, acc):
	stage = p_stage
	account = acc
	hub = p_stage.get("hub") if p_stage != null else null
	if account != null and account.has_signal("server_message"): account.server_message.connect(_on_message)

func _ready():
	layer = 110
	name = "DirectChat"
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "DirectChatRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _close_pop())
	root.add_child(dim)
	art = TextureRect.new()
	art.name = "DirectChatArt"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(art)
	scroll = ScrollContainer.new()
	scroll.name = "DirectChatScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	root.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "DirectChatList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	input = LineEdit.new()
	input.name = "DirectChatInput"
	input.placeholder_text = "Digite sua mensagem..."
	input.max_length = 1000
	input.flat = true
	input.context_menu_enabled = false
	input.add_theme_font_override("font", SERIF)
	input.add_theme_color_override("font_color", CREAM)
	input.add_theme_color_override("font_placeholder_color", Color(0.85, 0.80, 0.70, 0.62))
	input.add_theme_color_override("caret_color", GOLD)
	for st in ["normal", "focus", "read_only"]: input.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	input.text_submitted.connect(func(_t): send_current())
	root.add_child(input)
	for id in ["close", "profile", "channel", "plus", "emoji", "send"]:
		var b := Button.new()
		b.name = "DirectChat_" + id
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var hv := StyleBoxFlat.new()
		hv.bg_color = Color(1.0, 0.86, 0.45, 0.10)
		hv.set_corner_radius_all(40 if id in ["close", "plus", "emoji", "send"] else 14)
		b.add_theme_stylebox_override("hover", hv)
		root.add_child(b)
		hits[id] = b
	hits.close.tooltip_text = "Minimizar · a conversa fica no botão CHAT EXCLUSIVO no canto da tela"
	hits.profile.tooltip_text = "Ver perfil · sobre o administrador"
	hits.channel.tooltip_text = "Canal oficial · novidades e avisos"
	hits.plus.tooltip_text = "Mensagens rápidas"
	hits.emoji.tooltip_text = "Emotes"
	hits.send.tooltip_text = "Enviar"
	hits.close.pressed.connect(minimize)
	hits.send.pressed.connect(send_current)
	hits.plus.pressed.connect(func(): _toggle_pop("quick"))
	hits.emoji.pressed.connect(func(): _toggle_pop("emotes"))
	hits.profile.pressed.connect(_toggle_info)
	hits.channel.pressed.connect(_open_channel)
	status = Label.new()
	status.name = "DirectChatStatus"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_font_override("font", SERIF_B)
	status.add_theme_color_override("font_color", Color("ffb59a"))
	status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	status.add_theme_constant_override("outline_size", 4)
	root.add_child(status)
	visible = false
	get_viewport().size_changed.connect(func(): if visible: _layout())
	_build_pill()

func _input(e: InputEvent):
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if pop != null and pop.visible: _close_pop()
		elif info != null and info.visible: info.hide()
		else: minimize()

# ---------------------------------------------------------------- mensagens do servidor
func _on_message(m: Dictionary):
	var t := String(m.get("type", ""))
	if not t.begins_with("dchat_"): return
	match t:
		"dchat_open":
			chat = m.get("chat", {}) if m.get("chat") is Dictionary else {}
			var before := messages.size()
			messages = Array(chat.get("messages", [])) if chat.get("messages") is Array else []
			ended = not bool(chat.get("open", true))
			if minimized and not _reopening:
				# R177c · minimizado pelo jogador: a mensagem nova NÃO abre a janela no meio do jogo — o botão do canto
				# mostra quantas chegaram e pisca; tocar nele abre
				for i in range(before, messages.size()):
					if String(messages[i].get("from", "")) == "admin":
						unread += 1
						_ding(messages[i])
				_refresh_pill()
				return
			_reopening = false
			show_chat()
		"dchat_msg":
			var msg = m.get("msg")
			if not (msg is Dictionary): return
			for x in messages: if int(x.get("id", -1)) == int(msg.get("id", -2)): return
			messages.append(msg)
			if minimized:
				if String(msg.get("from", "")) == "admin": unread += 1
				_refresh_pill()
			elif not is_open and String(msg.get("from", "")) == "admin": show_chat()
			else: _add_row(msg, true)
			if String(msg.get("from", "")) == "admin": _ding(msg)
		"dchat_closed":
			ended = true
			messages.append({"id": -1, "from": "system", "text": "O administrador encerrou o chat. Obrigado pela conversa!", "ts": ""})
			if is_open: _add_row(messages[-1], true)
			_refresh_enabled()
			minimized = false
			_refresh_pill()
		"dchat_error":
			_flash(String(m.get("message", "Não foi possível enviar.")))
			if String(m.get("code", "")) == "not_open":
				ended = true
				_refresh_enabled()

func _ding(msg: Dictionary):
	if stage == null: return
	var snd = load("res://audio_v025/padrao/movimento.mp3") if msg.get("gift") == null else null
	if msg.get("gift") is Dictionary and ResourceLoader.exists("res://audio_v025/padrao/fim_partida.mp3"): snd = load("res://audio_v025/padrao/fim_partida.mp3")
	if snd != null: preload("res://ui_v022/mode_sound.gd").play(stage, snd, -6.0, 1.15)

# ---------------------------------------------------------------- abrir / fechar
## R177c · X / ESC: a conversa NÃO some — vira o botão "CHAT EXCLUSIVO" no canto da tela (perto do COMUNIDADE).
## Tocar nele abre de novo. Chat encerrado pelo administrador: aí sim o X fecha de vez.
var minimized := false
var unread := 0
var _reopening := false
var pill_layer: CanvasLayer
var pill: Button
var pill_badge: Label

func minimize():
	if ended:
		hide_chat()
		return
	hide_chat()
	minimized = true
	unread = 0
	_refresh_pill()

func reopen():
	minimized = false
	unread = 0
	_refresh_pill()
	_reopening = true
	show_chat()
	if account != null and account.has_method("send_server"): account.send_server({"type": "dchat_get"})

func _build_pill():
	pill_layer = CanvasLayer.new()
	pill_layer.layer = 109
	pill_layer.name = "DirectChatPillLayer"
	add_sibling.call_deferred(pill_layer)
	pill = Button.new()
	pill.name = "DirectChatPill"
	pill.text = "CHAT EXCLUSIVO"
	pill.icon = CROWN
	pill.expand_icon = false
	pill.focus_mode = Control.FOCUS_NONE
	pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pill.tooltip_text = "Chat exclusivo · conversa com o administrador"
	pill.add_theme_font_override("font", FONT_T)
	pill.add_theme_color_override("font_color", GOLD)
	pill.add_theme_color_override("font_hover_color", Color("fff1c8"))
	pill.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	pill.add_theme_constant_override("outline_size", 3)
	pill.add_theme_constant_override("h_separation", 8)
	for pair in [["normal", Color("0b1730")], ["hover", Color("142650")], ["pressed", Color("081022")], ["focus", Color("0b1730")]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = pair[1]
		sb.border_color = Color("e0b64a")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		sb.shadow_color = Color(0, 0, 0, 0.55)
		sb.shadow_size = 8
		sb.content_margin_left = 12
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		pill.add_theme_stylebox_override(pair[0], sb)
	pill.pressed.connect(reopen)
	pill_layer.add_child(pill)
	pill_badge = Label.new()
	pill_badge.name = "DirectChatPillBadge"
	pill_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill_badge.add_theme_font_override("font", SERIF_B)
	pill_badge.add_theme_color_override("font_color", Color.WHITE)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color("c4161f")
	bs.border_color = Color("ffd98a")
	bs.set_border_width_all(2)
	bs.set_corner_radius_all(14)
	pill_badge.add_theme_stylebox_override("normal", bs)
	pill_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(pill_badge)
	pill.hide()
	get_viewport().size_changed.connect(_place_pill)

func _refresh_pill():
	if pill == null: return
	pill.visible = minimized and not ended
	pill_badge.visible = unread > 0
	pill_badge.text = str(unread)
	_place_pill()

## perto do botão COMUNIDADE (lobby do PC); sem ele na tela (partidas, celular), canto de baixo à direita
func _place_pill():
	if pill == null or not pill.visible: return
	var vs := get_viewport().get_visible_rect().size
	var mob := vs.y > vs.x or vs.y < 520.0
	var fs := 15 if mob else 17
	pill.add_theme_font_size_override("font_size", fs)
	pill_badge.add_theme_font_size_override("font_size", fs - 2)
	pill.reset_size()
	var sz := pill.get_combined_minimum_size()
	pill.size = sz
	var pos := Vector2(vs.x - sz.x - 12.0, vs.y * (0.80 if vs.y > vs.x else 0.70))
	var cb = get_tree().root.find_child("CommunityButton", true, false) if get_tree() != null else null
	if cb is Control and (cb as Control).is_visible_in_tree():
		var r: Rect2 = (cb as Control).get_global_transform_with_canvas() * Rect2(Vector2.ZERO, (cb as Control).size)
		pos = Vector2(r.end.x - sz.x, r.position.y - sz.y - 10.0)
	pos.x = clampf(pos.x, 6.0, vs.x - sz.x - 6.0)
	pos.y = clampf(pos.y, 6.0, vs.y - sz.y - 6.0)
	pill.position = pos
	var bh := float(fs) + 10.0
	pill_badge.size = Vector2(maxf(bh, pill_badge.get_minimum_size().x + 8.0), bh)
	pill_badge.position = Vector2(sz.x - pill_badge.size.x * 0.6, -bh * 0.45)

func _process(_d):
	if pill != null and pill.visible:
		_place_pill()
		var a := 1.0
		if unread > 0: a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 220.0)
		pill.modulate = Color(1, 1, 1, a)

func show_chat():
	if pill != null and minimized:
		minimized = false
		unread = 0
		_refresh_pill()
	if not visible:
		visible = true
		is_open = true
		opened.emit()
	_close_pop()
	if info != null: info.hide()
	_layout()
	_rebuild()
	_refresh_enabled()

func hide_chat():
	if not visible: return
	visible = false
	is_open = false
	if input.has_focus(): input.release_focus()
	if not ended and account != null and account.has_method("send_server"): account.send_server({"type": "dchat_hide"})
	closed.emit()

func _refresh_enabled():
	input.editable = not ended
	input.placeholder_text = "Chat encerrado" if ended else "Digite sua mensagem..."
	for id in ["plus", "emoji", "send"]: hits[id].disabled = ended

func send_current():
	var t := input.text.strip_edges()
	if t.is_empty() or ended: return
	if account == null or not account.has_method("send_server"): return
	account.send_server({"type": "dchat_send", "text": t})
	input.text = ""
	_close_pop()

func send_emote(id: String, label: String):
	if ended or account == null: return
	account.send_server({"type": "dchat_send", "emote": id, "text": label})
	_close_pop()

func _flash(t: String):
	status.text = t
	status.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(status, "modulate:a", 0.0, 0.6)

# ---------------------------------------------------------------- layout (a arte escala inteira; celular em pé corta o painel da esquerda)
func R(r: Rect2) -> Rect2:
	return Rect2(origin + (r.position - src.position) * k, r.size * k)

func _layout():
	var vs := get_viewport().get_visible_rect().size
	portrait = vs.y > vs.x * 1.05
	src = Rect2(PORTRAIT_SHIFT, 0, REF.x - PORTRAIT_SHIFT, REF.y) if portrait else Rect2(Vector2.ZERO, REF)
	k = minf(vs.x * (0.99 if portrait else 0.94) / src.size.x, vs.y * 0.94 / src.size.y)
	if not portrait: k = minf(k, 1.15)
	origin = (vs - src.size * k) / 2.0
	var tex := _portrait_tex() if portrait else _land_tex()
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(Vector2.ZERO, tex.get_size())
	art.texture = at
	art.position = origin
	art.size = src.size * k
	var lr := R(R_LIST)
	scroll.position = lr.position
	scroll.size = lr.size
	var ir := R(R_INPUT)
	input.position = ir.position
	input.size = ir.size
	input.add_theme_font_size_override("font_size", int(round(26 * k * _boost())))
	var regions := {"close": R_CLOSE, "profile": R_PROFILE, "channel": R_CHANNEL, "plus": R_PLUS, "emoji": R_EMOJI, "send": R_SEND}
	for id in hits:
		var r: Rect2 = regions[id]
		hits[id].position = R(r).position
		hits[id].size = R(r).size
	hits.profile.visible = not portrait
	hits.channel.visible = not portrait
	status.position = Vector2(lr.position.x, lr.end.y - 40 * k * _boost())
	status.size = Vector2(lr.size.x, 36 * k * _boost())
	status.add_theme_font_size_override("font_size", int(round(22 * k * _boost())))
	if info != null and info.visible: _place_info()
	if pop != null and pop.visible: _place_pop()

## celular em pé: letras maiores (a arte fica pequena)
func _boost() -> float:
	return 1.45 if portrait else 1.0

# ---------------------------------------------------------------- lista de mensagens
func _rebuild():
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	list.add_theme_constant_override("separation", int(16 * k * _boost()))
	if messages.is_empty():
		var l := _label("O administrador abriu um canal direto com você. Pode falar!", 22, MUTED, SERIF)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(scroll.size.x - 20, 0)
		l.name = "DirectChatEmpty"
		list.add_child(l)
	for m in messages: _add_row(m, false)
	_scroll_end()

func _label(t: String, px: float, col: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", int(round(px * k * _boost())))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _hour(ts: String) -> String:
	# "2026-10-22T14:28:00.000Z" → hora local
	if ts.length() < 16: return ""
	var unix := Time.get_unix_time_from_datetime_string(ts.substr(0, 19))
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + bias * 60)
	return "%02d:%02d" % [int(d.hour), int(d.minute)]

func _add_row(m: Dictionary, scroll_now: bool):
	var empty := list.get_node_or_null("DirectChatEmpty")
	if empty != null: empty.queue_free()
	var from := String(m.get("from", ""))
	var s := k * _boost()
	if from == "system":
		var l := _label(String(m.get("text", "")), 20, MUTED, SERIF)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(scroll.size.x - 20, 0)
		list.add_child(l)
		if scroll_now: _scroll_end()
		return
	var admin := from == "admin"
	var row := HBoxContainer.new()
	row.name = "DirectChatRow"
	row.add_theme_constant_override("separation", int(14 * s))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var av := TextureRect.new()
	av.texture = ADMIN_AV if admin else PLAYER_AV
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	av.custom_minimum_size = Vector2(76, 76) * s
	av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(4 * s))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if admin:
		var nm := HBoxContainer.new()
		nm.add_theme_constant_override("separation", int(8 * s))
		var nl := _label(String(chat.get("admin_name", "Fraiha")), 24, GOLD, SERIF_B)
		nl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		nl.add_theme_constant_override("outline_size", 3)
		nm.add_child(nl)
		var cr := TextureRect.new()
		cr.texture = CROWN
		cr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cr.custom_minimum_size = Vector2(30, 26) * s
		cr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm.add_child(cr)
		col.add_child(nm)
	var bubble := PanelContainer.new()
	bubble.name = "DirectChatBubble"
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.066, 0.050, 0.94) if admin else Color(0.050, 0.235, 0.200, 0.95)
	sb.border_color = Color("c99a3c") if admin else Color("b8a252")
	sb.set_border_width_all(maxi(1, int(round(2 * s))))
	sb.set_corner_radius_all(int(12 * s))
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = int(6 * s)
	sb.content_margin_left = 22 * s
	sb.content_margin_right = 22 * s
	sb.content_margin_top = 12 * s
	sb.content_margin_bottom = 10 * s
	bubble.add_theme_stylebox_override("panel", sb)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", int(6 * s))
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(inner)
	var maxw: float = scroll.size.x * 0.66
	var emote_id := String(m.get("emote", ""))
	if not emote_id.is_empty():
		var er := HBoxContainer.new()
		er.add_theme_constant_override("separation", int(10 * s))
		var fx = preload("res://social/emote_fx.gd").make(emote_id, 54.0 * s)
		fx.custom_minimum_size = Vector2(54, 54) * s
		er.add_child(fx)
		er.add_child(_label(String(m.get("text", "")), 24, TEAL_TXT if not admin else CREAM, SERIF_B))
		inner.add_child(er)
	else:
		var text := String(m.get("text", ""))
		var tl := _label(text, 25, CREAM if admin else TEAL_TXT, SERIF)
		tl.name = "DirectChatText"
		var tw: float = 0.0
		for line in text.split("\n"): tw = maxf(tw, SERIF.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(25 * s))).x)
		if tw + 4 > maxw:
			tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tl.custom_minimum_size = Vector2(maxw, 0)
		inner.add_child(tl)
	var gift = m.get("gift")
	if gift is Dictionary: inner.add_child(_gift_card(gift, s))
	var tm := _label(_hour(String(m.get("ts", ""))), 16, Color(0.80, 0.76, 0.66, 0.85), SERIF)
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(tm)
	col.add_child(bubble)
	if admin:
		row.add_child(av)
		row.add_child(col)
	else:
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sp)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(col)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(av)
	list.add_child(row)
	if scroll_now: _scroll_end()

## presente dentro do balão: placa dourada com a coroa, o que veio e "já está na sua conta"
func _gift_card(g: Dictionary, s: float) -> Control:
	var p := PanelContainer.new()
	p.name = "DirectChatGift"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.12, 0.03, 0.95)
	sb.border_color = Color("f0c860")
	sb.set_border_width_all(maxi(1, int(round(2 * s))))
	sb.set_corner_radius_all(int(10 * s))
	sb.shadow_color = Color(1.0, 0.78, 0.30, 0.35)
	sb.shadow_size = int(10 * s)
	for side in ["left", "right"]: sb.set("content_margin_" + side, 16 * s)
	sb.content_margin_top = 10 * s
	sb.content_margin_bottom = 10 * s
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(14 * s))
	p.add_child(h)
	var icon: Control = null
	var kind := String(g.get("kind", ""))
	var item_kind := String(g.get("item_kind", ""))
	if kind == "item" and item_kind == "emote":
		icon = preload("res://social/emote_fx.gd").make(String(g.get("item", "")), 56.0 * s)
	elif kind == "item" and item_kind == "avatar" and hub != null and hub.has_method("avatar_texture"):
		var tr := TextureRect.new()
		tr.texture = hub.avatar_texture(String(g.get("item", "")))
		icon = tr
	if icon == null:
		var tr2 := TextureRect.new()
		tr2.texture = CROWN
		icon = tr2
	if icon is TextureRect:
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(56, 56) * s
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(2 * s))
	h.add_child(v)
	v.add_child(_label("PRESENTE", 17, GOLD, FONT_T))
	var what := ("%d Coroas" % int(g.get("amount", 0))) if kind == "crowns" else "%s · %s" % [String(g.get("kind_label", "Item")), String(g.get("name", ""))]
	var wl := _label(what, 24, Color("fff1c8"), SERIF_B)
	wl.name = "DirectChatGiftName"
	v.add_child(wl)
	v.add_child(_label("Já está na sua conta!" if kind == "crowns" else "Já é seu — use no Perfil.", 17, Color("8fe3b6"), SERIF))
	return p

func _scroll_end():
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

# ---------------------------------------------------------------- + (mensagens rápidas) e emotes
func _close_pop():
	if pop != null: pop.hide()
	pop_kind = ""

func _toggle_pop(kind: String):
	if ended: return
	if pop != null and pop.visible and pop_kind == kind:
		_close_pop()
		return
	if pop == null:
		pop = PanelContainer.new()
		pop.name = "DirectChatPop"
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.06, 0.05, 0.97)
		sb.border_color = Color("c99a3c")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(12)
		sb.shadow_color = Color(0, 0, 0, 0.6)
		sb.shadow_size = 10
		pop.add_theme_stylebox_override("panel", sb)
		pop.hide()
		root.add_child(pop)
	for c in pop.get_children():
		pop.remove_child(c)
		c.queue_free()
	pop_kind = kind
	var s := k * _boost()
	(pop.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 14 * s
	(pop.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 14 * s
	(pop.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_top = 12 * s
	(pop.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_bottom = 12 * s
	if kind == "quick":
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", int(8 * s))
		pop.add_child(v)
		v.add_child(_label("MENSAGENS RÁPIDAS", 18, GOLD, FONT_T))
		for q in QUICK:
			var qq: String = q
			v.add_child(_pop_button(qq, func(): account.send_server({"type": "dchat_send", "text": qq}); _close_pop(), s))
	else:
		var v2 := VBoxContainer.new()
		v2.add_theme_constant_override("separation", int(8 * s))
		pop.add_child(v2)
		v2.add_child(_label("SEUS EMOTES", 18, GOLD, FONT_T))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", int(8 * s))
		grid.add_theme_constant_override("v_separation", int(8 * s))
		v2.add_child(grid)
		var mine: Array = ShopCatalog.my_emotes(Cosmetics.shop_owned)
		if mine.is_empty(): v2.add_child(_label("Nenhum emote liberado ainda.", 18, MUTED, SERIF))
		for e in mine:
			var eid := String(e.id)
			var et := String(e.text)
			var b := _pop_button(et, func(): send_emote(eid, et), s)
			b.name = "DirectChatEmote_" + eid
			var fx = preload("res://social/emote_fx.gd").make(eid, 34.0 * s)
			fx.position = Vector2(8, 6) * s
			fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(fx)
			(b.get_theme_stylebox("normal") as StyleBoxFlat).content_margin_left = 50 * s
			grid.add_child(b)
	pop.show()
	_place_pop()

func _pop_button(t: String, action: Callable, s: float) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", SERIF_B)
	b.add_theme_font_size_override("font_size", int(round(21 * s)))
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color("fff1c8"))
	for pair in [["normal", Color(0.06, 0.20, 0.17)], ["hover", Color(0.09, 0.30, 0.25)], ["pressed", Color(0.04, 0.14, 0.12)]]:
		var st := StyleBoxFlat.new()
		st.bg_color = pair[1]
		st.border_color = Color("b8a252")
		st.set_border_width_all(1)
		st.set_corner_radius_all(int(8 * s))
		st.content_margin_left = 14 * s
		st.content_margin_right = 14 * s
		st.content_margin_top = 6 * s
		st.content_margin_bottom = 6 * s
		b.add_theme_stylebox_override(pair[0], st)
	b.custom_minimum_size.y = 46 * s
	b.pressed.connect(action)
	return b

func _place_pop():
	if pop == null: return
	pop.reset_size()
	var sz := pop.get_combined_minimum_size()
	var anchor := R(R_PLUS) if pop_kind == "quick" else R(R_EMOJI)
	var x := anchor.position.x if pop_kind == "quick" else anchor.end.x - sz.x
	var lr := R(R_LIST)
	x = clampf(x, lr.position.x, maxf(lr.position.x, lr.end.x - sz.x))
	pop.position = Vector2(x, anchor.position.y - sz.y - 10 * k)
	pop.size = sz

# ---------------------------------------------------------------- Ver Perfil (sobre o administrador) e Canal Oficial
func _toggle_info():
	if info == null:
		info = PanelContainer.new()
		info.name = "DirectChatInfo"
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.05, 0.04, 0.97)
		sb.border_color = Color("e0b64a")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.shadow_color = Color(0, 0, 0, 0.6)
		sb.shadow_size = 12
		info.add_theme_stylebox_override("panel", sb)
		info.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: info.hide())
		info.hide()
		root.add_child(info)
	if info.visible:
		info.hide()
		return
	for c in info.get_children(): c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(8 * k))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(v)
	v.add_child(_label("FRAIHA", 34, GOLD, FONT_T))
	v.add_child(_label("ADMINISTRADOR · DONO DO JOGO", 18, Color("d8c79b"), FONT_T))
	var t := _label("Criador do FRAIHA Xadrez. Por este canal você fala direto comigo: dúvidas, ideias, problemas no jogo, eventos especiais. Às vezes chegam presentes por aqui também!", 22, CREAM, SERIF)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(R(R_LIST).size.x * 0.62, 0)
	v.add_child(t)
	v.add_child(_label("Toque para fechar", 16, MUTED, SERIF))
	var sb2: StyleBoxFlat = info.get_theme_stylebox("panel")
	for side in ["left", "right", "top", "bottom"]: sb2.set("content_margin_" + side, 22 * k)
	info.show()
	_place_info()

func _place_info():
	info.reset_size()
	var sz := info.get_combined_minimum_size()
	var lr := R(R_LIST)
	info.position = lr.get_center() - sz / 2.0
	info.size = sz

func _open_channel():
	if hub != null and hub.has_method("open_news"):
		hide_chat()
		hub.open_news()
