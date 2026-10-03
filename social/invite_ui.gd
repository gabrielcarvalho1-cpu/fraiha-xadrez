extends CanvasLayer
## Cartão de CONVITE para partida Casual (recebido ou enviado). O servidor decide tudo:
## este cartão só mostra o estado e pede aceitar/recusar/cancelar. Nunca aparece por cima de uma partida online.
const Mobile = preload("res://ui_v022/mobile_layout.gd")
const GOLD = Color("f4ce7f")
const TEXT = Color("efe3c4")
const DIM_TEXT = Color("a9b2a4")
const ERROR = Color("ff9d86")
var account
var avatar_for: Callable
var hidden_when: Callable      # () -> bool: true durante partida online
var panel: PanelContainer
var box: VBoxContainer
var invite: Dictionary = {}    # convite aberto (pending/starting) do ponto de vista deste jogador
var left_ms := 0.0
var starting := false
var countdown: Label
var status_label: Label
var accept_button: Button
var decline_button: Button
var cancel_button: Button
var flash_left := 0.0          # mensagem final (recusado/expirado/cancelado) visível por alguns segundos

func setup(service, avatar_callable: Callable = Callable(), hide_fn: Callable = Callable()):
    account = service
    avatar_for = avatar_callable
    hidden_when = hide_fn
    layer = 58
    panel = PanelContainer.new()
    panel.name = "InviteCard"
    var style = StyleBoxFlat.new()
    style.bg_color = Color("#16281cf7")
    style.border_color = GOLD
    style.set_border_width_all(2)
    style.set_corner_radius_all(8)
    for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 12)
    panel.add_theme_stylebox_override("panel", style)
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(panel)
    box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 8)
    panel.add_child(box)
    panel.hide()
    account.server_message.connect(_on_message)
    account.changed.connect(func(): if not account.has_profile(): _clear())
    get_viewport().size_changed.connect(_layout)

func has_invite() -> bool:
    return not invite.is_empty()

func role() -> String:
    return String(invite.get("role", ""))

# ---------- Ações ----------
func accept():
    if not has_invite() or role() != "recipient" or starting: return
    starting = true   # "Iniciando…" bloqueia clique repetido
    _refresh_buttons()
    _status("Iniciando partida…")
    if not account.send_server({"type": "invite_accept", "invite_id": String(invite.get("id", ""))}):
        starting = false
        _refresh_buttons()
        _status("Sem conexão. Tente de novo.", ERROR)

func decline():
    if has_invite() and role() == "recipient" and not starting:
        account.send_server({"type": "invite_decline", "invite_id": String(invite.get("id", ""))})

func cancel():
    if has_invite() and role() == "sender" and not starting:
        account.send_server({"type": "invite_cancel", "invite_id": String(invite.get("id", ""))})

# ---------- Mensagens do servidor ----------
func _on_message(msg: Dictionary):
    var type = String(msg.get("type", ""))
    if not type.begins_with("invite_"): return
    var inv: Dictionary = msg.get("invite", {}) if msg.get("invite") is Dictionary else {}
    match type:
        "invite_received", "invite_sent":
            _set_invite(inv)
        "invite_snapshot":
            var list: Array = msg.get("invites", []) if msg.get("invites") is Array else []
            if list.is_empty(): _clear()
            else: _set_invite(list[0])
        "invite_updated":
            if inv.is_empty(): return
            if has_invite() and String(inv.get("id", "")) != String(invite.get("id", "")): return
            var st = String(inv.get("status", ""))
            if st == "pending" or st == "starting":
                _set_invite(inv)
            elif st == "accepted":
                _clear()   # a partida Casual abre sozinha (casual_found)
            elif has_invite():
                _finish(String(inv.get("message", "")) if inv.has("message") else _final_text(st))
        "invite_error":
            if has_invite() and panel.visible and (String(msg.get("invite_id", "")) == String(invite.get("id", "")) or starting or String(inv.get("id", "")) == String(invite.get("id", ""))):
                starting = false
                _refresh_buttons()
                _status(String(msg.get("message", "Não foi possível concluir.")), ERROR)

func _final_text(st: String) -> String:
    match st:
        "declined": return "Convite recusado."
        "cancelled": return "Convite cancelado."
        "expired": return "O convite expirou."
        "failed": return "Não foi possível iniciar a partida."
    return "Convite encerrado."

func _set_invite(inv: Dictionary):
    if inv.is_empty(): return
    var same = has_invite() and String(inv.get("id", "")) == String(invite.get("id", ""))
    invite = inv
    left_ms = float(inv.get("expires_in_ms", 0))
    starting = String(inv.get("status", "")) == "starting"
    flash_left = 0.0
    if not same or not is_instance_valid(countdown): _build()
    else: _refresh_buttons()
    if starting and is_instance_valid(status_label): _status("Iniciando partida…")

func _clear():
    invite = {}
    starting = false
    flash_left = 0.0
    panel.hide()

func _finish(text: String):
    invite = {}
    starting = false
    for child in box.get_children():
        box.remove_child(child)
        child.queue_free()
    var l = _label(text, 16, TEXT, true)
    l.name = "InviteFinal"
    flash_left = 3.5
    _update_visibility()
    _layout()

# ---------- Construção ----------
func _label(text: String, size := 16, color := TEXT, center := false) -> Label:
    var l = Label.new()
    l.text = text
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(l)
    return l

