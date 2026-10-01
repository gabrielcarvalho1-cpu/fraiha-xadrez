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
# Mensagens privadas (DM)
const DM_MAX := 500
var dm_id := ""
var dm_peer: Dictionary = {}
var dm_messages: Array = []
var dm_has_more := false
var dm_can_send := false
var dm_reason := ""
var dm_loading := false
var dm_error := ""
var dm_return := "list"
var dm_ref := 0
var dm_pending_ref := ""
var dm_scroll: ScrollContainer
var dm_list: VBoxContainer
var dm_input: LineEdit
var dm_to_end := true
# Convites (Casual entre amigos): escolha do tempo; o cartão do convite fica em invite_ui.gd
const INVITE_MODES = [["casual_3min", "RELÂMPAGO", 3], ["casual_5min", "RÁPIDA", 5], ["casual_10min", "NORMAL", 10], ["casual_20min", "CONVENCIONAL", 20]]
var invite_peer: Dictionary = {}
var invite_sending := false
# Presença (Etapa 7): estado publicado pelo servidor; revisão por amigo e época (reinício do servidor).
var presence: Dictionary = {}      # uid -> {"state": String, "rev": int}
var presence_epoch := ""
var reconnecting := false

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
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
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
        "dm": close_dm()
        "invite_pick": _show("profile")
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
    if type.begins_with("dm_"):
        _on_dm(msg)
        return
    if type == "invite_sent" or type == "invite_error":
        _on_invite(msg)
        return
    if type == "presence_snapshot" or type == "presence_update" or type == "link_lost":
        _on_presence(msg)
        return
    if not type.begins_with("social_"): return
    match type:
        "social_list":
            data = {"friends": _arr(msg, "friends"), "received": _arr(msg, "received"), "sent": _arr(msg, "sent"), "blocked": _arr(msg, "blocked")}
            _merge_list_presence(String(msg.get("presence_epoch", "")))
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
    dm_scroll = null
    dm_list = null
    dm_input = null

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
            preload("res://ui_v022/web_text_field.gd").attach(search_input)
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
        "dm": _build_dm()
        "invite_pick": _build_invite_pick()
    if reconnecting and is_instance_valid(notice) and not notice.visible: notice_text("Reconectando…", GOLD)
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
            var fid = String(f.get("user_id", ""))
            var unread = int(f.get("unread", 0))
            var finfo: Dictionary = f
            _row(f, PRESENCE[key][0].capitalize() if key != "in_match" else "Em partida", PRESENCE[key][1],
                [[("MENSAGEM (%d)" % unread) if unread > 0 else "MENSAGEM", func(): open_dm(fid, finfo, "list"), unread > 0]])
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
    var pres = String(profile.get("presence", ""))
    if not pres.is_empty():   # o servidor só envia presença de amigos
        var pinfo = PRESENCE.get(pres, PRESENCE["offline"])
        _label(info, "- " + pinfo[0], 15, pinfo[1], narrow).name = "ProfilePresence"
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
            var peer_info: Dictionary = profile.duplicate()
            var dm = _button(actions, "MENSAGEM", func(): open_dm(uid, peer_info, "profile"), true)
            dm.name = "ProfileMessage"
            var inv_peer: Dictionary = profile.duplicate()
            var inv = _button(actions, "CONVIDAR PARA JOGAR", func(): open_invite(uid, inv_peer), true)
            inv.name = "ProfileInvite"
            var friend_state = String(profile.get("presence", "offline"))
            if friend_state != "online":   # só visual: o servidor continua validando fila/partida/conexão
                inv.disabled = true
                _label(actions, ("%s está em partida agora." % nickname) if friend_state == "in_match" else ("Convite disponível quando %s estiver Online." % nickname), 13, DIM_TEXT, true).name = "InviteUnavailable"
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
    if screen == "dm" and is_instance_valid(dm_scroll):
        # A conversa ocupa o espaço que sobra na tela (sem passar do painel).
        var avail = (area.size.y - 16.0) / ui_scale - 28.0
        var rest = box.get_combined_minimum_size().y - dm_scroll.custom_minimum_size.y
        dm_scroll.custom_minimum_size.y = clampf(avail - rest - 4.0, 120.0, 560.0)
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

