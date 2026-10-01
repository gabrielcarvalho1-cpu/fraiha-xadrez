extends CanvasLayer
## Chat da partida online (Casual e Ranked). Texto puro; o servidor valida, limita e distribui.
## Desktop: painel fixo ao lado do tabuleiro. Mobile: abre/fecha pelo botão "Chat".
## Silenciar é só local: este jogador deixa de ver as mensagens do adversário.
const Mobile = preload("res://ui_v022/mobile_layout.gd")
const GOLD = Color("f4ce7f")
const MAX_LEN = 200
signal layout_needed
var account
var controller
var match_id := ""
var my_color := ""
var muted := false
var reported := false
var open_mobile := false
var unread := 0
var messages: Array = []
var panel: PanelContainer
var title: Label
var mute_button: Button
var report_button: Button
var close_button: Button
var scroll: ScrollContainer
var list: VBoxContainer
var input: LineEdit
var send_button: Button
var status: Label
var toggle_button: Button
var minimize_button: Button
var minimized := false   # desktop: chat recolhido num botão "CHAT"
var restore_button: Button

func setup(service):
    account = service
    layer = 46
    account.server_message.connect(_on_message)
    panel = PanelContainer.new()
    panel.name = "MatchChat"
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0.03, 0.10, 0.06, 0.88)
    style.border_color = Color("c99a45")
    style.set_border_width_all(2)
    style.set_corner_radius_all(10)
    style.shadow_color = Color(0, 0, 0, 0.4)
    style.shadow_size = 8
    for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 12)
    panel.add_theme_stylebox_override("panel", style)
    add_child(panel)
    var col = VBoxContainer.new()
    col.add_theme_constant_override("separation", 6)
    panel.add_child(col)
    var head = HBoxContainer.new()
    head.add_theme_constant_override("separation", 6)
    col.add_child(head)
    title = Label.new()
    title.text = "CHAT"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.clip_text = true
    title.add_theme_color_override("font_color", GOLD)
    title.add_theme_font_override("font", preload("res://account/fonts/Cinzel-Bold.woff"))
    head.add_child(title)
    mute_button = _small(head, "SILENCIAR", _toggle_mute)
    mute_button.tooltip_text = "Deixar de ver as mensagens do adversário (só para você)"
    report_button = _small(head, "DENUNCIAR", _report)
    report_button.tooltip_text = "Enviar as mensagens do adversário para análise"
    close_button = _small(head, "FECHAR", func(): set_mobile_open(false))
    minimize_button = _small(head, "—", func(): set_minimized(true))
    minimize_button.tooltip_text = "Minimizar o chat"
    scroll = ScrollContainer.new()
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    col.add_child(scroll)
    list = VBoxContainer.new()
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.add_theme_constant_override("separation", 4)
    scroll.add_child(list)
    status = Label.new()
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status.add_theme_color_override("font_color", Color("ff9d86"))
    status.hide()
    col.add_child(status)
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)
    col.add_child(row)
    input = LineEdit.new()
    input.name = "ChatInput"
    input.placeholder_text = "Mensagem…"
    input.max_length = MAX_LEN
    input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    input.text_submitted.connect(func(_t): send_current())
    row.add_child(input)
    # Web no celular: campo HTML real sobre o LineEdit para o teclado virtual abrir ao tocar.
    preload("res://ui_v022/web_text_field.gd").attach(input)
    send_button = _small(row, "ENVIAR", send_current)
    send_button.name = "ChatSend"
    toggle_button = Button.new()
    toggle_button.name = "ChatToggle"
    toggle_button.text = "Chat"
    toggle_button.pressed.connect(func(): set_mobile_open(not open_mobile))
    # Desktop: com o chat minimizado, um botão "CHAT" dourado traz o painel de volta.
    restore_button = _small(self, "CHAT", func(): set_minimized(false))
    restore_button.name = "ChatRestore"
    restore_button.tooltip_text = "Abrir o chat"
    var rs: StyleBoxFlat = restore_button.get_theme_stylebox("normal").duplicate()
    rs.bg_color = Color(0.05, 0.16, 0.09, 0.92)
    rs.border_color = Color("c99a45")
    rs.set_border_width_all(2)
    rs.set_corner_radius_all(10)
    rs.shadow_color = Color(0, 0, 0, 0.45)
    rs.shadow_size = 6
    restore_button.add_theme_stylebox_override("normal", rs)
    var rh: StyleBoxFlat = rs.duplicate()
    rh.bg_color = Color(0.09, 0.26, 0.14, 0.95)
    rh.border_color = Color("f4ce7f")
    for state in ["hover", "pressed"]: restore_button.add_theme_stylebox_override(state, rh)
    restore_button.add_theme_font_override("font", preload("res://account/fonts/Cinzel-Bold.woff"))
    restore_button.add_theme_color_override("font_color", GOLD)
    restore_button.add_theme_color_override("font_hover_color", Color("ffe6a0"))
    restore_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    restore_button.hide()
    panel.hide()

