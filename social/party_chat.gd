extends CanvasLayer
## R37.3 · CHAT das mesas com amigo (XEQUE e MARCHA REAL online). Texto puro; o servidor limpa, limita
## e entrega (party_chat). XEQUE: mensagens para todos. MARCHA REAL: escolha PARA TODOS ou SÓ ALIADO.
## Botão "CHAT" na borda direita da tela (com contador de não lidas); o painel abre ao lado dele.
const GOLD := Color("f4ce7f")
const CREAM := Color("efe3c4")
const ALLY := Color("8fd6ff")
const MAX_LEN := 200

var account
var room_id := ""
var game := ""                     # "marcha" | "xeque"
var to := "all"                    # destino escolhido (MARCHA REAL)
var names: Array = []              # nomes da mesa já girados (você = 0)
var messages: Array = []
var unread := 0
var opened := false
var toggle: Button
var panel: PanelContainer
var title: Label
var to_all: Button
var to_ally: Button
var to_row: HBoxContainer
var list: VBoxContainer
var scroll: ScrollContainer
var input: LineEdit
var status: Label

func _init():
    layer = 92
    name = "PartyChat"

func setup(acc):
    account = acc
    if account != null and account.has_signal("server_message"): account.server_message.connect(_on_message)
    toggle = Button.new()
    toggle.name = "PartyChatToggle"
    toggle.text = "CHAT"
    toggle.focus_mode = Control.FOCUS_NONE
    toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    _style(toggle, Color("123222"), GOLD, 22)
    toggle.pressed.connect(func(): set_open(not opened))
    add_child(toggle)
    panel = PanelContainer.new()
    panel.name = "PartyChatPanel"
    var st := StyleBoxFlat.new()
    st.bg_color = Color(0.03, 0.10, 0.06, 0.94)
    st.border_color = Color("c99a45")
    st.set_border_width_all(2)
    st.set_corner_radius_all(10)
    st.shadow_color = Color(0, 0, 0, 0.45)
    st.shadow_size = 8
    for side in ["left", "right", "top", "bottom"]: st.set("content_margin_" + side, 12)
    panel.add_theme_stylebox_override("panel", st)
    panel.custom_minimum_size = Vector2(340, 0)
    add_child(panel)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 6)
    panel.add_child(col)
    var head := HBoxContainer.new()
    col.add_child(head)
    title = Label.new()
    title.text = "CHAT DA MESA"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_color_override("font_color", GOLD)
    title.add_theme_font_size_override("font_size", 18)
    head.add_child(title)
    var close := Button.new()
    close.text = "×"
    close.focus_mode = Control.FOCUS_NONE
    _style(close, Color("1b3a2a"), GOLD, 18)
    close.pressed.connect(func(): set_open(false))
    head.add_child(close)
    to_row = HBoxContainer.new()
    to_row.add_theme_constant_override("separation", 6)
    col.add_child(to_row)
    to_all = Button.new()
    to_all.text = "PARA TODOS"
    to_ally = Button.new()
    to_ally.text = "SÓ ALIADO"
    for b in [to_all, to_ally]:
        b.focus_mode = Control.FOCUS_NONE
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        to_row.add_child(b)
    to_all.pressed.connect(func(): set_to("all"))
    to_ally.pressed.connect(func(): set_to("ally"))
    scroll = ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(0, 180)
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    col.add_child(scroll)
    list = VBoxContainer.new()
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.add_theme_constant_override("separation", 4)
    scroll.add_child(list)
    status = Label.new()
    status.add_theme_color_override("font_color", Color("ff9d86"))
    status.add_theme_font_size_override("font_size", 13)
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    col.add_child(status)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)
    col.add_child(row)
    input = LineEdit.new()
    input.max_length = MAX_LEN
    input.placeholder_text = "Escreva uma mensagem…"
    input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    input.text_submitted.connect(func(_t): send_current())
    row.add_child(input)
    var send := Button.new()
    send.text = "ENVIAR"
    send.focus_mode = Control.FOCUS_NONE
    _style(send, Color("e9b23a"), Color("5a3b06"), 16, Color("2a1a04"))
    send.pressed.connect(send_current)
    row.add_child(send)
    get_viewport().size_changed.connect(_layout)
    visible = false
    set_to("all")