# ---------- Mensagens privadas (DM) ----------
## Conversa a dois: "minha" = não enviada pelo amigo (não depende do id local da sessão).
func _is_mine(m: Dictionary, peer_id: String) -> bool:
    return String(m.get("sender_id", "")) != peer_id

func open_dm(uid: String, peer: Dictionary = {}, back_to := "list"):
    dm_id = uid
    dm_peer = {"user_id": uid, "nickname": String(peer.get("nickname", "")), "avatar_id": String(peer.get("avatar_id", "warrior"))}
    dm_messages = []
    dm_has_more = false
    dm_can_send = false
    dm_reason = ""
    dm_error = ""
    dm_loading = true
    dm_return = back_to
    _set_unread(uid, 0, false)
    _show("dm")
    if not _send({"type": "dm_open", "user_id": uid}):
        dm_loading = false
        dm_error = "Sem conexão. Tente de novo em instantes."
        _show("dm")

func close_dm():
    var back = dm_return
    dm_id = ""
    if back == "profile" and not profile.is_empty(): _show("profile")
    else:
        _show("list")
        _request_list()

func send_dm():
    if not is_instance_valid(dm_input) or dm_id.is_empty(): return
    var text = dm_input.text.strip_edges()
    if text.is_empty(): return
    if text.length() > DM_MAX:
        notice_text("Mensagem longa demais (máx. %d caracteres)." % DM_MAX)
        return
    dm_ref += 1
    dm_pending_ref = "c%d" % dm_ref
    if not _send({"type": "dm_send", "user_id": dm_id, "text": text, "client_ref": dm_pending_ref}):
        notice_text("Sem conexão. Tente de novo em instantes.")

func _load_older():
    if dm_messages.is_empty(): return
    _send({"type": "dm_open", "user_id": dm_id, "before_id": int(dm_messages[0].get("id", 0))})

func _set_unread(uid: String, count: int, rebuild := true):
    for f in data["friends"]:
        if String(f.get("user_id", "")) == uid: f["unread"] = count
    if rebuild and screen == "list": _show("list")

func _on_dm(msg: Dictionary):
    var type = String(msg.get("type", ""))
    var uid = String(msg.get("user_id", ""))
    match type:
        "dm_history":
            if uid != dm_id: return
            var rows = _arr(msg, "messages")
            dm_to_end = int(msg.get("before_id", 0)) == 0
            if not dm_to_end: dm_messages = rows + dm_messages
            else: dm_messages = rows
            dm_has_more = bool(msg.get("has_more", false))
            dm_can_send = bool(msg.get("can_send", false))
            dm_reason = String(msg.get("reason", ""))
            var peer = msg.get("peer", {})
            if peer is Dictionary and not peer.is_empty(): dm_peer = peer
            dm_loading = false
            dm_error = ""
            if screen == "dm":
                _show("dm")
                if int(msg.get("before_id", 0)) == 0: _send({"type": "dm_read", "user_id": dm_id})
        "dm_msg":
            var m: Dictionary = msg.get("message", {}) if msg.get("message") is Dictionary else {}
            var mine = _is_mine(m, uid)
            if screen == "dm" and uid == dm_id and is_open():
                if dm_messages.any(func(x): return int(x.get("id", -1)) == int(m.get("id", -2))): return
                dm_messages.append(m)
                if is_instance_valid(dm_list):
                    var empty = dm_list.find_child("DmEmpty", false, false)
                    if empty != null: empty.queue_free()
                    _dm_line(m)
                    _dm_scroll_end()
                # Só limpa o campo na confirmação DESTE envio (não quando a mesma conta envia de outra aba/dispositivo).
                if mine and not dm_pending_ref.is_empty() and String(msg.get("client_ref", "")) == dm_pending_ref and is_instance_valid(dm_input):
                    dm_pending_ref = ""
                    dm_input.clear()
                    notice_text("")
                if not mine: _send({"type": "dm_read", "user_id": dm_id})
            elif not mine:
                var who: Dictionary = msg.get("from", {}) if msg.get("from") is Dictionary else {}
                show_toast("Nova mensagem de %s." % String(who.get("nickname", "um amigo")))
        "dm_unread":
            var counts: Dictionary = msg.get("counts", {}) if msg.get("counts") is Dictionary else {}
            for f in data["friends"]:
                var fid = String(f.get("user_id", ""))
                f["unread"] = 0 if (screen == "dm" and fid == dm_id) else int(counts.get(fid, 0))
            if screen == "list": _show("list")
        "dm_error":
            if screen == "dm" and (uid.is_empty() or uid == dm_id):
                if dm_loading:
                    dm_loading = false
                    dm_error = String(msg.get("message", "Não foi possível abrir a conversa."))
                    _show("dm")
                else:
                    notice_text(String(msg.get("message", "Não foi possível enviar.")))
            elif is_open():
                notice_text(String(msg.get("message", "Não foi possível concluir.")))

