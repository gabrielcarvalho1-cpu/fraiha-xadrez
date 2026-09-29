extends CanvasLayer
## AMIGOS: lista (online / em partida / offline / pedidos / bloqueados), busca por nickname,
## perfil público e ações por relação. O servidor decide tudo; aqui só pedimos e mostramos.
## Nunca mostra e-mail. Texto de jogador sempre em Label comum (sem BBCode).
signal closed
const Mobile = preload("res://ui_v022/mobile_layout.gd")
const GOLD = Color("f4ce7f")
const TEXT = Color("efe3c4")
const DIM_TEXT = Color("a9b2a4")
const ERROR = Color("ff9d86")
const LEAGUES = ["Madeira","Ferro","Bronze","Prata","Ouro","Platina","Esmeralda","Diamante","Mestre","Grande Mestre","Challenger"]
const MODES = [["ranked_3min", "RELÂMPAGO"], ["ranked_5min", "RÁPIDA"], ["ranked_10min", "NORMAL"], ["ranked_20min", "CONVENCIONAL"]]
const PRESENCE = {"online": ["ONLINE", Color("7fd98a")], "in_match": ["EM PARTIDA", Color("f4ce7f")], "offline": ["OFFLINE", Color("8d968a")]}
const REFRESH_S := 20.0
var account
var avatar_for: Callable        # id -> Texture2D (usa os avatares da Home)
var dim: ColorRect
var panel: PanelContainer
var scroll: ScrollContainer
var box: VBoxContainer
var notice: Label
var search_input: LineEdit
var toast: PanelContainer
var toast_label: Label
var toast_left := 0.0
var screen := ""
var data := {"friends": [], "received": [], "sent": [], "blocked": []}
var has_list := false
var results: Array = []
var last_query := ""
var profile: Dictionary = {}
var profile_id := ""
var confirm: Dictionary = {}
var refresh_left := REFRESH_S
var pending_text := ""

func setup(service, avatar_callable: Callable = Callable()):
    account = service
    avatar_for = avatar_callable
    layer = 55
    dim = ColorRect.new()
    dim.color = Color(0.02, 0.04, 0.03, 0.82)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    panel = PanelContainer.new()
    panel.name = "FriendsPanel"
    var style = StyleBoxFlat.new()
    style.bg_color = Color("#142217f7")
    style.border_color = Color("#b19758")
    style.set_border_width_all(2)
    style.set_corner_radius_all(8)
    for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 14)
    panel.add_theme_stylebox_override("panel", style)
    add_child(panel)
    scroll = ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    panel.add_child(scroll)
    box = VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 8)
    scroll.add_child(box)
    toast = PanelContainer.new()
    toast.name = "FriendsToast"
    var ts = style.duplicate()
    ts.bg_color = Color("#1d3322f2")
    for side in ["left", "right", "top", "bottom"]: ts.set("content_margin_" + side, 10)
    toast.add_theme_stylebox_override("panel", ts)
    toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
    toast_label = Label.new()
    toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    toast_label.add_theme_color_override("font_color", TEXT)
    toast.add_child(toast_label)
    add_child(toast)
    toast.hide()
    account.server_message.connect(_on_message)
    # Conta ainda conectando: mostra aqui o motivo se o servidor recusar a sessão.
    account.notice.connect(func(text, is_error): if is_open() and is_error and not account.has_profile(): notice_text(text))
    account.changed.connect(func(): if is_open() and screen == "list" and not has_list: _request_list())
    get_viewport().size_changed.connect(_layout)
    hide_ui()

# ---------- Abrir / fechar ----------
func is_open() -> bool:
    return panel.visible

func open():
    notice_text("")
    _show("list")
    _request_list()

func hide_ui():
    screen = ""
    dim.hide(); panel.hide()
    if is_instance_valid(search_input) and search_input.has_focus(): search_input.release_focus()

func close():
    hide_ui()
    closed.emit()

