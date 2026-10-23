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
var send_btn: Button
var close_btn: Button
var panel_style: StyleBoxFlat
var emote_row: HFlowContainer
const ShopCatalog := preload("res://economy/crown_store_catalog.gd")
const EmotePrefs := preload("res://social/emote_prefs.gd")
const EmoteBanner := preload("res://social/emote_banner.gd")
## R177b · onde está a foto de cada lugar da mesa (0 = você), em pixels da tela — o modo (XEQUE/MARCHA) informa
var seat_rect: Callable
var bubble_layer: Control
const Cosmetics := preload("res://profile/premium_cosmetics.gd")
## R90 · cores da sala (nada de verde): XEQUE vinho + marfim + ouro; MARCHA REAL roxo real + ouro
const THEMES := {
    "xeque": {"btn": Color("6b1424"), "panel": Color(0.16, 0.04, 0.06, 0.95), "border": Color("d9a441"), "text": Color("f3e6c8"), "off": Color("3a0e16")},
    "marcha": {"btn": Color("3d1c57"), "panel": Color(0.09, 0.05, 0.14, 0.95), "border": Color("d9a441"), "text": Color("f3e6c8"), "off": Color("261338")},
}
func _theme() -> Dictionary:
    return THEMES.get(game, THEMES["xeque"])

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
    _style(toggle, THEMES.xeque.btn, THEMES.xeque.border, 22, THEMES.xeque.text)
    toggle.pressed.connect(func(): set_open(not opened))
    add_child(toggle)
    panel = PanelContainer.new()
    panel.name = "PartyChatPanel"
    var st := StyleBoxFlat.new()
    panel_style = st
    st.bg_color = Color(0.042, 0.075, 0.141, 0.94)
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
    close_btn = Button.new()
    var close := close_btn
    close.text = "×"
    close.focus_mode = Control.FOCUS_NONE
    _style(close, THEMES.xeque.off, GOLD, 18)
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
    # R119 · EMOTES para a mesa toda (os de graça + os comprados na Loja de Coroas)
    # R176.8c · com muitos emotes a fileira empurrava a conversa: agora é uma faixa de ~2 linhas que rola
    var emote_scroll := ScrollContainer.new()
    emote_scroll.name = "PartyEmoteScroll"
    emote_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    emote_scroll.custom_minimum_size = Vector2(0, 76)
    preload("res://ui_v022/touch_scroll.gd").attach(emote_scroll)
    col.add_child(emote_scroll)
    emote_row = HFlowContainer.new()
    emote_row.name = "PartyEmoteRow"
    emote_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    emote_row.add_theme_constant_override("h_separation", 6)
    emote_row.add_theme_constant_override("v_separation", 6)
    emote_scroll.add_child(emote_row)
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
    # R90 · Web no celular: campo HTML real (teclado abre no iPhone) com barra de envio fixa acima do teclado
    preload("res://ui_v022/web_text_field.gd").attach(input, true)
    send_btn = Button.new()
    var send := send_btn
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
    _apply_theme()
    visible = true
    _layout()
    _rebuild()
    if account != null: account.send_server({"type": "party_chat_sync", "room_id": room_id})

func unbind():
    dock_rect = Rect2()
    blocked = false
    room_id = ""
    visible = false
    opened = false
    messages = []
    unread = 0

func active() -> bool:
    return visible and not room_id.is_empty()

func set_open(v: bool):
    opened = v
    if v:
        unread = 0
        _fill_emotes()   # R119 · inclui os comprados desde a última vez
    _layout()
    if v and input.focus_mode != Control.FOCUS_NONE: input.grab_focus.call_deferred()

func _apply_theme():
    var t := _theme()
    _style(toggle, t.btn, t.border, 22, t.text)
    _style(close_btn, t.off, t.border, 18, t.text)
    if panel_style != null:
        panel_style.bg_color = t.panel
        panel_style.border_color = t.border
    set_to(to)

func set_to(v: String):
    to = v if game == "marcha" else "all"
    var off: Color = _theme().off
    _style(to_all, Color("e9b23a") if to == "all" else off, GOLD, 14, Color("2a1a04") if to == "all" else CREAM)
    _style(to_ally, Color("2f7fb0") if to == "ally" else off, ALLY, 14, Color.WHITE if to == "ally" else CREAM)
    input.placeholder_text = "Mensagem só para o aliado…" if to == "ally" else "Mensagem para todos…"

func send_current():
    var t := input.text.strip_edges()
    if t.is_empty() or room_id.is_empty(): return
    if account != null and account.send_server({"type": "party_chat", "room_id": room_id, "text": t, "to": to}):
        input.text = ""
        status.text = ""
    else:
        status.text = "Sem conexão. Tente de novo em instantes."

func _fill_emotes():
    if emote_row == null: return
    for c in emote_row.get_children(): c.queue_free()
    for e in ShopCatalog.my_emotes(Cosmetics.shop_owned):
        var eid := String(e.id)
        var b := Button.new()
        b.name = "PartyEmote_" + eid
        b.text = String(e.text)
        b.focus_mode = Control.FOCUS_NONE
        _style(b, Color("16306a"), Color("c99a45"), 14)
        b.pressed.connect(func(): send_emote(eid))
        emote_row.add_child(b)

func send_emote(id: String):
    if room_id.is_empty() or account == null: return
    if account.send_server({"type": "party_emote", "room_id": room_id, "id": id}): status.text = ""
    else: status.text = "Sem conexão. Tente de novo em instantes."

