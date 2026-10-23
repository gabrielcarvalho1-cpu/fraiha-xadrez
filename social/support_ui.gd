extends "res://ui_v022/home_modal.gd"
## R176.8 · SUPORTE: o jogador manda uma mensagem (reclamação, sugestão, dúvida, problema no jogo, pagamento)
## que cai direto no Admin → Suporte. Embaixo/ao lado: MEUS TICKETS, com a resposta da equipe (chega na hora se
## estiver online — ticket_update). Só com conta (convidado vê o aviso para entrar). Servidor: online_v021/support.
const CATS := [["reclamacao", "RECLAMAÇÃO"], ["sugestao", "SUGESTÃO"], ["duvida", "DÚVIDA"], ["problema", "PROBLEMA"], ["pagamento", "PAGAMENTO"]]
const ST_TXT := {"open": ["AGUARDANDO RESPOSTA", Color("e6c27a")], "answered": ["RESPONDIDO", Color("7fe0a0")], "closed": ["FECHADO", Color("9c9886")]}
const OK_COL := Color("9fe0a8")
const ERR_COL := Color("ff9d86")

var scroll: ScrollContainer
var content: VBoxContainer
var category := ""
var subject: LineEdit
var message_line: LineEdit = null   # celular na Web: campo de uma linha (o teclado do navegador)
var message_box: TextEdit = null    # PC: caixa de várias linhas
var status: Label
var send_btn: Button
var cat_buttons := {}
var items: Array = []
var list_ok := true
var _draft := {"subject": "", "message": ""}
var _sending := false

func setup(p_hub, acc):
	build(p_hub, "SUPORTE")
	account = acc
	scroll = ScrollContainer.new()
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	if account != null and account.has_signal("server_message"): account.server_message.connect(_on_message)

func show_support():
	open()
	_rebuild()
	if _logged() and account.has_method("send_server"): account.send_server({"type": "ticket_list"})

func _logged() -> bool:
	return account != null and account.has_method("has_profile") and account.has_profile()

func _layout():
	super._layout()
	if visible and content != null: _rebuild.call_deferred()

func _keep_draft():
	if subject != null and is_instance_valid(subject): _draft.subject = subject.text
	if message_box != null and is_instance_valid(message_box): _draft.message = message_box.text
	elif message_line != null and is_instance_valid(message_line): _draft.message = message_line.text

func _rebuild():
	if scroll == null: return
	_keep_draft()
	if content != null: content.queue_free()
	content = VBoxContainer.new()
	content.name = "SupportContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	var left: Control = content
	var right: Control = content
	if not portrait():
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 26)
		content.add_child(cols)
		left = _col(cols, 1.1)
		right = _col(cols, 1.0)
	_form(left)
	_mine(right)

func _col(parent: Control, ratio: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = ratio
	v.add_theme_constant_override("separation", 10)
	parent.add_child(v)
	return v

func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _section(parent: Control, t: String):
	parent.add_child(label(t, 17, GOLD))
	var line := ColorRect.new()
	line.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	parent.add_child(line)

func _field_style(c: Control):
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.09, 0.92)
	sb.border_color = Color("84754b")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	for side in ["left", "right"]: sb.set("content_margin_" + side, 10)
	for side in ["top", "bottom"]: sb.set("content_margin_" + side, 6)
	for st in ["normal", "focus", "read_only"]: c.add_theme_stylebox_override(st, sb)
	c.add_theme_font_override("font", preload("res://ui_kit/fonts/Alegreya-Bold.woff"))
	c.add_theme_font_size_override("font_size", ts(15))
	c.add_theme_color_override("font_color", CREAM)
	c.add_theme_color_override("font_placeholder_color", DIM)
	c.add_theme_color_override("caret_color", GOLD)