func _input(event):
    if not is_open(): return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        _back()
        get_viewport().set_input_as_handled()

func _back():
    match screen:
        "list": close()
        "confirm": _show(String(confirm.get("return", "profile")))
        "profile": _show("search" if not last_query.is_empty() and profile.get("from_search", false) else "list")
        _: _show("list")

func _request_list():
    refresh_left = REFRESH_S
    if not _send({"type": "social_list"}) and screen == "list":
        notice_text("Conectando sua conta ao servidor...", GOLD)

func _send(msg: Dictionary) -> bool:
    if not account.has_profile(): return false
    return account.send_server(msg)

func _act(action: String, uid: String):
    if not _send({"type": "social_" + action, "user_id": uid}):
        notice_text("Sem conexão. Tente de novo em instantes.")

func search(query: String):
    query = query.strip_edges()
    if query.length() < 2:
        notice_text("Digite ao menos 2 letras do nickname.")
        return
    last_query = query
    if _send({"type": "social_search", "query": query}):
        pending_text = "Buscando…"
        notice_text(pending_text, GOLD)
    else:
        notice_text("Sem conexão. Tente de novo em instantes.")

func open_profile(uid: String, from_search := false):
    profile_id = uid
    profile = {"user_id": uid, "loading": true, "from_search": from_search}
    _show("profile")
    if not _send({"type": "social_profile", "user_id": uid}):
        notice_text("Sem conexão. Tente de novo em instantes.")

# ---------- Mensagens do servidor ----------
func _on_message(msg: Dictionary):
    var type = String(msg.get("type", ""))
    if not type.begins_with("social_"): return
    match type:
        "social_list":
            data = {"friends": _arr(msg, "friends"), "received": _arr(msg, "received"), "sent": _arr(msg, "sent"), "blocked": _arr(msg, "blocked")}
            has_list = true
            if screen == "list": _show("list")
        "social_search":
            results = _arr(msg, "results")
            last_query = String(msg.get("query", last_query))
            if is_open(): _show("search")
        "social_profile":
            var p: Dictionary = msg.get("profile", {}) if msg.get("profile") is Dictionary else {}
            if String(p.get("user_id", "")) != profile_id: return
            p["from_search"] = profile.get("from_search", false)
            profile = p
            if screen == "profile": _show("profile")
        "social_ok":
            var uid = String(msg.get("user_id", ""))
            var rel = String(msg.get("relation", ""))
            for r in results:
                if String(r.get("user_id", "")) == uid: r["relation"] = rel
            if uid == profile_id and not profile.is_empty():
                profile["relation"] = rel
            notice_text(_ok_text(String(msg.get("action", ""))), Color("9fe0a8"))
            if screen == "profile" or screen == "confirm":
                _show("profile")
                notice_text(_ok_text(String(msg.get("action", ""))), Color("9fe0a8"))
            elif screen == "search": _show("search")
        "social_error":
            var code = String(msg.get("code", ""))
            if code == "reverse_pending":
                open_profile(String(msg.get("user_id", "")), profile.get("from_search", false))
            if code == "not_found" and screen == "profile" and profile.get("loading", false):
                profile = {"user_id": profile_id, "missing": true}
                _show("profile")
            notice_text(String(msg.get("message", "Não foi possível concluir.")))
        "social_event":
            var who: Dictionary = msg.get("user", {}) if msg.get("user") is Dictionary else {}
            var nick = String(who.get("nickname", "Alguém"))
            match String(msg.get("event", "")):
                "request_received": show_toast("%s te enviou um pedido de amizade." % nick)
                "request_accepted": show_toast("%s aceitou seu pedido de amizade." % nick)

func _arr(msg: Dictionary, key: String) -> Array:
    return Array(msg.get(key, [])) if msg.get(key) is Array else []

