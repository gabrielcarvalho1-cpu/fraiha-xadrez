extends "res://ui_v022/home_modal.gd"
## R121 · APOIE UM CRIADOR — o jogador digita o código de um criador de conteúdo parceiro (ou abre o link dele).
## Vale 30 dias (digitar de novo renova). Na primeira vez ganha um presente em Coroas; parte do que comprar no jogo
## nesse período vai para o criador, sem custar nada a mais. O servidor decide tudo (creator_set / creator_state).
const InviteLink := preload("res://social/invite_link.gd")
var client
var info: VBoxContainer
var input: LineEdit
var go: Button
var msg_label: Label
var state: Dictionary = {}

func setup(p_hub, acc, p_client):
	build(p_hub, "APOIE UM CRIADOR")
	account = acc
	client = p_client
	if account != null and account.has_signal("server_message"): account.server_message.connect(_on_message)
	# tudo dentro de uma rolagem (celular estreito: o texto não cabe inteiro na moldura)
	var sc := ScrollContainer.new()
	preload("res://ui_v022/touch_scroll.gd").attach(sc)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(sc)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	sc.add_child(col)
	var expl := label("Segue algum criador de conteúdo de xadrez parceiro do FRAIHA? Digite o código dele: você ganha um presente em Coroas na primeira vez e, por 30 dias, parte do que você comprar no jogo vai para ele — sem pagar nada a mais.", 14, CREAM, true)
	expl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(expl)
	info = VBoxContainer.new()
	info.name = "CreatorInfo"
	info.add_theme_constant_override("separation", 4)
	col.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	input = LineEdit.new()
	input.name = "CreatorInput"
	input.placeholder_text = "Código do criador"
	input.max_length = 20
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = ts(40)
	input.add_theme_font_size_override("font_size", ts(16))
	input.text_submitted.connect(func(_t): _send())
	row.add_child(input)
	preload("res://ui_v022/web_text_field.gd").attach(input)
	go = button("APOIAR", 15, true)
	go.name = "CreatorGo"
	go.pressed.connect(_send)
	row.add_child(go)
	msg_label = label("", 14, GOLD, true)
	msg_label.name = "CreatorMsg"
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(msg_label)
	var fine := label("O código não muda nenhum preço e não dá vantagem no jogo. Você pode trocar de criador quando quiser.", 12, DIM, true)
	fine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(fine)

func show_creator():
	open()
	msg_label.text = ""
	_render()
	if account != null and account.has_method("send_server"): account.send_server({"type": "creator_get"})

func _send():
	var code := InviteLink.creator_clean(input.text)
	if code.is_empty():
		msg_label.text = "Digite o código (3 a 20 letras ou números)."
		return
	msg_label.text = "Conferindo…"
	if not account.send_server({"type": "creator_set", "code": code}): msg_label.text = "Sem conexão. Tente de novo."

func _on_message(m: Dictionary):
	match String(m.get("type", "")):
		"creator_state":
			state = m
			if m.has("just_linked"):
				var g := int(m.get("gift", 0))
				msg_label.text = "Pronto! Você está apoiando %s.%s" % [String(m.just_linked), (" Ganhou %d Coroas de presente!" % g) if g > 0 else ""]
				input.text = ""
			if visible: _render()
		"creator_error":
			msg_label.text = String(m.get("message", "Não foi possível."))

func _render():
	for c in info.get_children(): c.queue_free()
	if state.is_empty(): return
	if not bool(state.get("available", false)):
		var na := label(String(state.get("message", "Os códigos de criador ainda não estão ligados neste servidor.")), 14, DIM, true)
		na.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(na)
		input.editable = false
		go.disabled = true
		return
	input.editable = true
	go.disabled = false
	var l = state.get("linked")
	if l is Dictionary:
		var exp := String(l.get("expires_at", ""))
		var d := "%s/%s" % [exp.substr(8, 2), exp.substr(5, 2)] if exp.length() >= 10 else ""
		var t := label("VOCÊ APOIA: %s (%s)" % [String(l.get("name", "")).to_upper(), String(l.get("code", ""))], 17, GOLD)
		t.name = "CreatorCurrent"
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(t)
		var until := label("Até %s · digite o código de novo para renovar por mais 30 dias." % d, 13, CREAM, true)
		until.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(until)
	else:
		var none := label("Você ainda não apoia nenhum criador.", 14, DIM, true)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(none)
