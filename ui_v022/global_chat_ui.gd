extends "res://ui_v022/home_modal.gd"
## R96 · CHAT GLOBAL (balão no topo da Home, ao lado do troféu): uma sala para o servidor inteiro
## (online_v021/social/global_chat.js). Abrir = entrar na sala (recebe as últimas mensagens); fechar = sair.
## Conta escreve; convidado só lê. Tocar numa mensagem de outra pessoa mostra VER PERFIL (R104.1), SILENCIAR
## (só neste aparelho) e DENUNCIAR (vai para a moderação).
const WebTextField = preload("res://ui_v022/web_text_field.gd")
var scroll: ScrollContainer
var list: VBoxContainer
var status: Label
var online_label: Label
var input_row: HBoxContainer
var input: LineEdit
var send_button: Button
var guest_label: Label
var messages: Array = []
var muted := {}          # user_id -> nickname (só nesta sessão)
var muted_bar: HFlowContainer   # R161 · silenciados: um botão por pessoa para voltar a ver (REATIVAR)
var reported := {}       # id -> true
var selected := -1
var can_send := false
## R168 · ABAS (canais do servidor): GERAL, PROCURANDO PARCEIROS, DÚVIDAS E AJUDA
const CHANNELS := [["geral", "GERAL", "Escreva para todos…", "GERAL"], ["parceiros", "PROCURANDO PARCEIROS", "Ex.: alguém pra uma Rápida 5 min?", "PARCEIROS"], ["ajuda", "DÚVIDAS E AJUDA", "Pergunte sobre o jogo…", "AJUDA"]]
func _tab_text(c: Array) -> String:
	return c[3] if narrow() else c[1]
var channel := "geral"
var tab_row: HBoxContainer
var tab_buttons := {}
var unread := {}

func setup(p_hub, acc):
	build(p_hub, "CHAT GLOBAL")
	account = acc
	if account != null and account.has_signal("server_message"): account.server_message.connect(_on_message)
	online_label = label("", 13, DIM, true)
	online_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(online_label)
	body.move_child(online_label, 0)
	tab_row = HBoxContainer.new()
	tab_row.name = "GchatTabs"
	tab_row.add_theme_constant_override("separation", 6)
	body.add_child(tab_row)
	body.move_child(tab_row, 0)
	for c in CHANNELS:
		var cid: String = c[0]
		var b := button(_tab_text(c), 11 if narrow() else 15, cid == channel)
		b.name = "GchatTab_" + cid
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.pressed.connect(func(): set_channel(cid))
		tab_row.add_child(b)
		tab_buttons[cid] = b
	muted_bar = HFlowContainer.new()
	muted_bar.name = "GchatMutedBar"
	muted_bar.add_theme_constant_override("h_separation", 8)
	muted_bar.add_theme_constant_override("v_separation", 6)
	muted_bar.hide()
	body.add_child(muted_bar)
	body.move_child(muted_bar, 1)
	scroll = ScrollContainer.new()
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	status = label("", 14, DIM, true)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	body.add_child(input_row)
	input = LineEdit.new()
	input.placeholder_text = "Escreva para todos…"
	input.max_length = 200
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = 46
	input.add_theme_font_size_override("font_size", ts(17))
	var ist := StyleBoxFlat.new()
	ist.bg_color = Color("1d1510")
	ist.border_color = Color("84754b")
	ist.set_border_width_all(1)
	ist.set_corner_radius_all(6)
	for side in ["left", "right"]: ist.set("content_margin_" + side, 10)
	input.add_theme_stylebox_override("normal", ist)
	input.add_theme_stylebox_override("focus", ist)
	input.add_theme_color_override("font_color", CREAM)
	input.text_submitted.connect(func(_t): send_current())
	input_row.add_child(input)
	send_button = button("ENVIAR", 16, true)
	send_button.custom_minimum_size.y = 46
	send_button.pressed.connect(send_current)
	input_row.add_child(send_button)
	guest_label = label("Entre na sua conta para escrever no chat global.", 14, GOLD, true)
	guest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(guest_label)
	WebTextField.attach(input, true)   # celular: campo HTML real (abre o teclado no iPhone) com ENVIAR acima do teclado