func _build_dm():
    var head = HBoxContainer.new()
    head.add_theme_constant_override("separation", 10)
    box.add_child(head)
    _avatar(head, String(dm_peer.get("avatar_id", "warrior")), 44)
    var col = VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(col)
    var nick = _label(col, String(dm_peer.get("nickname", "")), 19, Color("f4edda"))
    nick.name = "DmPeer"
    var dm_pres = _label(col, _dm_presence_text(), 13, DIM_TEXT)
    dm_pres.name = "DmPresence"
    dm_scroll = ScrollContainer.new()
    preload("res://ui_v022/touch_scroll.gd").attach(dm_scroll)
    dm_scroll.name = "DmScroll"
    dm_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    dm_scroll.custom_minimum_size.y = 240
    var bg = StyleBoxFlat.new()
    bg.bg_color = Color(0.03, 0.06, 0.05, 0.75)
    bg.border_color = Color("3d4a3a")
    bg.set_border_width_all(1)
    bg.set_corner_radius_all(6)
    for side in ["left", "right", "top", "bottom"]: bg.set("content_margin_" + side, 8)
    dm_scroll.add_theme_stylebox_override("panel", bg)
    box.add_child(dm_scroll)
    dm_list = VBoxContainer.new()
    dm_list.name = "DmList"
    dm_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    dm_list.add_theme_constant_override("separation", 6)
    dm_scroll.add_child(dm_list)
    if dm_loading:
        _label(dm_list, "Carregando conversa…", 15, GOLD, true)
    elif not dm_error.is_empty():
        _label(dm_list, dm_error, 15, ERROR, true).name = "DmError"
    else:
        if dm_has_more:
            _button(dm_list, "CARREGAR ANTERIORES", _load_older, false, true)
        if dm_messages.is_empty():
            _label(dm_list, "Nenhuma mensagem ainda. Diga olá!", 14, DIM_TEXT, true).name = "DmEmpty"
        for m in dm_messages: _dm_line(m)
    if not dm_loading and dm_error.is_empty() and not dm_can_send:
        _label(box, dm_reason if not dm_reason.is_empty() else "Não é possível enviar mensagens nesta conversa.", 14, DIM_TEXT, true).name = "DmReason"
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)
    box.add_child(row)
    dm_input = LineEdit.new()
    preload("res://ui_v022/web_text_field.gd").attach(dm_input)
    dm_input.name = "DmInput"
    dm_input.placeholder_text = "Mensagem para %s" % String(dm_peer.get("nickname", "amigo"))
    dm_input.max_length = DM_MAX
    dm_input.custom_minimum_size.y = 44
    dm_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    dm_input.add_theme_font_size_override("font_size", 16)
    dm_input.editable = dm_can_send and not dm_loading
    dm_input.text_submitted.connect(func(_t): send_dm())
    row.add_child(dm_input)
    var send = _button(row, "ENVIAR", send_dm, true, true)
    send.name = "DmSend"
    send.custom_minimum_size.y = 44
    send.disabled = not dm_input.editable
    if dm_to_end: _dm_scroll_end()
    dm_to_end = true