func _form(parent: Control):
	_section(parent, "FALE COM A GENTE")
	if not _logged():
		parent.add_child(_wrap(label("Entre na sua conta para mandar uma mensagem ao suporte — assim a gente consegue te responder aqui mesmo, no jogo.", 15, CREAM, true)))
		parent.add_child(_wrap(label("Sem conta? Fale com a gente no Discord (Conheça o FRAIHA → Comunidade e Suporte).", 13, DIM, true)))
		return
	parent.add_child(_wrap(label("TIPO  ·  a mensagem chega direto para a equipe do FRAIHA", 13, GOLD)))
	var grid := GridContainer.new()
	grid.columns = 2 if (narrow() or portrait()) else 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	cat_buttons.clear()
	for c in CATS:
		var id: String = c[0]
		var b := button(c[1], 13, id == category)
		b.name = "SupportCat_" + id
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, ts(36))
		b.pressed.connect(func():
			category = id
			for k in cat_buttons: style_button(cat_buttons[k], k == category))
		grid.add_child(b)
		cat_buttons[id] = b
		b.resized.connect(_fit_cat)   # R176.8c · texto encolhe até caber (RECLAMAÇÃO cortava)
	parent.add_child(label("ASSUNTO (opcional)", 13, GOLD))
	subject = LineEdit.new()
	subject.name = "SupportSubject"
	subject.max_length = 80
	subject.placeholder_text = "Ex.: A partida travou no fim"
	subject.text = String(_draft.subject)
	subject.custom_minimum_size = Vector2(0, ts(38))
	_field_style(subject)
	parent.add_child(subject)
	preload("res://ui_v022/web_text_field.gd").attach(subject)
	parent.add_child(label("MENSAGEM", 13, GOLD))
	message_box = null
	message_line = null
	if preload("res://ui_v022/web_text_field.gd").wanted(get_viewport()):
		message_line = LineEdit.new()
		message_line.name = "SupportMessage"
		message_line.max_length = 2000
		message_line.placeholder_text = "Conte o que aconteceu…"
		message_line.text = String(_draft.message)
		message_line.custom_minimum_size = Vector2(0, ts(44))
		_field_style(message_line)
		parent.add_child(message_line)
		preload("res://ui_v022/web_text_field.gd").attach(message_line)
	else:
		message_box = TextEdit.new()
		message_box.name = "SupportMessage"
		message_box.placeholder_text = "Conte o que aconteceu, com o máximo de detalhes (modo de jogo, horário, o que apareceu na tela)…"
		message_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		message_box.text = String(_draft.message)
		message_box.custom_minimum_size = Vector2(0, ts(96 if not narrow() else 110))
		_field_style(message_box)
		message_box.text_changed.connect(func(): if message_box.text.length() > 2000: message_box.text = message_box.text.substr(0, 2000))
		parent.add_child(message_box)
	send_btn = button("ENVIAR PARA O SUPORTE", 15, true)
	send_btn.name = "SupportSend"
	send_btn.custom_minimum_size = Vector2(0, ts(44))
	send_btn.disabled = _sending
	send_btn.pressed.connect(_send)
	parent.add_child(send_btn)
	status = _wrap(label("", 14, OK_COL, true))
	status.name = "SupportStatus"
	parent.add_child(status)

func _fit_cat(_b = null):
	# R176.8c · todos os tipos com o MESMO tamanho de letra: o do que precisa ser menor para caber (RECLAMAÇÃO)
	var px := ts(13)
	for k in cat_buttons:
		var b: Button = cat_buttons[k]
		if not is_instance_valid(b) or b.size.x < 10: return
		var f: Font = b.get_theme_font("font")
		var room := b.size.x - (14.0 if narrow() else 26.0)
		while px > 8 and f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room: px -= 1
	for k in cat_buttons:
		var b: Button = cat_buttons[k]
		if b.get_theme_font_size("font_size") != px: b.add_theme_font_size_override("font_size", px)

func _message_text() -> String:
	if message_box != null and is_instance_valid(message_box): return message_box.text.strip_edges()
	if message_line != null and is_instance_valid(message_line): return message_line.text.strip_edges()
	return ""

func _say(t: String, ok := true):
	if status != null and is_instance_valid(status):
		status.text = t
		status.add_theme_color_override("font_color", OK_COL if ok else ERR_COL)

func _send():
	if _sending: return
	if category.is_empty(): return _say("Escolha o TIPO da mensagem.", false)
	var msg := _message_text()
	if msg.length() < 5: return _say("Escreva a sua mensagem (pelo menos 5 letras).", false)
	if not (account != null and account.has_method("send_server")): return _say("Sem conexão com o servidor agora.", false)
	_sending = true
	send_btn.disabled = true
	_say("Enviando…")
	var vs := get_viewport().get_visible_rect().size
	account.send_server({"type": "ticket_send", "category": category, "subject": subject.text.strip_edges(), "message": msg,
		"context": {"platform": "web" if OS.has_feature("web") else OS.get_name().to_lower(), "version": String(ProjectSettings.get_setting("application/config/version", "")),
			"mobile": vs.y > vs.x, "screen": "suporte"}})
	get_tree().create_timer(12.0).timeout.connect(func():
		if _sending:
			_sending = false
			if is_instance_valid(send_btn): send_btn.disabled = false
			_say("O servidor não respondeu. Tente de novo em instantes.", false))