func _button(parent: Node, text: String, action: Callable, primary := false) -> Button:
    var b = Button.new()
    b.text = text
    b.focus_mode = Control.FOCUS_NONE
    b.custom_minimum_size = Vector2(0, 50)   # alvo grande para toque; sem depender de hover
    b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    b.add_theme_font_size_override("font_size", 17)
    var st = StyleBoxFlat.new()
    st.bg_color = Color("2c4a2f") if primary else Color("14221d")
    st.border_color = GOLD if primary else Color("84754b")
    st.set_border_width_all(1)
    st.set_corner_radius_all(6)
    b.add_theme_stylebox_override("normal", st)
    var hi = st.duplicate()
    hi.bg_color = Color("36593a")
    for state in ["hover", "pressed"]: b.add_theme_stylebox_override(state, hi)
    var off = st.duplicate()
    off.bg_color = Color("101a16")
    off.border_color = Color("4b4a3a")
    b.add_theme_stylebox_override("disabled", off)
    b.add_theme_color_override("font_color", Color("f4edda"))
    b.add_theme_color_override("font_disabled_color", Color("7d8479"))
    b.pressed.connect(action)
    parent.add_child(b)
    return b

func _build():
    for child in box.get_children():
        box.remove_child(child)
        child.queue_free()
    var incoming = role() == "recipient"
    var other: Dictionary = invite.get("from" if incoming else "to", {})
    var head = HBoxContainer.new()
    head.add_theme_constant_override("separation", 10)
    box.add_child(head)
    var av = TextureRect.new()
    av.custom_minimum_size = Vector2(52, 52)
    av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    var aid = String(other.get("avatar_id", "warrior"))
    if avatar_for.is_valid(): av.texture = avatar_for.call(aid if aid in ["warrior", "archer", "mage", "paladin"] else "warrior")
    head.add_child(av)
    var col = VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(col)
    var title = Label.new()
    title.text = "CONVITE PARA PARTIDA" if incoming else "CONVITE ENVIADO"
    title.add_theme_font_size_override("font_size", 15)
    title.add_theme_color_override("font_color", GOLD)
    col.add_child(title)
    var who = Label.new()
    who.name = "InviteWho"
    who.text = ("%s te convidou" if incoming else "Para %s") % String(other.get("nickname", ""))
    who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    who.add_theme_font_size_override("font_size", 18)
    who.add_theme_color_override("font_color", Color("f4edda"))
    col.add_child(who)
    var game := String(invite.get("game", "chess"))
    var mode_text := "%s · %d min · Casual (sem PL)" % [String(invite.get("mode_name", "")).to_upper(), int(invite.get("minutes", 0))]
    if game == "marcha": mode_text = "MARCHA REAL · vocês em dupla contra 2 bots"
    elif game == "xeque": mode_text = "XEQUE · vocês dois + 2 bots, cada um por si"
    _label(mode_text, 15, TEXT).name = "InviteMode"
    countdown = _label("", 14, DIM_TEXT)
    countdown.name = "InviteCountdown"
    status_label = _label("", 14, GOLD)
    status_label.name = "InviteStatus"
    status_label.hide()
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    box.add_child(row)
    accept_button = null
    decline_button = null
    cancel_button = null
    if incoming:
        accept_button = _button(row, "ACEITAR", accept, true)
        accept_button.name = "InviteAccept"
        decline_button = _button(row, "RECUSAR", decline)
        decline_button.name = "InviteDecline"
    else:
        cancel_button = _button(row, "CANCELAR CONVITE", cancel)
        cancel_button.name = "InviteCancel"
    _refresh_buttons()
    _tick_label()
    _update_visibility()
    _layout()
    _layout.call_deferred()

func _refresh_buttons():
    for b in [accept_button, decline_button, cancel_button]:
        if is_instance_valid(b): b.disabled = starting

func _tick_label():
    if not is_instance_valid(countdown): return
    var s = ceili(maxf(0.0, left_ms) / 1000.0)
    countdown.text = ("Expira em %d s" % s) if role() == "recipient" else ("Aguardando resposta · %d s" % s)

func _process(delta):
    if has_invite():
        left_ms -= delta * 1000.0
        _tick_label()
    elif flash_left > 0.0:
        flash_left -= delta
        if flash_left <= 0.0: panel.hide()
    _update_visibility()

func _update_visibility():
    var blocked = hidden_when.is_valid() and bool(hidden_when.call())
    var want = (has_invite() or flash_left > 0.0) and not blocked
    if panel.visible != want:
        panel.visible = want
        if want: _layout()

func _layout():
    if not panel.visible: return
    var mobile = Mobile.active(get_viewport())
    var area = Mobile.safe_rect(get_viewport()) if mobile else get_viewport().get_visible_rect()
    var s = 1.0 if mobile else 1.4
    panel.scale = Vector2.ONE * s
    var w = minf(460.0, (area.size.x - 16.0) / s)
    box.custom_minimum_size.x = w - 24.0
    panel.reset_size()
    panel.size.x = w
    # Abaixo da faixa dos avisos (toast), centralizado no topo.
    panel.position = Vector2(area.position.x + (area.size.x - w * s) / 2.0, area.position.y + (64.0 if mobile else 90.0))

func _status(text: String, color := GOLD):
    if not is_instance_valid(status_label): return
    status_label.text = text
    status_label.add_theme_color_override("font_color", color)
    status_label.visible = not text.is_empty()
    panel.reset_size()
    _layout()