func _ok_text(action: String) -> String:
    match action:
        "request": return "Pedido de amizade enviado."
        "accept": return "Pedido aceito. Agora vocês são amigos!"
        "decline": return "Pedido recusado."
        "cancel": return "Pedido cancelado."
        "remove": return "Amizade removida."
        "block": return "Jogador bloqueado."
        "unblock": return "Jogador desbloqueado."
    return "Pronto."

func show_toast(text: String):
    toast_label.text = text
    toast.show()
    toast_left = 4.5
    _layout_toast()

func _process(delta):
    if toast.visible:
        toast_left -= delta
        if toast_left <= 0.0: toast.hide()
    if is_open() and screen == "list":
        refresh_left -= delta
        if refresh_left <= 0.0: _request_list()
    if is_open(): _layout()

# ---------- Construção das telas ----------
func _clear():
    for child in box.get_children():
        box.remove_child(child)
        child.queue_free()
    search_input = null

func notice_text(text: String, color := ERROR):
    if not is_instance_valid(notice): return
    notice.text = text
    notice.visible = not text.is_empty()
    notice.add_theme_color_override("font_color", color)

func _label(parent: Node, text: String, size := 16, color := TEXT, center := false) -> Label:
    var l = Label.new()
    l.text = text
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    parent.add_child(l)
    return l

func _button(parent: Node, text: String, action: Callable, primary := false, small := false) -> Button:
    var b = Button.new()
    b.text = text
    b.focus_mode = Control.FOCUS_NONE
    b.custom_minimum_size.y = 38 if small else 46
    b.add_theme_font_size_override("font_size", 14 if small else 16)
    var style = StyleBoxFlat.new()
    style.bg_color = Color("2c4a2f") if primary else Color("14221d")
    style.border_color = GOLD if primary else Color("84754b")
    style.set_border_width_all(1)
    style.set_corner_radius_all(6)
    style.content_margin_left = 8 if small else 12
    style.content_margin_right = 8 if small else 12
    b.add_theme_stylebox_override("normal", style)
    var hover = style.duplicate()
    hover.bg_color = Color("36593a")
    for state in ["hover", "pressed"]: b.add_theme_stylebox_override(state, hover)
    var off = style.duplicate()
    off.bg_color = Color("101a16")
    off.border_color = Color("4b4a3a")
    b.add_theme_stylebox_override("disabled", off)
    b.add_theme_color_override("font_color", Color("f4edda"))
    b.add_theme_color_override("font_disabled_color", Color("7d8479"))
    b.pressed.connect(action)
    parent.add_child(b)
    return b

func _avatar(parent: Node, id: String, px: int) -> TextureRect:
    var t = TextureRect.new()
    t.custom_minimum_size = Vector2(px, px)
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    t.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if avatar_for.is_valid(): t.texture = avatar_for.call(id if id in ["warrior", "archer", "mage", "paladin"] else "warrior")
    parent.add_child(t)
    return t

func _section(title: String, count: int):
    var l = _label(box, "%s (%d)" % [title, count], 15, GOLD)
    l.name = "Section_" + title.replace(" ", "_")
    var line = ColorRect.new()
    line.color = Color("84754b")
    line.custom_minimum_size.y = 1
    box.add_child(line)

## Linha de jogador: avatar + nickname (toque abre o perfil) + status + botões de ação.
func _row(p: Dictionary, status_text: String, status_color: Color, actions: Array) -> HBoxContainer:
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.set_meta("user_id", String(p.get("user_id", "")))
    box.add_child(row)
    _avatar(row, String(p.get("avatar_id", "warrior")), 40)
    var col = VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.add_theme_constant_override("separation", 0)
    row.add_child(col)
    var name_btn = Button.new()
    name_btn.text = String(p.get("nickname", "?"))
    name_btn.flat = true
    name_btn.clip_text = true
    name_btn.custom_minimum_size.x = 40
    name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
    name_btn.focus_mode = Control.FOCUS_NONE
    name_btn.add_theme_font_size_override("font_size", 16)
    name_btn.add_theme_color_override("font_color", Color("f4edda"))
    name_btn.tooltip_text = "Ver perfil"
    var plain = StyleBoxEmpty.new()
    for state in ["normal", "hover", "pressed", "focus"]: name_btn.add_theme_stylebox_override(state, plain)
    name_btn.add_theme_color_override("font_hover_color", GOLD)
    var uid = String(p.get("user_id", ""))
    name_btn.pressed.connect(func(): open_profile(uid, screen == "search"))
    col.add_child(name_btn)
    if not status_text.is_empty():
        var st = _label(col, status_text, 13, status_color)
        st.autowrap_mode = TextServer.AUTOWRAP_OFF
        st.clip_text = true
    for a in actions:
        _button(row, a[0], a[1], a.size() > 2 and a[2], true)
    return row