func _mine(parent: Control):
	_section(parent, "MEUS TICKETS")
	var list := VBoxContainer.new()
	list.name = "SupportMine"
	list.add_theme_constant_override("separation", 8)
	parent.add_child(list)
	if not _logged():
		list.add_child(_wrap(label("As suas mensagens e as respostas aparecem aqui.", 13, DIM, true)))
		return
	if not list_ok:
		list.add_child(_wrap(label("O suporte pelo jogo ainda não está ligado neste servidor. Fale com a gente no Discord.", 13, DIM, true)))
		return
	if items.is_empty():
		list.add_child(_wrap(label("Você ainda não mandou nenhuma mensagem. A resposta da equipe aparece aqui.", 13, DIM, true)))
		return
	for t in items:
		if not (t is Dictionary): continue
		var p := PanelContainer.new()
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.03, 0.06, 0.14, 0.88)
		s.border_color = Color("c99a45") if String(t.get("status", "")) != "answered" else Color("49d17a")
		s.set_border_width_all(2)
		s.set_corner_radius_all(6)
		for side in ["left", "right"]: s.set("content_margin_" + side, 12)
		for side in ["top", "bottom"]: s.set("content_margin_" + side, 8)
		p.add_theme_stylebox_override("panel", s)
		p.name = "Ticket_" + String(t.get("ticket_id", ""))
		list.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		p.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		v.add_child(top)
		var head := String(t.get("category_label", "")).to_upper() + ("  ·  " + String(t.get("subject", "")) if String(t.get("subject", "")) != "" else "")
		var hl := _wrap(label(head, 13, GOLD, true))
		top.add_child(hl)
		var stt: Array = ST_TXT.get(String(t.get("status", "open")), ST_TXT.open)
		var sl := label(String(stt[0]), 11, stt[1], true)
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top.add_child(sl)
		v.add_child(_wrap(label(String(t.get("message", "")), 13, CREAM, true)))
		v.add_child(label(_when(String(t.get("created_at", ""))), 11, DIM, true))
		var rep := String(t.get("reply", ""))
		if not rep.is_empty():
			var rl := _wrap(label("RESPOSTA DO FRAIHA: " + rep, 14, Color("bff2cf"), true))
			rl.name = "TicketReply"
			v.add_child(rl)

func _when(iso: String) -> String:
	if iso.length() < 16: return ""
	var t := Time.get_unix_time_from_datetime_string(iso.substr(0, 19)) - 3 * 3600   # horário de Brasília
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%02d/%02d %02d:%02d" % [d.day, d.month, d.hour, d.minute]

func _on_message(m: Dictionary):
	match String(m.get("type", "")):
		"ticket_ok":
			_sending = false
			category = ""
			_draft = {"subject": "", "message": ""}
			if visible:
				if subject != null and is_instance_valid(subject): subject.text = ""
				if message_box != null and is_instance_valid(message_box): message_box.text = ""
				if message_line != null and is_instance_valid(message_line): message_line.text = ""
				for k in cat_buttons: if is_instance_valid(cat_buttons[k]): style_button(cat_buttons[k], false)
				if is_instance_valid(send_btn): send_btn.disabled = false
				_say("Mensagem enviada! A resposta aparece em MEUS TICKETS.")
		"ticket_error":
			_sending = false
			if visible:
				if is_instance_valid(send_btn): send_btn.disabled = false
				_say(String(m.get("message", "Não foi possível enviar.")), false)
		"ticket_list":
			list_ok = bool(m.get("available", false))
			items = m.get("items", []) if m.get("items") is Array else []
			if visible: _rebuild_list()
		"ticket_update":
			var tk: Dictionary = m.get("ticket", {}) if m.get("ticket") is Dictionary else {}
			var found := false
			for i in items.size():
				if items[i] is Dictionary and String(items[i].get("ticket_id", "")) == String(tk.get("ticket_id", "")):
					items[i] = tk
					found = true
			if not found and not tk.is_empty(): items.push_front(tk)
			if visible: _rebuild_list()
			elif hub != null and hub.has_method("show_toast"): hub.show_toast("O SUPORTE RESPONDEU A SUA MENSAGEM")

## troca só a lista (o formulário que está sendo escrito fica como está)
func _rebuild_list():
	var old := content.find_child("SupportMine", true, false) if content != null else null
	if old == null:
		_rebuild()
		return
	var parent: Control = old.get_parent()
	var idx: int = old.get_index()
	# título + linha ficam; troca só a caixa da lista
	parent.remove_child(old)
	old.queue_free()
	var tmp := VBoxContainer.new()
	_mine(tmp)
	var fresh: Node = tmp.find_child("SupportMine", false, false)
	tmp.remove_child(fresh)
	parent.add_child(fresh)
	parent.move_child(fresh, idx)
	tmp.queue_free()