func _style(b: Button, bg: Color, border: Color, fs: int, fg := GOLD):
    var n := StyleBoxFlat.new()
    n.bg_color = bg
    n.border_color = border
    n.set_border_width_all(2)
    n.set_corner_radius_all(8)
    for side in ["left", "right"]: n.set("content_margin_" + side, 12)
    for side in ["top", "bottom"]: n.set("content_margin_" + side, 6)
    var h := n.duplicate()
    h.bg_color = bg.lightened(0.15)
    for pair in [["normal", n], ["hover", h], ["pressed", h], ["focus", StyleBoxEmpty.new()]]: b.add_theme_stylebox_override(pair[0], pair[1])
    b.add_theme_font_size_override("font_size", fs)
    for c in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(c, fg)

## Mesa começou (ou reconectou): mostra o botão CHAT e pede o histórico.
func bind(p_room: String, p_game: String, p_names: Array):
    if p_room != room_id:
        messages = []
        unread = 0
    room_id = p_room
    game = p_game
    names = p_names.duplicate()
    to_row.visible = game == "marcha"
    if game != "marcha": to = "all"
    title.text = "CHAT DA MESA · " + ("MARCHA REAL" if game == "marcha" else "XEQUE")
    visible = true
    _layout()
    _rebuild()
    if account != null: account.send_server({"type": "party_chat_sync", "room_id": room_id})

func unbind():
    room_id = ""
    visible = false
    opened = false
    messages = []
    unread = 0

func active() -> bool:
    return visible and not room_id.is_empty()

func set_open(v: bool):
    opened = v
    if v: unread = 0
    _layout()
    if v: input.grab_focus.call_deferred()

func set_to(v: String):
    to = v if game == "marcha" else "all"
    _style(to_all, Color("e9b23a") if to == "all" else Color("173a2a"), GOLD, 14, Color("2a1a04") if to == "all" else CREAM)
    _style(to_ally, Color("2f7fb0") if to == "ally" else Color("173a2a"), ALLY, 14, Color.WHITE if to == "ally" else CREAM)
    input.placeholder_text = "Mensagem só para o aliado…" if to == "ally" else "Mensagem para todos…"

func send_current():
    var t := input.text.strip_edges()
    if t.is_empty() or room_id.is_empty(): return
    if account != null and account.send_server({"type": "party_chat", "room_id": room_id, "text": t, "to": to}):
        input.text = ""
        status.text = ""
    else:
        status.text = "Sem conexão. Tente de novo em instantes."

func _on_message(msg: Dictionary):
    var t := String(msg.get("type", ""))
    if not t.begins_with("party_chat") or String(msg.get("room_id", "")) != room_id: return
    match t:
        "party_chat_msg":
            messages.append(msg)
            if messages.size() > 60: messages.pop_front()
            if not opened and int(msg.get("from_seat", 0)) != 0: unread += 1
            _rebuild()
        "party_chat_history":
            messages = (msg.get("messages", []) as Array).duplicate()
            _rebuild()
        "party_chat_error":
            status.text = String(msg.get("message", ""))

func _rebuild():
    if list == null: return
    for c in list.get_children(): c.queue_free()
    for m in messages:
        var l := RichTextLabel.new()
        l.bbcode_enabled = true
        l.fit_content = true
        l.scroll_active = false
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        l.add_theme_font_size_override("normal_font_size", 15)
        var mine := int(m.get("from_seat", 0)) == 0
        var who := "Você" if mine else String(m.get("nickname", "?"))
        var ally := String(m.get("to", "all")) == "ally"
        var tag := "[color=#8fd6ff][ALIADO][/color] " if ally else ""
        var col := "#f4ce7f" if mine else ("#8fd6ff" if ally else "#e8c78a")
        l.text = "%s[color=%s][b]%s:[/b][/color] %s" % [tag, col, _esc(who), _esc(String(m.get("text", "")))]
        list.add_child(l)
    _layout()
    _scroll_end.call_deferred()

static func _esc(s: String) -> String:
    return s.replace("[", "[lb]")

func _scroll_end():
    if scroll != null: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func _layout():
    if toggle == null: return
    var vs: Vector2 = get_viewport().get_visible_rect().size
    var s := clampf(minf(vs.x / 1280.0, vs.y / 720.0), 0.8, 1.15)
    var portrait := vs.y > vs.x * 1.15
    toggle.text = "CHAT" + (" (%d)" % unread if unread > 0 else "")
    toggle.scale = Vector2(s, s)
    toggle.reset_size()
    var tsz := toggle.size * s
    toggle.position = Vector2(vs.x - tsz.x - 10, vs.y * (0.30 if portrait else 0.46))
    panel.visible = opened
    panel.scale = Vector2(s, s)
    panel.reset_size()
    var psz := panel.size * s
    panel.position = Vector2(clampf(vs.x - psz.x - 12, 8, vs.x), clampf(toggle.position.y + tsz.y + 8, 8, vs.y - psz.y - 8))