func _dm_time(iso: String) -> String:
    if iso.length() < 19: return ""
    var unix = Time.get_unix_time_from_datetime_string(iso.substr(0, 19))
    unix += int(Time.get_time_zone_from_system().get("bias", 0)) * 60
    var t = Time.get_datetime_dict_from_unix_time(unix)
    return "%02d:%02d" % [int(t.hour), int(t.minute)]

## Enviadas à direita (dourado), recebidas à esquerda. Texto sempre em Label comum (sem BBCode).
func _dm_line(m: Dictionary):
    var mine = _is_mine(m, dm_id)
    var wrap = MarginContainer.new()
    wrap.add_theme_constant_override("margin_left", 48 if mine else 0)
    wrap.add_theme_constant_override("margin_right", 0 if mine else 48)
    wrap.set_meta("dm_id", int(m.get("id", 0)))
    wrap.set_meta("mine", mine)
    dm_list.add_child(wrap)
    var bubble = PanelContainer.new()
    var st = StyleBoxFlat.new()
    st.bg_color = Color("2c4a2f") if mine else Color("1b2a24")
    st.border_color = Color("b19758") if mine else Color("4b5a4c")
    st.set_border_width_all(1)
    st.set_corner_radius_all(8)
    for side in ["left", "right"]: st.set("content_margin_" + side, 10)
    for side in ["top", "bottom"]: st.set("content_margin_" + side, 5)
    bubble.add_theme_stylebox_override("panel", st)
    wrap.add_child(bubble)
    var col = VBoxContainer.new()
    col.add_theme_constant_override("separation", 1)
    bubble.add_child(col)
    var meta = _label(col, ("Você" if mine else String(dm_peer.get("nickname", ""))) + "  ·  " + _dm_time(String(m.get("created_at", ""))), 12, GOLD if mine else DIM_TEXT)
    meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT
    var body = _label(col, String(m.get("body", "")), 16, Color("f4edda"))
    body.name = "DmBody"
    body.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT

func _dm_scroll_end():
    await get_tree().process_frame
    await get_tree().process_frame
    if is_instance_valid(dm_scroll): dm_scroll.scroll_vertical = int(dm_scroll.get_v_scroll_bar().max_value)

# ---------- Convite para partida Casual ----------
func open_invite(uid: String, peer: Dictionary):
    invite_peer = {"user_id": uid, "nickname": String(peer.get("nickname", "")), "avatar_id": String(peer.get("avatar_id", "warrior"))}
    invite_sending = false
    _show("invite_pick")

func send_invite(mode: String):
    if invite_sending: return
    invite_sending = true
    _show("invite_pick")
    if not _send({"type": "invite_send", "user_id": String(invite_peer.get("user_id", "")), "mode": mode}):
        invite_sending = false
        _show("invite_pick")
        notice_text("Sem conexão. Tente de novo em instantes.")

func _on_invite(msg: Dictionary):
    if screen != "invite_pick": return
    invite_sending = false
    if String(msg.get("type", "")) == "invite_sent":
        # O cartão do convite (com CANCELAR e contagem) aparece no topo; volta ao perfil.
        _show("profile")
        notice_text("Convite enviado para %s." % String(invite_peer.get("nickname", "")), Color("9fe0a8"))
    else:
        _show("invite_pick")
        notice_text(String(msg.get("message", "Não foi possível convidar.")))