func set_channel(cid: String):
	channel = cid
	unread.erase(cid)
	selected = -1
	for c in CHANNELS:
		var cid2: String = c[0]
		var b: Button = tab_buttons[cid2]
		b.text = _tab_text(c) + ("  •" if unread.has(cid2) else "")
		_style_tab(b, cid2 == channel)
		if cid2 == channel: input.placeholder_text = c[2]
	_rebuild()

func _style_tab(b: Button, on: bool):
	style_button(b, on)

static func channel_of(m: Dictionary) -> String:
	var c := String(m.get("channel", "geral"))
	return c if c in ["geral", "parceiros", "ajuda"] else "geral"

func show_chat():
	open()
	selected = -1
	var ok: bool = account != null and bool(account.get("server_ready")) and account.send_server({"type": "gchat_join"})
	status.text = "Entrando no chat…" if ok else "Sem conexão com o servidor. Tente de novo em instantes."
	_apply_can_send(can_send)

func close():
	if visible and account != null: account.send_server({"type": "gchat_leave"})
	super.close()

func _apply_can_send(v: bool):
	can_send = v
	input_row.visible = v
	guest_label.visible = not v

func send_current():
	var t := input.text.strip_edges()
	if t.is_empty(): return
	if account == null or not account.send_server({"type": "gchat_send", "text": t, "channel": channel}):
		status.text = "Sem conexão com o servidor."
		return
	input.text = ""

func _on_message(msg: Dictionary):
	var ty := String(msg.get("type", ""))
	if not ty.begins_with("gchat_"): return
	match ty:
		"gchat_history":
			messages = (msg.get("messages", []) as Array).duplicate() if msg.get("messages") is Array else []
			_apply_can_send(bool(msg.get("can_send", false)))
			var n := int(msg.get("online", 0))
			online_label.text = (("%d pessoa%s no chat agora" % [n, "" if n == 1 else "s"]) if n > 0 else "") + ("  ·  toque numa mensagem para ver o perfil" if can_send else "")
			status.text = ""
			set_channel(channel)
		"gchat_msg":
			messages.append(msg)
			if messages.size() > 240: messages.pop_front()
			status.text = ""
			var mc := channel_of(msg)
			if mc != channel and not unread.has(mc):
				unread[mc] = true
				(tab_buttons[mc] as Button).text += "  •"
			if visible and mc == channel: _rebuild()
		"gchat_error":
			status.text = String(msg.get("message", "Não foi possível enviar."))
		"gchat_reported":
			reported[int(msg.get("id", 0))] = true
			status.text = "Denúncia enviada. Obrigado por ajudar a manter o chat limpo."
			selected = -1
			_rebuild()

func unmute(uid: String):
	var nick := str(muted.get(uid, "")) if muted.get(uid) is String else ""
	muted.erase(uid)
	status.text = "Você voltou a ver as mensagens de %s." % nick if nick != "" else ""
	_rebuild()

func _rebuild_muted():
	for ch in muted_bar.get_children(): ch.queue_free()
	muted_bar.visible = not muted.is_empty()
	if muted.is_empty(): return
	var t := label("Silenciados:", 13, DIM, false)
	muted_bar.add_child(t)
	for uid in muted:
		var u := String(uid)
		var nm = muted[uid]
		var b := button("%s  ·  REATIVAR" % (nm if nm is String and nm != "" else "Jogador"), 13)
		b.name = "GchatUnmute_" + u
		b.pressed.connect(func(): unmute(u))
		muted_bar.add_child(b)

func _rebuild():
	_rebuild_muted()
	for ch in list.get_children(): ch.queue_free()
	var me := String(account.get("user_id")) if account != null else ""
	var shown := 0
	for m in messages:
		if channel_of(m) != channel: continue
		var uid := String(m.get("user_id", ""))
		if muted.has(uid): continue
		list.add_child(_message_row(m, uid == me and me != ""))
		shown += 1
	if shown == 0 and status.text.is_empty() or status.text.begins_with("Ninguém escreveu"):
		status.text = "" if shown > 0 else {"geral": "Ninguém escreveu aqui ainda. Seja o primeiro a dizer olá!", "parceiros": "Ninguém escreveu aqui ainda. Procurando alguém pra jogar? Escreva aqui!", "ajuda": "Ninguém escreveu aqui ainda. Tem alguma dúvida? Pergunte aqui!"}.get(channel, "")
	_scroll_end.call_deferred()