func _show(which: String):
    screen = which
    _clear()
    var narrow = _narrow()
    var head = HBoxContainer.new()
    head.add_theme_constant_override("separation", 8)
    box.add_child(head)
    var back = _button(head, "VOLTAR", _back, false, true)
    back.name = "FriendsBack"
    var title = _label(head, "AMIGOS", 22, GOLD, true)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.autowrap_mode = TextServer.AUTOWRAP_OFF
    var spacer = Control.new()
    spacer.custom_minimum_size.x = back.get_combined_minimum_size().x
    head.add_child(spacer)
    notice = _label(box, "", 14, ERROR, true)
    notice.name = "FriendsNotice"
    notice.hide()
    match which:
        "list", "search":
            var srow = HBoxContainer.new()
            srow.add_theme_constant_override("separation", 6)
            box.add_child(srow)
            search_input = LineEdit.new()
            search_input.name = "FriendSearch"
            search_input.placeholder_text = "Buscar jogador pelo nickname"
            search_input.max_length = 16
            search_input.text = last_query if which == "search" else ""
            search_input.custom_minimum_size.y = 44
            search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            search_input.add_theme_font_size_override("font_size", 16)
            search_input.text_submitted.connect(func(t): search(t))
            srow.add_child(search_input)
            var input_ref = search_input
            _button(srow, "BUSCAR", func(): search(input_ref.text), true, true).custom_minimum_size.y = 44
            if which == "search": _build_search()
            else: _build_list(narrow)
        "profile": _build_profile(narrow)
        "confirm": _build_confirm()
    dim.show(); panel.show()
    _layout()
    _layout.call_deferred()

func _build_list(_narrow_layout: bool):
    if not has_list:
        _label(box, "Carregando amigos…" if account.has_profile() else "Conectando sua conta ao servidor...", 15, GOLD, true)
        return
    var friends: Array = data["friends"]
    var groups = {"online": [], "in_match": [], "offline": []}
    for f in friends: groups.get(String(f.get("presence", "offline")), groups["offline"]).append(f)
    if data["received"].size():
        _section("PEDIDOS RECEBIDOS", data["received"].size())
        for p in data["received"]:
            var uid = String(p.get("user_id", ""))
            _row(p, "novo pedido", GOLD, [["ACEITAR", func(): _act("accept", uid), true], ["RECUSAR", func(): _act("decline", uid)]])
    for key in ["online", "in_match", "offline"]:
        var title = PRESENCE[key][0]
        _section(title, groups[key].size())
        if groups[key].is_empty():
            _label(box, "Ninguém por aqui." if friends.size() else ("Você ainda não tem amigos. Busque pelo nickname acima." if key == "online" else "—"), 13, DIM_TEXT)
        for f in groups[key]:
            _row(f, PRESENCE[key][0].capitalize() if key != "in_match" else "Em partida", PRESENCE[key][1], [])
    if data["sent"].size():
        _section("PEDIDOS ENVIADOS", data["sent"].size())
        for p in data["sent"]:
            var uid = String(p.get("user_id", ""))
            _row(p, "aguardando resposta", DIM_TEXT, [["CANCELAR", func(): _act("cancel", uid)]])
    if data["blocked"].size():
        _section("BLOQUEADOS", data["blocked"].size())
        for p in data["blocked"]:
            var uid = String(p.get("user_id", ""))
            _row(p, "bloqueado", DIM_TEXT, [["DESBLOQUEAR", func(): _act("unblock", uid)]])