func _on_message(msg: Dictionary):
    var t := String(msg.get("type", ""))
    if not t.begins_with("party_chat") or String(msg.get("room_id", "")) != room_id: return
    match t:
        "party_chat_msg":
            messages.append(msg)
            if messages.size() > 60: messages.pop_front()
            if msg.has("emote"): show_emote(msg)   # R177b · o emote aparece na mesa (faixa ao lado da foto de quem mandou)
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
        if m.has("emote"): l.text = "[color=%s][b]%s:[/b][/color] [color=#bcd4ff]“%s”[/color]" % [col, _esc(who), _esc(String(m.get("text", "")))]   # R119
        list.add_child(l)
    _layout()
    _scroll_end.call_deferred()

## R177b · faixa do EMOTE na mesa (XEQUE / MARCHA), igual à do xadrez: ao lado da foto de quem mandou, sem cobrir o
## botão CHAT nem o painel aberto, sempre dentro da tela. Some sozinha.
func show_emote(m: Dictionary):
    if not EmotePrefs.enabled(): return
    if bubble_layer == null:
        bubble_layer = Control.new()
        bubble_layer.name = "PartyEmoteBubbles"
        bubble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bubble_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(bubble_layer)
    var seat := int(m.get("from_seat", 0))
    var mine := seat == 0
    var nm := "PartyEmote_%d" % seat
    for c in bubble_layer.get_children():
        if c.name == nm or c.is_queued_for_deletion():
            bubble_layer.remove_child(c)
            c.queue_free()
    var vs := get_viewport().get_visible_rect().size
    var a := Rect2()
    if seat_rect.is_valid(): a = seat_rect.call(seat)
    if not a.has_area(): a = Rect2(Vector2(vs.x * 0.5 - 40, vs.y * (0.62 if mine else 0.12)), Vector2(80, 80))
    # faixa por cima do PRÓPRIO cartão de quem mandou (na parte de baixo dele): fica claro de quem é e não cai
    # em cima do tabuleiro, das cartas da mão ou dos botões
    var h := clampf(minf(a.size.y * 0.55, vs.y * 0.12), 52.0, 64.0)
    var p: Control = EmoteBanner.make(String(m.get("text", "")), "Você" if mine else String(m.get("nickname", "")), String(m.get("emote", "")), h)
    p.name = nm
    var w := p.size.x
    var x := a.get_center().x - w / 2.0
    x = clampf(x, 4.0, maxf(4.0, vs.x - w - 4.0))
    var y := a.end.y - h - 4.0
    if mine and vs.y > vs.x: y = a.position.y - h - 6.0   # celular em pé: a mão cobre o seu cartão — a faixa fica logo acima
    y = clampf(y, 4.0, maxf(4.0, vs.y - h - 4.0))
    # não cobre o botão CHAT nem o painel do chat aberto
    var avoid: Array = []
    if toggle != null and toggle.visible: avoid.append(Rect2(toggle.global_position, toggle.size * toggle.scale))
    if panel != null and panel.visible: avoid.append(Rect2(panel.global_position, panel.size * panel.scale))
    for r in avoid:
        if Rect2(x, y, w, h).intersects((r as Rect2).grow(4.0)):
            var up: float = (r as Rect2).position.y - h - 8.0
            y = up if up >= 4.0 else clampf((r as Rect2).end.y + 8.0, 4.0, vs.y - h - 4.0)
    p.position = Vector2(floorf(x), floorf(y))
    bubble_layer.add_child(p)
    p.pivot_offset = Vector2(0, h / 2.0)
    p.modulate.a = 0.0
    p.scale = Vector2(0.92, 0.92)
    var tw := create_tween()
    tw.set_parallel(true)
    tw.tween_property(p, "modulate:a", 1.0, 0.15)
    tw.tween_property(p, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.chain().tween_interval(2.3)
    tw.chain().tween_property(p, "modulate:a", 0.0, 0.4)
    tw.chain().tween_callback(p.queue_free)

static func _esc(s: String) -> String:
    return s.replace("[", "[lb]")

func _scroll_end():
    if scroll != null: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

## R88 · lugar do botão CHAT escolhido pelo modo (pixels de tela); Rect2() = posição padrão (borda direita)
var dock_rect := Rect2()
## R95 · o modo (MARCHA / XEQUE) abriu menu, tutorial, confirmação ou a tela de resultado: o CHAT some
## (botão e painel) para nunca ficar por cima dessas telas — esta camada fica acima da camada do modo.
var blocked := false

func set_blocked(v: bool):
    if v == blocked: return
    blocked = v
    _layout()
func set_dock(r: Rect2):
    if r == dock_rect: return
    dock_rect = r
    if r.size.x <= 1.0 and toggle != null:
        toggle.custom_minimum_size = Vector2.ZERO
        toggle.remove_theme_font_size_override("font_size")
    _layout()

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
    if dock_rect.size.x > 1.0:
        # R88 · o modo (XEQUE / MARCHA no celular) reservou um lugar para o CHAT: botão grande ali
        toggle.scale = Vector2.ONE
        toggle.add_theme_font_size_override("font_size", int(clampf(dock_rect.size.y * 0.42, 14.0, 26.0)))
        toggle.custom_minimum_size = dock_rect.size
        toggle.size = dock_rect.size
        toggle.position = dock_rect.position
        tsz = dock_rect.size
    toggle.visible = not blocked
    panel.visible = opened and not blocked
    panel.scale = Vector2(s, s)
    panel.reset_size()
    var psz := panel.size * s
    panel.position = Vector2(clampf(vs.x - psz.x - 12, 8, vs.x), clampf(toggle.position.y + tsz.y + 8, 8, vs.y - psz.y - 8))