func _scroll_end():
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

var _last_toggle_ms := -100000
func _message_row(m: Dictionary, mine: bool) -> Control:
	var id := int(m.get("id", 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var line := RichTextLabel.new()
	line.bbcode_enabled = false
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_font_override("normal_font", FONT_SEMI)
	line.add_theme_font_size_override("normal_font_size", ts(16))
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	line.push_color(GOLD if mine else Color("8fd1c4"))
	line.push_font(FONT, ts(16))
	line.add_text(String(m.get("nickname", "Jogador")))
	line.pop()
	line.pop()
	# R169 · título escolhido (Loja / Fundador / Club) do lado do nome
	var Cos = preload("res://profile/premium_cosmetics.gd")
	var ttl: String = Cos.title_text(String(m.get("title", "")))
	if not ttl.is_empty():
		# R176.9 · título com a cor própria e um brilho da mesma cor (contorno suave)
		var tc: Color = Cos.title_color(String(m.get("title", "")))
		line.push_color(tc)
		line.push_outline_size(5)
		line.push_outline_color(Color(tc.r, tc.g, tc.b, 0.32))
		line.push_font(FONT, ts(13))
		line.add_text("  " + ttl.to_upper())
		line.pop()
		line.pop()
		line.pop()
		line.pop()
	line.push_color(DIM)
	line.add_text("  " + _hour(String(m.get("ts", ""))) + "\n")
	line.pop()
	line.push_color(CREAM)
	line.add_text(String(m.get("text", "")))   # texto puro: nada de BBCode vindo de outros jogadores
	line.pop()
	box.add_child(line)
	if not mine:
		line.gui_input.connect(func(e: InputEvent):
			var up: bool = (e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and not e.pressed)
			if up:
				# R153 · o celular manda o MESMO toque duas vezes (toque + clique emulado): antes a mensagem abria e
				# fechava no mesmo toque (Android: "apertar várias vezes"; iPhone: nunca ficava aberta). Um toque = uma troca.
				var now := Time.get_ticks_msec()
				if now - _last_toggle_ms < 450: return
				_last_toggle_ms = now
				selected = -1 if selected == id else id
				_rebuild())
	if selected == id and not mine:
		var acts := HFlowContainer.new()
		acts.add_theme_constant_override("h_separation", 8)
		acts.add_theme_constant_override("v_separation", 6)
		var uid := String(m.get("user_id", ""))
		# R104.1 · ver o perfil de quem escreveu (de lá dá para adicionar, convidar, bloquear ou denunciar)
		if can_send and not uid.is_empty():   # conta (o servidor confirma pelo can_send); convidado não tem AMIGOS
			var prof := button("VER PERFIL", 13, true)
			prof.name = "GchatProfile"
			prof.pressed.connect(func(): open_player(uid))
			acts.add_child(prof)
		var mute := button("SILENCIAR", 13)
		mute.pressed.connect(func():
			muted[uid] = String(m.get("nickname", "Jogador"))
			selected = -1
			status.text = "Você não verá mais as mensagens de %s. Para voltar a ver, toque em REATIVAR lá em cima." % String(m.get("nickname", ""))
			_rebuild())
		acts.add_child(mute)
		var rep := button("DENUNCIAR" if not reported.has(id) else "DENUNCIADA", 13)
		rep.disabled = reported.has(id)
		rep.pressed.connect(func(): if account != null: account.send_server({"type": "gchat_report", "id": id}))
		acts.add_child(rep)
		box.add_child(acts)
	var sep := ColorRect.new()
	sep.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.12)
	sep.custom_minimum_size = Vector2(0, 1)
	box.add_child(sep)
	return box

## Fecha o chat e abre o perfil do jogador na tela de AMIGOS.
func open_player(uid: String):
	selected = -1
	close()
	var st = hub.get_parent() if hub != null else null
	var social = st.get("social_ui") if st != null else null
	if social == null: return
	social.open()
	social.open_profile(uid)

func _hour(iso: String) -> String:
	# "2026-10-14T18:05:09.000Z" → hora local "15:05"
	var unix := Time.get_unix_time_from_datetime_string(iso.substr(0, 19)) if iso.length() >= 19 else 0
	if unix <= 0: return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%02d:%02d" % [int(d.hour), int(d.minute)]