func _build_search():
    _label(box, "Resultados para \"%s\"" % last_query, 15, GOLD)
    if results.is_empty():
        _label(box, "Nenhum jogador encontrado com esse nickname.", 15, DIM_TEXT, true)
    for p in results:
        var uid = String(p.get("user_id", ""))
        var rel = String(p.get("relation", "none"))
        var actions := []
        var status := ""
        match rel:
            "none": actions = [["ADICIONAR", func(): _act("request", uid), true]]
            "friend": status = "amigo"
            "request_sent": status = "pedido enviado"
            "request_received": actions = [["ACEITAR", func(): _act("accept", uid), true]]; status = "novo pedido"
            "blocked": status = "bloqueado"
        _row(p, status, DIM_TEXT, actions)
    _button(box, "VOLTAR PARA A LISTA", func():
        last_query = ""
        _show("list"))

func _build_profile(narrow: bool):
    if profile.get("missing", false):
        _label(box, "Jogador não encontrado.", 16, DIM_TEXT, true)
        return
    if profile.get("loading", false):
        _label(box, "Carregando perfil…", 16, GOLD, true)
        return
    var top = HBoxContainer.new() if not narrow else VBoxContainer.new()
    top.add_theme_constant_override("separation", 12)
    box.add_child(top)
    var av = _avatar(top, String(profile.get("avatar_id", "warrior")), 88)
    if narrow: av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    var info = VBoxContainer.new()
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(info)
    var nick = _label(info, String(profile.get("nickname", "")), 24, Color("f4edda"), narrow)
    nick.name = "ProfileNickname"
    var pres = String(profile.get("presence", "offline"))
    var pinfo = PRESENCE.get(pres, PRESENCE["offline"])
    _label(info, "● " + pinfo[0], 15, pinfo[1], narrow).name = "ProfilePresence"
    var hl = int(profile.get("highest_league", 0))
    _label(info, "Maior liga: " + LEAGUES[clampi(hl, 0, 10)], 15, GOLD, narrow).name = "ProfileHighest"
    _label(box, "RANQUEADO", 15, GOLD)
    var ranked: Dictionary = profile.get("ranked", {}) if profile.get("ranked") is Dictionary else {}
    var grid = GridContainer.new()
    grid.columns = 1 if narrow else 2
    grid.add_theme_constant_override("h_separation", 14)
    grid.add_theme_constant_override("v_separation", 4)
    box.add_child(grid)
    for m in MODES:
        var s: Dictionary = ranked.get(m[0], {}) if ranked.get(m[0]) is Dictionary else {}
        var line = "%s · %s %d PL\n%dV %dD %dE · %d partidas" % [m[1], LEAGUES[clampi(int(s.get("league", 0)), 0, 10)], int(s.get("pl", 0)), int(s.get("wins", 0)), int(s.get("losses", 0)), int(s.get("draws", 0)), int(s.get("matches", 0))]
        var l = _label(grid, line, 14, TEXT)
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var uid = String(profile.get("user_id", ""))
    var nickname = String(profile.get("nickname", ""))
    var actions = VBoxContainer.new()
    actions.name = "ProfileActions"
    actions.add_theme_constant_override("separation", 8)
    box.add_child(actions)
    match String(profile.get("relation", "none")):
        "none":
            _button(actions, "ADICIONAR AMIGO", func(): _act("request", uid), true)
        "request_sent":
            _label(actions, "Pedido de amizade enviado. Aguardando resposta.", 14, DIM_TEXT, true)
            _button(actions, "CANCELAR PEDIDO", func(): _act("cancel", uid))
        "request_received":
            _label(actions, "%s quer ser seu amigo." % nickname, 14, GOLD, true)
            _button(actions, "ACEITAR PEDIDO", func(): _act("accept", uid), true)
            _button(actions, "RECUSAR PEDIDO", func(): _act("decline", uid))
        "friend":
            # MENSAGEM e CONVIDAR chegam nas próximas etapas (DM e convites).
            var dm = _button(actions, "MENSAGEM (em breve)", func(): pass)
            dm.name = "ProfileMessage"
            dm.disabled = true
            var inv = _button(actions, "CONVIDAR PARA JOGAR (em breve)", func(): pass)
            inv.name = "ProfileInvite"
            inv.disabled = true
            _button(actions, "REMOVER AMIGO", func(): _ask("remove", uid, "REMOVER AMIGO?", "%s deixará de ser seu amigo. Vocês podem voltar a se adicionar depois." % nickname))
    if String(profile.get("relation", "")) == "blocked":
        _label(actions, "Você bloqueou este jogador: ele não pode te enviar pedidos.", 14, DIM_TEXT, true)
        _button(actions, "DESBLOQUEAR", func(): _act("unblock", uid))
    else:
        _button(actions, "BLOQUEAR", func(): _ask("block", uid, "BLOQUEAR JOGADOR?", "%s não poderá te enviar pedidos, mensagens ou convites, e deixa de te encontrar na busca. A amizade (se houver) é desfeita." % nickname))