func _small(parent: Node, text: String, action: Callable) -> Button:
    var b = Button.new()
    b.text = text
    b.focus_mode = Control.FOCUS_NONE
    var st = StyleBoxFlat.new()
    st.bg_color = Color("14221d")
    st.border_color = Color("84754b")
    st.set_border_width_all(1)
    st.set_corner_radius_all(4)
    st.content_margin_left = 8
    st.content_margin_right = 8
    b.add_theme_stylebox_override("normal", st)
    var hi = st.duplicate()
    hi.bg_color = Color("26382b")
    for state in ["hover", "pressed"]: b.add_theme_stylebox_override(state, hi)
    b.add_theme_color_override("font_color", Color("efe3c4"))
    b.pressed.connect(action)
    parent.add_child(b)
    return b

# ---------- Ciclo de vida ----------
func bind(ranked_controller):
    controller = ranked_controller
    var new_id = String(controller.match_id)
    if new_id != match_id:
        match_id = new_id
        muted = false
        reported = false
        unread = 0
        messages.clear()
        _rebuild()
    my_color = String(controller.human_color)
    status.hide()
    mute_button.text = "SILENCIAR"
    report_button.disabled = reported
    report_button.text = "DENUNCIAR"
    open_mobile = false
    panel.show()
    _refresh_toggle()
    account.send_server({"type": "chat_sync", "match_id": match_id})

func unbind():
    controller = null
    open_mobile = false
    panel.hide()
    if restore_button != null: restore_button.hide()
    if input.has_focus(): input.release_focus()

func active() -> bool:
    return controller != null

# ---------- Envio ----------
func send_current():
    var text = input.text.strip_edges()
    if text.is_empty() or match_id.is_empty(): return
    if text.length() > MAX_LEN:
        _show_status("Mensagem longa demais (máx. %d caracteres)." % MAX_LEN)
        return
    if account.send_server({"type": "chat_send", "match_id": match_id, "text": text}):
        input.clear()
        status.hide()
    else:
        _show_status("Sem conexão. Tente de novo em instantes.")

func _toggle_mute():
    muted = not muted
    mute_button.text = "REATIVAR" if muted else "SILENCIAR"
    _rebuild()

func _report():
    if reported or match_id.is_empty(): return
    account.send_server({"type": "chat_report", "match_id": match_id})

# ---------- Mensagens do servidor ----------
func _on_message(msg: Dictionary):
    var type = String(msg.get("type", ""))
    if not type.begins_with("chat_") or String(msg.get("match_id", match_id)) != match_id: return
    match type:
        "chat_msg":
            messages.append(msg)
            if messages.size() > 80: messages.pop_front()
            if not (muted and String(msg.get("from_color", "")) != my_color):
                _add_line(msg)
                if String(msg.get("from_color", "")) != my_color and not _visible_now():
                    unread += 1
                    _refresh_toggle()
        "chat_history":
            messages = Array(msg.get("messages", [])) if msg.get("messages") is Array else []
            _rebuild()
        "chat_error":
            _show_status(String(msg.get("message", "Não foi possível enviar.")))
        "chat_report_ok":
            reported = true
            report_button.disabled = true
            report_button.text = "DENUNCIADO"
            _show_status("Denúncia enviada. Obrigado!", Color("c4cbbd"))

func _visible_now() -> bool:
    if Mobile.active(get_viewport()): return panel.visible and open_mobile
    return panel.visible and not minimized