func _build_invite_pick():
    var head = HBoxContainer.new()
    head.add_theme_constant_override("separation", 10)
    box.add_child(head)
    _avatar(head, String(invite_peer.get("avatar_id", "warrior")), 44)
    var col = VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(col)
    _label(col, "CONVIDAR " + String(invite_peer.get("nickname", "")), 19, Color("f4edda"))
    _label(col, "Partida Casual · sem PL · o convite vale 60 s", 13, DIM_TEXT)
    _label(box, "Escolha o tempo:", 15, GOLD)
    var grid = GridContainer.new()
    grid.columns = 1 if _narrow() else 2
    grid.add_theme_constant_override("h_separation", 8)
    grid.add_theme_constant_override("v_separation", 8)
    box.add_child(grid)
    for item in INVITE_MODES:
        var mode: String = item[0]
        var b = _button(grid, "%s · %d min" % [item[1], item[2]], func(): send_invite(mode), true)
        b.name = "Invite_" + mode
        b.custom_minimum_size.y = 54
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.disabled = invite_sending
    if invite_sending: _label(box, "Enviando convite…", 14, GOLD, true)

# ---------- Presença ----------
func presence_of(uid: String) -> String:
    var p = presence.get(uid, null)
    return String(p["state"]) if p != null else ""

func _dm_presence_text() -> String:
    var st = presence_of(dm_id)
    if st.is_empty():
        for f in data["friends"]:
            if String(f.get("user_id", "")) == dm_id: st = String(f.get("presence", ""))
    var label = {"online": "Online", "in_match": "Em partida", "offline": "Offline"}.get(st, "")
    return "Conversa privada" + ((" · " + label) if not label.is_empty() else "")

func _new_epoch(epoch: String):
    if epoch.is_empty() or epoch == presence_epoch: return
    presence_epoch = epoch      # servidor reiniciou: revisões recomeçam
    presence.clear()

## Aplica se for mais novo (revisão maior; o snapshot também aceita igual).
func _apply_presence(uid: String, state: String, rev: int, allow_equal := false) -> bool:
    var cur = presence.get(uid, null)
    if cur != null and (rev < int(cur["rev"]) or (rev == int(cur["rev"]) and not allow_equal)): return false
    var changed = cur == null or String(cur["state"]) != state
    presence[uid] = {"state": state, "rev": rev}
    for f in data["friends"]:
        if String(f.get("user_id", "")) == uid: f["presence"] = state
    return changed

func _merge_list_presence(epoch: String):
    _new_epoch(epoch)
    for f in data["friends"]:
        var uid = String(f.get("user_id", ""))
        var cur = presence.get(uid, null)
        if cur != null and int(cur["rev"]) > int(f.get("presence_rev", 0)): f["presence"] = cur["state"]   # lista mais antiga que um update já recebido
        else: presence[uid] = {"state": String(f.get("presence", "offline")), "rev": int(f.get("presence_rev", 0))}

func _on_presence(msg: Dictionary):
    var type = String(msg.get("type", ""))
    if type == "link_lost":
        # Minha conexão caiu: mantém o último estado dos amigos até o novo snapshot.
        reconnecting = true
        if is_open(): notice_text("Reconectando…", GOLD)
        return
    _new_epoch(String(msg.get("epoch", "")))
    var touched := []
    if type == "presence_snapshot":
        var was = reconnecting
        reconnecting = false
        for e in _arr(msg, "friends"):
            if _apply_presence(String(e.get("user_id", "")), String(e.get("state", "offline")), int(e.get("rev", 0)), true): touched.append(String(e.get("user_id", "")))
        if was and is_open() and is_instance_valid(notice) and notice.text == "Reconectando…": notice_text("")
        if was and is_open() and screen == "list": _request_list()
    else:
        var uid = String(msg.get("user_id", ""))
        if _apply_presence(uid, String(msg.get("state", "offline")), int(msg.get("rev", 0))): touched.append(uid)
    if touched.is_empty() or not is_open(): return
    match screen:
        "list": _show("list")      # reorganiza Online / Em partida / Offline na hora
        "profile":
            if touched.has(String(profile.get("user_id", ""))) and String(profile.get("relation", "")) == "friend":
                profile["presence"] = presence_of(String(profile.get("user_id", "")))
                _show("profile")
        "dm":
            if touched.has(dm_id):
                var lbl = box.find_child("DmPresence", true, false)
                if lbl != null: lbl.text = _dm_presence_text()   # sem reconstruir: não perde o texto digitado