func _ask(action: String, uid: String, title: String, text: String):
    confirm = {"action": action, "user_id": uid, "title": title, "text": text, "return": "profile"}
    _show("confirm")

func _build_confirm():
    _label(box, String(confirm.get("title", "")), 20, GOLD, true)
    _label(box, String(confirm.get("text", "")), 16, TEXT, true)
    var action = String(confirm.get("action", ""))
    var uid = String(confirm.get("user_id", ""))
    _button(box, "CONFIRMAR", func(): _act(action, uid), true)
    _button(box, "CANCELAR", func(): _show("profile"))

# ---------- Layout ----------
func _narrow() -> bool:
    return get_viewport().get_visible_rect().size.x < 700.0 or (Mobile.active(get_viewport()) and Mobile.is_portrait(get_viewport()))

func _layout():
    if not panel.visible: return
    var mobile = Mobile.active(get_viewport())
    var area = Mobile.safe_rect(get_viewport()) if mobile else get_viewport().get_visible_rect()
    dim.size = get_viewport().get_visible_rect().size
    var ui_scale = 1.0 if mobile else 1.4
    panel.scale = Vector2.ONE * ui_scale
    var width = minf(560.0, (area.size.x - 16.0) / ui_scale)
    box.custom_minimum_size.x = width - 28.0
    var wanted = box.get_combined_minimum_size().y + 28.0
    var height = minf(maxf(wanted, 0.0), (area.size.y - 16.0) / ui_scale)
    scroll.custom_minimum_size = Vector2(width - 28.0, height - 28.0)
    panel.custom_minimum_size = Vector2.ZERO
    panel.reset_size()
    panel.size = Vector2(width, height)
    panel.position = area.position + (area.size - panel.size * ui_scale) / 2.0
    _layout_toast()

func _layout_toast():
    if not toast.visible: return
    var mobile = Mobile.active(get_viewport())
    var area = Mobile.safe_rect(get_viewport()) if mobile else get_viewport().get_visible_rect()
    var s = 1.0 if mobile else 1.4
    toast.scale = Vector2.ONE * s
    toast_label.add_theme_font_size_override("font_size", 15)
    var w = minf(460.0, (area.size.x - 24.0) / s)
    toast_label.custom_minimum_size.x = w - 20.0
    toast.reset_size()
    toast.size.x = w
    toast.position = Vector2(area.position.x + (area.size.x - w * s) / 2.0, area.position.y + 12.0)