func _show_status(text: String, color := Color("ff9d86")):
    status.text = text
    status.add_theme_color_override("font_color", color)
    status.show()

func _rebuild():
    for child in list.get_children():
        list.remove_child(child)
        child.queue_free()
    var hidden = 0
    for m in messages:
        if muted and String(m.get("from_color", "")) != my_color:
            hidden += 1
            continue
        _add_line(m, false)
    if muted:
        var note = Label.new()
        note.text = "Adversário silenciado (%d mensagem(ns) oculta(s))." % hidden
        note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        note.add_theme_color_override("font_color", Color("a9b2a4"))
        list.add_child(note)
    _scroll_end()

func _add_line(m: Dictionary, scroll_now := true):
    var mine = String(m.get("from_color", "")) == my_color
    var line = Label.new()
    # Label comum (sem BBCode): o texto do jogador nunca vira formatação.
    line.text = "%s: %s" % [("Você" if mine else String(m.get("nickname", "Adversário"))), String(m.get("text", ""))]
    line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    line.add_theme_color_override("font_color", GOLD if mine else Color("efe3c4"))
    line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    list.add_child(line)
    if scroll_now: _scroll_end()

func _scroll_end():
    await get_tree().process_frame
    if is_instance_valid(scroll): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

# ---------- Layout ----------
func set_minimized(value: bool):
    minimized = value
    if value:
        if input.has_focus(): input.release_focus()
    else:
        unread = 0
    _refresh_toggle()
    layout_needed.emit()

func set_mobile_open(value: bool):
    open_mobile = value
    if value:
        unread = 0
    elif input.has_focus():
        input.release_focus()
    _refresh_toggle()
    layout_needed.emit()

func _refresh_toggle():
    var t := ("CHAT (%d)" % unread) if unread > 0 else "CHAT"
    toggle_button.text = t
    if restore_button != null: restore_button.text = t

## Desktop: painel à esquerda do tabuleiro (coordenadas 1920x1080). Mobile: folha sobre a parte de baixo.
func layout(board: Rect2, mobile: bool, safe: Rect2):
    if not active():
        panel.hide()
        restore_button.hide()
        return
    var fonts = 15 if mobile else 20
    for node in [title, mute_button, report_button, close_button, input, send_button, status]:
        node.add_theme_font_size_override("font_size", fonts)
    for child in list.get_children(): child.add_theme_font_size_override("font_size", fonts)
    close_button.visible = mobile
    minimize_button.visible = not mobile
    input.custom_minimum_size.y = 44 if mobile else 48
    send_button.custom_minimum_size = Vector2(0, 44 if mobile else 48)
    if mobile:
        restore_button.hide()
        panel.visible = open_mobile
        var h = minf(safe.size.y * 0.62, 460.0)
        panel.position = Vector2(safe.position.x, safe.end.y - h - 52.0)
        panel.size = Vector2(safe.size.x, h)
        return
    # Desktop minimizado: só o botão CHAT no canto do tabuleiro.
    restore_button.visible = minimized
    if minimized:
        panel.visible = false
        restore_button.add_theme_font_size_override("font_size", 20)
        restore_button.size = Vector2(170, 52)
        restore_button.position = Vector2(maxf(safe.position.x + 8.0, board.position.x - 190.0), board.end.y - 52.0)
        return
    panel.visible = true
    var left_space = board.position.x - safe.position.x - 36.0
    if left_space >= 260.0:
        var width = minf(440.0, left_space)
        panel.position = Vector2(board.position.x - width - 28.0, board.position.y)
        panel.size = Vector2(width, board.size.y)
        return
    # Tela estreita/quadrada: usa a faixa abaixo (ou acima) do tabuleiro.
    var below = safe.end.y - board.end.y - 90.0
    var above = board.position.y - safe.position.y - 16.0
    var h = maxf(below, above)
    panel.size = Vector2(minf(board.size.x, 560.0), clampf(h, 120.0, 320.0))
    panel.position = Vector2(board.get_center().x - panel.size.x / 2.0, (board.end.y + 12.0) if below >= above else (board.position.y - panel.size.y - 8.0))
