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
const ART_K := 0.42            # R51 · escala da arte de referência dentro do painel (px locais por px da arte)
const PANEL_W := 700.0
## R52b · PC: painel/modal próprio na arte da referência nova (ui_kit/pages/amigos_bg.png, 1448 x 1086),
## centralizado por cima da Home escurecida, com fade. O conteúdo continua o mesmo (em unidades lógicas:
## a arte é desenhada 1/WIDE_LS do tamanho dela e o painel inteiro é ampliado para caber em 92% da tela).
## Celular e janela estreita continuam no layout antigo.
const WIDE_REF := Vector2(1448, 1086)
const WIDE_LS := 1.757
const WIDE_K := 1.0 / WIDE_LS
const WIDE_CONTENT := Rect2(92, 224, 1266, 764)   # área do conteúdo na arte (abaixo do VOLTAR/placa AMIGOS)
const WIDE_BACK := Rect2(76, 100, 270, 95)        # VOLTAR desenhado na arte
var chrome: Control                                # por cima do painel (mesma transformação): VOLTAR da arte
var _wide_now := false
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
var picker_game := ""          # R35.1: convite aberto de dentro de um modo ("chess" | "marcha" | "xeque")
var invite_sending := false
# Presença (Etapa 7): estado publicado pelo servidor; revisão por amigo e época (reinício do servidor).
var presence: Dictionary = {}      # uid -> {"state": String, "rev": int}
var presence_epoch := ""
var reconnecting := false

func setup(service, avatar_callable: Callable = Callable()):
    account = service
    avatar_for = avatar_callable
    var hub = avatar_for.get_object() if avatar_for.is_valid() else null
    if hub != null and hub.has_signal("peer_avatar_ready"): hub.peer_avatar_ready.connect(_on_peer_avatar)
    preload("res://ui_v022/esc_stack.gd").register(self)   # R129 · ESC em tudo (fecha só a janela de cima)
    layer = 66   # R35.1: por cima das telas dos modos (MARCHA REAL / XEQUE), que convidam daqui
    dim = ColorRect.new()
    dim.color = Color(0.029, 0.038, 0.057, 0.82)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    panel = PanelContainer.new()
    panel.name = "FriendsPanel"
    var style = StyleBoxFlat.new()   # (base do aviso/toast)
    style.bg_color = Color("#1c222ff7")
    style.border_color = Color("#b19758")
    style.set_border_width_all(2)
    style.set_corner_radius_all(8)
    for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 14)
    # R51 · moldura de madeira/cobre da referência AMIGOS (cantos, bandeira e bordas originais da arte)
    var frame := Kit.box("painel_amigos", ART_K, Vector2(24, 20))
    frame.content_margin_bottom = 30
    panel.add_theme_stylebox_override("panel", frame)
    add_child(panel)
    scroll = ScrollContainer.new()
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    panel.add_child(scroll)
    box = VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 8)
    scroll.add_child(box)
    chrome = Control.new()
    chrome.name = "FriendsChrome"
    chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(chrome)
    var wb := Button.new()
    wb.name = "FriendsBack"
    wb.flat = true
    wb.focus_mode = Control.FOCUS_NONE
    wb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    wb.position = WIDE_BACK.position / WIDE_LS
    wb.size = WIDE_BACK.size / WIDE_LS
    var lit := StyleBoxFlat.new()
    lit.bg_color = Color(1.0, 0.86, 0.45, 0.10)
    lit.set_corner_radius_all(6)
    for st in ["normal", "focus", "disabled"]: wb.add_theme_stylebox_override(st, StyleBoxEmpty.new())
    for st in ["hover", "pressed"]: wb.add_theme_stylebox_override(st, lit)
    wb.pressed.connect(func(): _back())
    chrome.add_child(wb)
    toast = PanelContainer.new()
    toast.name = "FriendsToast"
    var ts = style.duplicate()
    ts.bg_color = Color("#273145f2")
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
    if _wide_now:   # R52b · fade de entrada (igual às outras telas do PC)
        for n in [panel, chrome, dim]: n.modulate.a = 0.0
        var tw := create_tween().set_parallel(true)
        for n in [panel, chrome, dim]: tw.tween_property(n, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)

func hide_ui():
    screen = ""
    dim.hide(); panel.hide()
    if is_instance_valid(chrome): chrome.hide()
    if is_instance_valid(search_input) and search_input.has_focus(): search_input.release_focus()

func close():
    picker_game = ""
    hide_ui()
    closed.emit()

func _input(event):
    if not is_open(): return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        _back()
        get_viewport().set_input_as_handled()

func esc_open() -> bool:
    return is_open()

func esc_close():
    _back()

func _back():
    match screen:
        "list": close()
        "confirm": _show(String(confirm.get("return", "profile")))
        "dm": close_dm()
        "invite_pick": _show("invite_friends" if not picker_game.is_empty() else invite_return)
        "invite_friends": close()
        "invite_table": _show("invite_friends")
        "ref": _show("list")
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
    if action == "report_dm":   # R104 · denúncia feita de dentro da conversa privada
        if _send({"type": "social_report", "user_id": uid, "from": "dm"}): _show("dm")
        else: notice_text("Sem conexão. Tente de novo em instantes.")
        return
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
    if type == "friend_profile":   # R150 · amigo trocou a foto/avatar/nome
        if msg.get("profile") is Dictionary: _on_friend_profile(msg.profile)
        return
    if type == "ref_info":   # R105 · convite por link
        ref_info = msg
        if screen == "ref": _show("ref")
        return
    if not type.begins_with("social_"): return
    match type:
        "social_list":
            data = {"friends": _arr(msg, "friends"), "received": _arr(msg, "received"), "sent": _arr(msg, "sent"), "blocked": _arr(msg, "blocked")}
            _merge_list_presence(String(msg.get("presence_epoch", "")))
            has_list = true
            if screen == "list": _show("list")
            elif screen == "invite_friends": _show("invite_friends")
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
        "social_report_ok":
            if screen == "confirm": _show("profile")
            notice_text("Denúncia enviada. Obrigado! A equipe FRAIHA vai analisar.", Color("9fe0a8"))
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
                "request_received": show_request_card(who)
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
    _layout_toast.call_deferred()

# ---------- R51 · Pedido de amizade recebido: cartãozinho com ACEITAR / RECUSAR (fora da tela de AMIGOS) ----------
const Kit = preload("res://ui_kit/kit.gd")
const ThemeCatalog = preload("res://cosmetics/theme_catalog.gd")
const LeagueIds = preload("res://league/catalog.gd")
var req_card: PanelContainer
var req_left := 0.0
var req_uid := ""

func show_request_card(who: Dictionary):
    req_uid = String(who.get("user_id", ""))
    if is_instance_valid(req_card): req_card.queue_free()
    req_card = PanelContainer.new()
    req_card.name = "FriendRequestCard"
    var st = StyleBoxFlat.new()
    st.bg_color = Color("#161b25f5")
    st.border_color = Color("#c79a4a")
    st.set_border_width_all(2)
    st.set_corner_radius_all(6)
    st.shadow_color = Color(0, 0, 0, 0.45)
    st.shadow_size = 8
    for side in ["left", "right", "top", "bottom"]: st.set("content_margin_" + side, 12)
    req_card.add_theme_stylebox_override("panel", st)
    req_card.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(req_card)
    var v = VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    req_card.add_child(v)
    var head = HBoxContainer.new()
    head.add_theme_constant_override("separation", 10)
    v.add_child(head)
    var av = _avatar(head, who, 46)
    av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var col = VBoxContainer.new()
    col.add_theme_constant_override("separation", 2)
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(col)
    var t = Label.new(); t.text = "PEDIDO DE AMIZADE"; Kit.label(t, 13, Kit.GOLD); col.add_child(t)
    var n = Label.new(); n.name = "RequestWho"
    n.text = "%s quer ser seu amigo" % String(who.get("nickname", "Alguém"))
    n.clip_text = true
    Kit.label(n, 15, Kit.CREAM, false); col.add_child(n)
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    v.add_child(row)
    var uid := req_uid
    for spec in [["ACEITAR", "btn_verde", "accept"], ["RECUSAR", "btn_azul", "decline"]]:
        var b = Button.new()
        b.name = "Request" + String(spec[2]).capitalize()
        b.text = spec[0]
        b.focus_mode = Control.FOCUS_NONE
        b.custom_minimum_size.y = 40
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        Kit.button(b, spec[1], 0.42, 14)
        var action: String = spec[2]
        b.pressed.connect(func():
            _act(action, uid)
            _hide_req_card())
        row.add_child(b)
    req_left = 20.0
    _layout_req_card()
    _layout_req_card.call_deferred()

func _hide_req_card():
    if is_instance_valid(req_card): req_card.queue_free()
    req_card = null
    req_uid = ""

func _layout_req_card():
    if not is_instance_valid(req_card): return
    var mobile = Mobile.active(get_viewport())
    var area = Mobile.safe_rect(get_viewport()) if mobile else get_viewport().get_visible_rect()
    var s = 1.0 if mobile else 1.4
    req_card.scale = Vector2.ONE * s
    var w = minf(360.0, (area.size.x - 24.0) / s)
    req_card.custom_minimum_size = Vector2(w, 0)
    req_card.reset_size()
    req_card.size.x = w
    req_card.position = Vector2(area.position.x + (area.size.x - w * s) / 2.0, area.position.y + 12.0)

func _process(delta):
    if toast.visible:
        toast_left -= delta
        if toast_left <= 0.0: toast.hide()
    if is_instance_valid(req_card):
        req_left -= delta
        # some sozinho depois de um tempo (o pedido continua em AMIGOS > PEDIDOS RECEBIDOS) ou se a lista já tratou
        if req_left <= 0.0 or (has_list and not data["received"].any(func(p): return String(p.get("user_id", "")) == req_uid)) and req_left < 18.0:
            _hide_req_card()
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
    Kit.label(l, size + 1, color, color == GOLD)
    if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    parent.add_child(l)
    return l

func _button(parent: Node, text: String, action: Callable, primary := false, small := false, kind := "", icon_name := "") -> Button:
    var b = Button.new()
    b.text = text
    b.focus_mode = Control.FOCUS_NONE
    b.custom_minimum_size.y = 40 if small else 46
    # R51 · molduras da referência: verde (ação principal), azul (secundária), vermelho (VOLTAR)
    var k := kind if not kind.is_empty() else ("btn_verde" if primary else "btn_azul")
    if _wide() and k in ["btn_verde", "btn_azul"]:
        # R52b · botões da referência nova (verde = principal, azul = mensagem/secundária)
        var ic: String = {"ico_balao": "fr_ico_balao", "ico_espadas": "fr_ico_convidar"}.get(icon_name, icon_name)
        Kit.button(b, "fr_" + k, WIDE_K, 15 if small else 17, ic)
        b.custom_minimum_size.y = 46 if small else 50
    else:
        Kit.button(b, k, ART_K, 15 if small else 17, icon_name)
    b.pressed.connect(action)
    parent.add_child(b)
    return b

## R150 · `who` = perfil público (Dictionary: foto avatar_url + avatar_id) ou só o id do avatar (String).
func _avatar(parent: Node, who, px: int) -> TextureRect:
    var t = TextureRect.new()
    t.custom_minimum_size = Vector2(px, px)
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    t.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _set_avatar(t, who)
    parent.add_child(t)
    return t

func _set_avatar(t: TextureRect, who):
    var info: Dictionary = who if who is Dictionary else {"avatar_id": String(who)}
    var id := String(info.get("avatar_id", "warrior"))
    var known: bool = id in ["warrior", "archer", "mage", "paladin"] or (id in AvatarCatalog.ids() and AvatarCatalog.has_art(id))
    if not known: info = info.duplicate(); info["avatar_id"] = "warrior"
    var hub = avatar_for.get_object() if avatar_for.is_valid() else null
    if hub != null and hub.has_method("avatar_texture_for"):
        t.texture = hub.avatar_texture_for(info)
        var url := String(info.get("avatar_url", "")) if info.get("avatar_url") is String else ""
        if not url.is_empty() and t.texture is ImageTexture: t.texture = _round_photo(t.texture, url)
        var uid := String(info.get("user_id", ""))
        if not uid.is_empty():
            t.set_meta("peer_uid", uid)
            t.set_meta("peer_info", info)
    elif avatar_for.is_valid(): t.texture = avatar_for.call(String(info.avatar_id))

## R150 · foto (quadrada) recortada em círculo, para caber no anel dourado como os avatares do catálogo.
var _round_cache := {}
func _round_photo(tex: Texture2D, url: String) -> Texture2D:
    var k := url + "|" + str(tex.get_instance_id())
    if _round_cache.has(k): return _round_cache[k]
    var img: Image = tex.get_image()
    if img == null: return tex
    img = img.duplicate()
    if img.get_format() != Image.FORMAT_RGBA8: img.convert(Image.FORMAT_RGBA8)
    var w := img.get_width()
    var c := (w - 1) / 2.0
    var r := w * 0.47
    for y in w:
        for x in w:
            var d := Vector2(x - c, y - c).length()
            if d > r:
                var px := img.get_pixel(x, y)
                px.a *= clampf(1.0 - (d - r), 0.0, 1.0)
                img.set_pixel(x, y, px)
    if _round_cache.size() > 64: _round_cache.clear()
    _round_cache[k] = ImageTexture.create_from_image(img)
    return _round_cache[k]

## R150 · a foto de alguém chegou (download terminou): troca nos retratos dessa pessoa que estão na tela.
func _on_peer_avatar(uid: String):
    for n in find_children("*", "TextureRect", true, false):
        if n.has_meta("peer_uid") and String(n.get_meta("peer_uid")) == uid: _set_avatar(n, n.get_meta("peer_info"))

## R150 · um amigo trocou a foto / avatar / selo / nome (aviso do servidor): atualiza tudo que guardamos dele.
func _on_friend_profile(p: Dictionary):
    var uid := String(p.get("user_id", ""))
    if uid.is_empty(): return
    var upd := func(d: Dictionary):
        if String(d.get("user_id", "")) != uid: return
        for k in ["nickname", "avatar_id", "avatar_url", "badge", "title", "frame", "founder", "club"]:
            if p.has(k): d[k] = p[k]
    for key in data:
        for d in data[key]:
            if d is Dictionary: upd.call(d)
    for d in results:
        if d is Dictionary: upd.call(d)
    for d in [profile, dm_peer, invite_peer]: upd.call(d)
    for n in find_children("*", "TextureRect", true, false):
        if n.has_meta("peer_uid") and String(n.get_meta("peer_uid")) == uid:
            var info: Dictionary = (n.get_meta("peer_info") as Dictionary).duplicate()
            for k in ["avatar_id", "avatar_url"]: info[k] = p.get(k, info.get(k))
            _set_avatar(n, info)
    if is_open() and screen in ["list", "profile", "search", "invite_friends"]: _show(screen)

## R41 · Moldura Club / Fundador sobre o avatar de outro jogador (dados do servidor).
func _frame(av: Control, p: Dictionary) -> void:
    var fr := Cosmetics.public_frame(p)
    if av == null or fr == "liga": return   # R116 · Club, Fundador e as molduras da Loja
    var f = preload("res://monetization/club_frame.gd").new()
    f.style = fr
    f.compact = av.custom_minimum_size.x < 60.0
    av.add_child(f)

## R31 · DESTAQUE SOCIAL: selo (Fundador / Club) que o servidor já filtrou pelos direitos ativos.
const AvatarCatalog = preload("res://profile/avatar_catalog.gd")
const Cosmetics = preload("res://profile/premium_cosmetics.gd")
func _seal(parent: Node, p: Dictionary, px: int) -> TextureRect:
    var id := Cosmetics.public_badge(p)
    if id.is_empty(): return null
    var t = TextureRect.new()
    t.name = "SocialBadge"
    t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # R138 · ícone nítido
    t.texture = Cosmetics.badge_texture(id, px <= 48)
    t.custom_minimum_size = Vector2(px, px)
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    t.tooltip_text = String(Cosmetics.BADGE_NAMES.get(id, ""))
    t.mouse_filter = Control.MOUSE_FILTER_PASS
    parent.add_child(t)
    return t

static func _peer(uid: String, peer: Dictionary) -> Dictionary:
    return {"user_id": uid, "nickname": String(peer.get("nickname", "")), "avatar_id": String(peer.get("avatar_id", "warrior")), "avatar_url": peer.get("avatar_url"), "badge": String(peer.get("badge", "")), "title": String(peer.get("title", ""))}

const SECTION_ICON := {"ONLINE": "ico_sec_online", "EM PARTIDA": "ico_sec_partida", "OFFLINE": "ico_sec_offline"}
const SECTION_ICON_WIDE := {"ONLINE": "fr_ico_online", "EM PARTIDA": "fr_ico_partida", "OFFLINE": "fr_ico_offline"}
func _section(title: String, count: int):
    var h = HBoxContainer.new()
    h.name = "SectionRow_" + title.replace(" ", "_")
    h.add_theme_constant_override("separation", 8)
    if _wide():
        # R52b · faixa da seção na moldura fina da referência
        var sp := PanelContainer.new()
        sp.add_theme_stylebox_override("panel", Kit.box("fr_caixa_secao", WIDE_K, Vector2(14, 6)))
        sp.custom_minimum_size.y = 36
        box.add_child(sp)
        sp.add_child(h)
        h.add_child(Kit.icon(SECTION_ICON_WIDE.get(title, "fr_ico_offline"), 22))
    else:
        box.add_child(h)
        if SECTION_ICON.has(title): h.add_child(Kit.icon(SECTION_ICON[title], 18))
    var l = Label.new()
    l.text = "%s (%d)" % [title, count]
    l.name = "Section_" + title.replace(" ", "_")
    Kit.label(l, 18, Color("e8b25a"))
    h.add_child(l)
    var line = TextureRect.new()
    line.texture = Kit.tex("sec_linha")
    line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    line.stretch_mode = TextureRect.STRETCH_SCALE
    line.custom_minimum_size = Vector2(40, 6)
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    h.add_child(line)

## "Ninguém por aqui." na caixa com cantoneiras da referência.
func _empty(text: String):
    var c = PanelContainer.new()
    c.add_theme_stylebox_override("panel", Kit.box("fr_caixa_vazia", WIDE_K, Vector2(22, 8)) if _wide() else Kit.box("caixa_vazia", ART_K, Vector2(16, 10)))
    c.custom_minimum_size.y = 48 if _wide() else 42
    box.add_child(c)
    var l = Label.new()
    l.text = text
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    Kit.label(l, 16, DIM_TEXT, false)
    c.add_child(l)

## Linha de jogador: avatar + nickname (toque abre o perfil) + status + botões de ação.
func _row(p: Dictionary, status_text: String, status_color: Color, actions: Array) -> HBoxContainer:
    var holder = PanelContainer.new()
    var wide := _wide()
    holder.add_theme_stylebox_override("panel", Kit.box("fr_caixa_linha", WIDE_K, Vector2(14, 6)) if wide else Kit.box("caixa_linha", ART_K, Vector2(10, 7)))
    if wide: holder.custom_minimum_size.y = 70
    box.add_child(holder)
    var narrow := _narrow()
    var outer = VBoxContainer.new()
    outer.add_theme_constant_override("separation", 6)
    holder.add_child(outer)
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.set_meta("user_id", String(p.get("user_id", "")))
    outer.add_child(row)
    var btn_row: HBoxContainer = row
    if narrow and actions.size() > 0:
        btn_row = HBoxContainer.new()
        btn_row.add_theme_constant_override("separation", 6)
        outer.add_child(btn_row)
    var av := _avatar(row, p, 50 if wide else 46)
    if wide:
        # anel dourado da referência em volta do retrato
        var ring := TextureRect.new()
        ring.texture = Kit.tex("fr_anel")
        ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        ring.stretch_mode = TextureRect.STRETCH_SCALE
        ring.size = Vector2(66, 66)
        ring.position = Vector2(-8, -8)
        ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
        ring.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        av.add_child(ring)
        av.custom_minimum_size.x = 60
    _frame(av, p)
    if status_color == PRESENCE["online"][1]:
        # bolinha verde de online no canto do retrato (como na referência)
        var dot = Panel.new()
        var ds = StyleBoxFlat.new()
        ds.bg_color = Color("36c25a"); ds.set_corner_radius_all(6)
        ds.border_color = Color("121825"); ds.set_border_width_all(1)
        dot.add_theme_stylebox_override("panel", ds)
        dot.size = Vector2(12, 12)
        dot.position = Vector2(34, 34)
        dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
        av.add_child(dot)
    _seal(row, p, 28)
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
    name_btn.add_theme_font_override("font", Kit.SERIF_BOLD)
    name_btn.add_theme_font_size_override("font_size", 22 if wide else 19)
    name_btn.add_theme_color_override("font_color", Color("f4edda"))
    name_btn.tooltip_text = "Ver perfil"
    var plain = StyleBoxEmpty.new()
    for state in ["normal", "hover", "pressed", "focus"]: name_btn.add_theme_stylebox_override(state, plain)
    name_btn.add_theme_color_override("font_hover_color", GOLD)
    var uid = String(p.get("user_id", ""))
    name_btn.pressed.connect(func(): open_profile(uid, screen == "search"))
    col.add_child(name_btn)
    if not status_text.is_empty():
        var st_parent: Node = col
        if wide and status_color in [PRESENCE["online"][1], PRESENCE["offline"][1], PRESENCE["in_match"][1]]:
            var sr := HBoxContainer.new()
            sr.add_theme_constant_override("separation", 6)
            col.add_child(sr)
            var dot_name: String = "fr_ico_online" if status_color == PRESENCE["online"][1] else ("fr_ico_partida" if status_color == PRESENCE["in_match"][1] else "fr_ico_dot_off")
            sr.add_child(Kit.icon(dot_name, 14))
            st_parent = sr
        var st = _label(st_parent, status_text, 15, status_color)
        st.autowrap_mode = TextServer.AUTOWRAP_OFF
        st.clip_text = true
        if st_parent != col: st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        st.add_theme_font_override("font", Kit.SERIF)
    for a in actions:
        var b := _button(btn_row, a[0], a[1], a.size() > 2 and a[2], true, String(a[3]) if a.size() > 3 else "", String(a[4]) if a.size() > 4 else "")
        b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        if narrow:
            b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            b.add_theme_font_size_override("font_size", 15)
        else:
            b.custom_minimum_size.x = 150
            b.add_theme_font_size_override("font_size", 17)
    return row

func _show(which: String):
    screen = which
    _clear()
    var narrow = _narrow()
    _wide_now = _wide()
    if _wide_now:
        # R52b · arte inteira da referência nova; VOLTAR e placa AMIGOS são da arte (VOLTAR clicável no chrome)
        var wf := StyleBoxTexture.new()
        wf.texture = load("res://ui_kit/pages/amigos_bg.png")
        wf.content_margin_left = WIDE_CONTENT.position.x / WIDE_LS
        wf.content_margin_top = WIDE_CONTENT.position.y / WIDE_LS
        wf.content_margin_right = (WIDE_REF.x - WIDE_CONTENT.end.x) / WIDE_LS
        wf.content_margin_bottom = (WIDE_REF.y - WIDE_CONTENT.end.y) / WIDE_LS
        panel.add_theme_stylebox_override("panel", wf)
        _build_body(which, narrow)
        return
    # moldura: no celular em pé, um pouco menor (a bandeira não encosta na placa do título)
    # R158 · celular em pé: moldura "clean" (sem a bandeira que cobria a placa AMIGOS e o canto)
    var frame := Kit.box("painel_amigos" if not narrow else "painel_amigos_clean", ART_K if not narrow else 0.3, Vector2(24 if not narrow else 14, 20 if not narrow else 14))
    frame.content_margin_bottom = 30 if not narrow else 22
    panel.add_theme_stylebox_override("panel", frame)
    var head = HBoxContainer.new()
    head.add_theme_constant_override("separation", 8)
    box.add_child(head)
    var back = _button(head, "VOLTAR", _back, false, true, "btn_vermelho", "ico_voltar")
    back.name = "FriendsBack"
    back.custom_minimum_size = Vector2(122, 44) if not narrow else Vector2(96, 40)
    back.add_theme_font_size_override("font_size", 18 if not narrow else 15)
    back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    # placa AMIGOS: cantos da arte (flores-de-lis e volutas) fixos, miolo esticado até ~44% da largura (referência)
    var pc := CenterContainer.new()
    pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(pc)
    var plate := Kit.plate("placa_titulo", 290 if not narrow else 168, 66 if not narrow else 50, 170)
    plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    pc.add_child(plate)
    var title = Label.new()
    title.text = "AMIGOS"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    title.offset_top = -4
    Kit.label(title, 26 if not narrow else 20, Color("f5d27a"))
    title.add_theme_font_override("font", Kit.FONT_BOLD)
    plate.add_child(title)
    var spacer = Control.new()
    spacer.custom_minimum_size.x = 122 if not narrow else 0
    head.add_child(spacer)
    _build_body(which, narrow)

func _build_body(which: String, narrow: bool):
    notice = _label(box, "", 14, ERROR, true)
    notice.name = "FriendsNotice"
    notice.hide()
    var wide := _wide_now
    match which:
        "list", "search":
            var srow = HBoxContainer.new()
            srow.add_theme_constant_override("separation", 6)
            box.add_child(srow)
            search_input = LineEdit.new()
            preload("res://ui_v022/web_text_field.gd").attach(search_input)
            search_input.name = "FriendSearch"
            search_input.placeholder_text = "Buscar jogador" if narrow else "Buscar jogador pelo nickname"   # R158 · celular: sem cortar
            search_input.max_length = 16
            search_input.text = last_query if which == "search" else ""
            search_input.custom_minimum_size.y = 50 if wide else 46
            search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            search_input.add_theme_font_override("font", Kit.SERIF)
            search_input.add_theme_font_size_override("font_size", 18)
            search_input.add_theme_color_override("font_placeholder_color", Color("9a96c4"))
            search_input.add_theme_color_override("font_color", Color("f1e6c8"))
            var fst := Kit.box("fr_campo" if wide else "campo", WIDE_K if wide else ART_K, Vector2(48 if wide else 44, 6))
            for st_name in ["normal", "focus", "read_only"]: search_input.add_theme_stylebox_override(st_name, fst)
            if wide:
                search_input.add_theme_font_size_override("font_size", 19)
                var lupa2 := Kit.icon("fr_ico_lupa", 26)
                lupa2.position = Vector2(15, 12)
                search_input.add_child(lupa2)
            elif not narrow:
                var lupa := Kit.icon("ico_lupa", 20)
                lupa.position = Vector2(14, 13)
                search_input.add_child(lupa)
            else:
                search_input.add_theme_stylebox_override("normal", Kit.box("campo", ART_K, Vector2(14, 6)))
                search_input.add_theme_stylebox_override("focus", Kit.box("campo", ART_K, Vector2(14, 6)))
            search_input.text_submitted.connect(func(t): search(t))
            srow.add_child(search_input)
            var input_ref = search_input
            var sb := _button(srow, "BUSCAR", func(): search(input_ref.text), true, true)
            sb.custom_minimum_size = Vector2(150 if wide else (112 if not narrow else 92), 50 if wide else 46)
            if wide: sb.add_theme_font_size_override("font_size", 19)
            if which == "search": _build_search()
            else: _build_list(narrow)
        "profile": _build_profile(narrow)
        "confirm": _build_confirm()
        "dm": _build_dm()
        "invite_pick": _build_invite_pick()
        "ref": _build_ref(narrow)
        "invite_friends": _build_invite_friends()
        "invite_table": _build_invite_table()
    if reconnecting and is_instance_valid(notice) and not notice.visible: notice_text("Reconectando…", GOLD)
    dim.show(); panel.show()
    chrome.visible = wide
    _layout()
    _layout.call_deferred()

func _build_list(_narrow_layout: bool):
    if not has_list:
        _label(box, "Carregando amigos…" if account.has_profile() else "Conectando sua conta ao servidor...", 15, GOLD, true)
        return
    # R105 · convite por link (WhatsApp) com recompensa
    var inv := _button(box, "CONVIDAR AMIGOS · GANHE 7 DIAS DE CLUB" if not _narrow_layout else "CONVIDAR · +7 DIAS DE CLUB", open_ref, true, false, "btn_verde", "ico_espadas")
    inv.clip_text = true
    inv.name = "OpenReferral"
    inv.custom_minimum_size.y = 50
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
            _empty("Ninguém por aqui." if friends.size() or key != "online" else "Você ainda não tem amigos. Busque pelo nickname acima.")
        for f in groups[key]:
            var fid = String(f.get("user_id", ""))
            var unread = int(f.get("unread", 0))
            var finfo: Dictionary = f
            var acts := [[("MENSAGEM (%d)" % unread) if unread > 0 else "MENSAGEM", func(): open_dm(fid, finfo, "list"), false, "btn_azul", "ico_balao"]]
            # R51 · CONVIDAR direto na lista (como na referência), para amigo online
            if key == "online":
                var peer := _peer(fid, finfo)
                acts.append(["CONVIDAR", func(): open_invite(fid, peer), true, "btn_verde", "ico_espadas"])
            _row(f, PRESENCE[key][0].capitalize() if key != "in_match" else "Em partida", PRESENCE[key][1], acts)
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

# ---------- R105 · CONVIDAR AMIGOS (link + recompensa por indicação) ----------
const InviteLink := preload("res://social/invite_link.gd")
var ref_info: Dictionary = {}

func open_ref():
    if not is_open(): open()
    ref_info = {}
    _show("ref")
    if not _send({"type": "ref_get"}): notice_text("Sem conexão. Tente de novo em instantes.")

func _build_ref(_narrow_layout: bool):
    _label(box, "CONVIDE SEUS AMIGOS", 22, GOLD, true).name = "RefTitle"
    var rules: Dictionary = ref_info.get("rules", {}) if ref_info.get("rules") is Dictionary else {}
    var games := int(rules.get("games", 5)); var fd := int(rules.get("friend_days", 7)); var pd := int(rules.get("purchase_days", 30)); var cap := int(rules.get("cap", 10))
    var how := _label(box, "Mande o seu link. Quando o amigo criar a conta por ele e terminar %d partidas online, VOCÊS DOIS ganham %d dias de Club FRAIHA. Se ele apoiar o jogo com uma compra, você ganha mais %d dias." % [games, fd, pd], 16, TEXT, true)
    how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    how.name = "RefRules"
    if ref_info.is_empty():
        _label(box, "Preparando o seu link…", 15, GOLD, true)
        return
    var code := String(ref_info.get("code", ""))
    if not bool(ref_info.get("available", false)) or code.is_empty():
        _label(box, String(ref_info.get("message", "O convite com recompensa ainda não está ligado neste servidor. Você pode chamar os amigos pelo endereço do jogo.")), 15, DIM_TEXT, true)
        code = ""
    var link_text := InviteLink.link(code) if not code.is_empty() else InviteLink.SITE
    var ll := _label(box, link_text, 15, Color("9fe0a8"), true)
    ll.name = "RefLink"
    ll.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
    var row := HFlowContainer.new()
    row.add_theme_constant_override("h_separation", 8)
    row.add_theme_constant_override("v_separation", 8)
    row.alignment = FlowContainer.ALIGNMENT_CENTER
    box.add_child(row)
    var wa := _button(row, "ENVIAR NO WHATSAPP", func():
        if code.is_empty(): OS.shell_open("https://wa.me/?text=" + ("Bora jogar xadrez comigo no FRAIHA? " + InviteLink.SITE).uri_encode())
        else: InviteLink.open_whatsapp(code), true, false, "btn_verde", "ico_balao")
    wa.name = "RefWhatsApp"
    var cp := _button(row, "COPIAR LINK", func():
        DisplayServer.clipboard_set(link_text)
        notice_text("Link copiado! Cole na conversa com seu amigo.", Color("9fe0a8")), false, false, "btn_azul")
    cp.name = "RefCopy"
    if OS.has_feature("web") and not code.is_empty():
        var sh := _button(row, "COMPARTILHAR", func():
            if not InviteLink.native_share(code):
                InviteLink.copy(code)
                notice_text("Link copiado! Cole onde quiser.", Color("9fe0a8")), false, false, "btn_azul")
        sh.name = "RefShare"
    if not code.is_empty():
        var st := _label(box, "Amigos que entraram pelo seu link: %d  ·  já completaram %d partidas: %d  ·  prêmios este mês: %d de %d" % [int(ref_info.get("invited", 0)), games, int(ref_info.get("qualified", 0)), int(ref_info.get("rewarded_month", 0)), cap], 14, DIM_TEXT, true)
        st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        st.name = "RefStats"
    var fine := _label(box, "Vale para contas novas criadas pelo link. Partidas online contra outra pessoa (Casual, Ranqueada, XEQUE e Marcha com amigos); desistências logo no começo não contam. Até %d amigos premiados por mês." % cap, 13, DIM_TEXT, true)
    fine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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
    # R161 · perfil novo: cabeçalho centrado, ELO do xadrez em destaque, os 4 ritmos em quadradinhos e
    # Casual / XEQUE / MARCHA em linhas simples (vitórias, derrotas, empates e % de vitórias)
    var head = VBoxContainer.new()
    head.add_theme_constant_override("separation", 4)
    box.add_child(head)
    var av_row = CenterContainer.new()
    head.add_child(av_row)
    var av = _avatar(av_row, profile, 92)
    _frame(av, profile)
    var nick_row = HBoxContainer.new()
    nick_row.alignment = BoxContainer.ALIGNMENT_CENTER
    nick_row.add_theme_constant_override("separation", 8)
    head.add_child(nick_row)
    var nick = _label(nick_row, String(profile.get("nickname", "")), 24, Color("f4edda"), true)
    nick.name = "ProfileNickname"
    # R35.1 · nickname numa linha só (antes quebrava letra a letra: o rótulo ficava com largura 0)
    nick.autowrap_mode = TextServer.AUTOWRAP_OFF
    nick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    nick.clip_text = true
    nick.custom_minimum_size.x = 120
    _seal(nick_row, profile, 40)
    var ttl := Cosmetics.title_text(String(profile.get("title", "")))
    if not ttl.is_empty(): _label(head, ttl.to_upper(), 14, GOLD, true).name = "ProfileTitle"
    var pres = String(profile.get("presence", ""))
    if not pres.is_empty():   # o servidor só envia presença de amigos
        var pinfo = PRESENCE.get(pres, PRESENCE["offline"])
        _label(head, "●  " + pinfo[0], 14, pinfo[1], true).name = "ProfilePresence"
    var ranked: Dictionary = profile.get("ranked", {}) if profile.get("ranked") is Dictionary else {}
    # ---- ELO DO XADREZ: o melhor ritmo jogado (liga mais alta, depois mais PL)
    var best := -1
    var best_key := -1
    for i in MODES.size():
        var s0: Dictionary = ranked.get(MODES[i][0], {}) if ranked.get(MODES[i][0]) is Dictionary else {}
        if int(s0.get("matches", 0)) <= 0: continue
        var key := int(s0.get("league", 0)) * 1000 + int(s0.get("pl", 0))
        if key > best_key: best_key = key; best = i
    var hl := clampi(int(profile.get("highest_league", 0)), 0, 10)
    var elo := _stat_box(box)
    elo.name = "ProfileElo"
    var er = HBoxContainer.new()
    er.add_theme_constant_override("separation", 12)
    elo.add_child(er)
    var lg := 0
    var line2 := "Ainda sem partidas ranqueadas"
    if best >= 0:
        var bs: Dictionary = ranked[MODES[best][0]]
        lg = clampi(int(bs.get("league", 0)), 0, 10)
        line2 = "%s · %d PL" % [LEAGUES[lg].to_upper(), int(bs.get("pl", 0))]
    _badge(er, lg, 64)
    var ev = VBoxContainer.new()
    ev.alignment = BoxContainer.ALIGNMENT_CENTER
    ev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    ev.add_theme_constant_override("separation", 0)
    er.add_child(ev)
    _label(ev, "ELO NO XADREZ" + (("  ·  " + MODES[best][1]) if best >= 0 else ""), 13, GOLD).name = "ProfileEloMode"
    var el = _label(ev, line2, 21 if best >= 0 else 15, Color("f4edda") if best >= 0 else DIM_TEXT)
    el.name = "ProfileEloLeague"
    _label(ev, "Maior liga já alcançada: " + LEAGUES[hl], 13, DIM_TEXT).name = "ProfileHighest"
    # ---- XADREZ RANKEADO: um quadradinho por ritmo
    _pf_section(box, "XADREZ RANQUEADO")
    var grid = GridContainer.new()
    grid.name = "ProfileRankedGrid"
    grid.columns = 2 if narrow else 4
    grid.add_theme_constant_override("h_separation", 8)
    grid.add_theme_constant_override("v_separation", 8)
    box.add_child(grid)
    for m in MODES:
        var s: Dictionary = ranked.get(m[0], {}) if ranked.get(m[0]) is Dictionary else {}
        var t := _stat_box(grid)
        t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var tv = VBoxContainer.new()
        tv.add_theme_constant_override("separation", 2)
        t.add_child(tv)
        _label(tv, m[1], 13, GOLD, true)
        var games := int(s.get("matches", 0))
        var tr = CenterContainer.new()
        tv.add_child(tr)
        var li := clampi(int(s.get("league", 0)), 0, 10)
        var bd := _badge(tr, li, 40)
        if games <= 0: bd.modulate = Color(1, 1, 1, 0.45)
        var lt := _label(tv, "%s · %d PL" % [LEAGUES[li], int(s.get("pl", 0))], 15, Color("f4edda") if games > 0 else DIM_TEXT, true)
        lt.autowrap_mode = TextServer.AUTOWRAP_OFF
        if games > 0:
            _label(tv, _wld(int(s.get("wins", 0)), int(s.get("losses", 0)), int(s.get("draws", 0))), 13, TEXT, true)
            _label(tv, "%d partidas · %d%% vitórias" % [games, _pct(int(s.get("wins", 0)), games)], 12, DIM_TEXT, true)
        else:
            _label(tv, "Sem partidas", 13, DIM_TEXT, true)
    # ---- OUTROS MODOS: Casual / XEQUE / MARCHA
    var modes: Dictionary = profile.get("modes", {}) if profile.get("modes") is Dictionary else {}
    _pf_section(box, "OUTROS MODOS")
    var om := _stat_box(box)
    om.name = "ProfileModes"
    var ol = VBoxContainer.new()
    ol.add_theme_constant_override("separation", 6)
    om.add_child(ol)
    for o in [["casual", "XADREZ CASUAL"], ["xeque", "XEQUE"], ["marcha", "MARCHA"]]:
        var ms: Dictionary = modes.get(o[0], {}) if modes.get(o[0]) is Dictionary else {}
        var w := int(ms.get("wins", 0))
        var lo := int(ms.get("losses", 0))
        var d := int(ms.get("draws", 0))
        var n := w + lo + d
        var r = HBoxContainer.new()
        r.add_theme_constant_override("separation", 8)
        ol.add_child(r)
        var nm = _label(r, o[1], 14, GOLD)
        nm.autowrap_mode = TextServer.AUTOWRAP_OFF
        nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var v = _label(r, (_wld(w, lo, d) + "   " + ("%d%%" % _pct(w, n))) if n > 0 else ("—" if modes.is_empty() else "Sem partidas"), 14, TEXT if n > 0 else DIM_TEXT)
        v.autowrap_mode = TextServer.AUTOWRAP_OFF
        v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
    # R104 · denunciar (perfil, nome, foto ou mensagens privadas)
    var rep = _button(actions, "DENUNCIAR", func(): _ask("report", uid, "DENUNCIAR JOGADOR?", "A equipe FRAIHA vai analisar o perfil de %s (nome e foto) e as mensagens privadas que ele te enviou. Use para ofensa, assédio, golpe ou nome impróprio. Denúncia falsa pode gerar punição." % nickname))
    rep.name = "ProfileReport"

## R161 · caixinha do perfil (mesma moldura das linhas da lista)
func _stat_box(parent: Node) -> PanelContainer:
    var holder = PanelContainer.new()
    holder.add_theme_stylebox_override("panel", Kit.box("fr_caixa_linha", WIDE_K, Vector2(16, 10)) if _wide() else Kit.box("caixa_linha", ART_K, Vector2(12, 9)))
    parent.add_child(holder)
    return holder

func _pf_section(parent: Node, text: String) -> void:
    var l = _label(parent, text, 14, GOLD)
    l.custom_minimum_size.y = 26
    l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

func _badge(parent: Node, league: int, px: int) -> TextureRect:
    var t = TextureRect.new()
    t.texture = ThemeCatalog.badge_texture(LeagueIds.IDS[clampi(league, 0, 10)])
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    t.custom_minimum_size = Vector2(px, px)
    t.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(t)
    return t

static func _wld(w: int, l: int, d: int) -> String:
    return "%dV · %dD · %dE" % [w, l, d]

static func _pct(w: int, n: int) -> int:
    return 0 if n <= 0 else int(round(100.0 * w / n))

func _ask(action: String, uid: String, title: String, text: String):
    confirm = {"action": action, "user_id": uid, "title": title, "text": text, "return": "profile"}
    _show("confirm")

func _build_confirm():
    _label(box, String(confirm.get("title", "")), 20, GOLD, true)
    _label(box, String(confirm.get("text", "")), 16, TEXT, true)
    var action = String(confirm.get("action", ""))
    var uid = String(confirm.get("user_id", ""))
    var back := String(confirm.get("return", "profile"))
    _button(box, "CONFIRMAR", func(): _act(action, uid), true)
    _button(box, "CANCELAR", func(): _show(back))

# ---------- Layout ----------
## PC (não celular, janela larga): painel/modal da referência nova.
func _wide() -> bool:
    return not _narrow() and not Mobile.active(get_viewport())

func _narrow() -> bool:
    return get_viewport().get_visible_rect().size.x < 700.0 or (Mobile.active(get_viewport()) and Mobile.is_portrait(get_viewport()))

func _layout():
    if not panel.visible: return
    if _wide_now:
        _layout_wide()
        _layout_toast()
        return
    var mobile = Mobile.active(get_viewport())
    var area = Mobile.safe_rect(get_viewport()) if mobile else get_viewport().get_visible_rect()
    dim.size = get_viewport().get_visible_rect().size
    var ui_scale = 1.0 if mobile else 1.4
    panel.scale = Vector2.ONE * ui_scale
    var width = minf(PANEL_W, (area.size.x - 16.0) / ui_scale)
    box.custom_minimum_size.x = width - 48.0
    if screen == "dm" and is_instance_valid(dm_scroll):
        # A conversa ocupa o espaço que sobra na tela (sem passar do painel).
        # R158 · desconta a moldura de verdade (antes 28 px fixos, mas o painel usa ~50): a caixa de mensagem
        # passava da borda de baixo e cortava no celular
        var sb = panel.get_theme_stylebox("panel")
        var pad: float = maxf(50.0, (sb.get_minimum_size().y if sb != null else 0.0) + 6.0)
        var avail = (area.size.y - 16.0) / ui_scale - pad
        _set_dm_height(avail - _dm_rest() - 6.0)
    var wanted = box.get_combined_minimum_size().y + 28.0
    var pad_x := 48.0
    var sb0 = panel.get_theme_stylebox("panel")
    var pad_y: float = maxf(50.0, (sb0.get_minimum_size().y if sb0 != null else 0.0) + 6.0)
    wanted = box.get_combined_minimum_size().y + pad_y
    var height = minf(maxf(wanted, 0.0), (area.size.y - 16.0) / ui_scale)
    scroll.custom_minimum_size = Vector2(width - pad_x, height - pad_y)
    panel.custom_minimum_size = Vector2.ZERO
    panel.reset_size()
    panel.size = Vector2(width, height)
    panel.position = area.position + (area.size - panel.size * ui_scale) / 2.0
    _layout_toast()

## R52d · Altura da conversa (DM) = espaço que sobra no painel. Antes era calculada a partir do tamanho mínimo
## da coluna inteira, que INCLUI a própria conversa e só é recalculado no quadro seguinte (valor atrasado):
## como _layout roda todo quadro, a altura nunca parava (alternava entre dois valores, ±1 px arredondado) e a
## caixa de mensagem + ENVIAR tremiam. Agora a soma usa só os outros elementos e o valor é inteiro e estável.
func _dm_rest() -> float:
    var total := 0.0
    var n := 0
    for c in box.get_children():
        if c == dm_scroll or not (c is Control) or not c.visible: continue
        total += c.get_combined_minimum_size().y
        n += 1
    return total + float(box.get_theme_constant("separation")) * n

func _set_dm_height(h: float):
    var want := floorf(clampf(h, 120.0, 560.0))
    if dm_scroll.custom_minimum_size.y != want: dm_scroll.custom_minimum_size.y = want

## R52b · tamanho fixo (proporção da arte), centralizado; a lista rola dentro do painel.
func _layout_wide():
    var vs := get_viewport().get_visible_rect().size
    dim.size = vs
    var k := minf(vs.x * 0.92 / WIDE_REF.x, vs.y * 0.92 / WIDE_REF.y)
    var logical := WIDE_REF / WIDE_LS
    var s := k * WIDE_LS
    var cw := WIDE_CONTENT.size.x / WIDE_LS
    var ch := WIDE_CONTENT.size.y / WIDE_LS
    box.custom_minimum_size.x = cw - 14.0
    if screen == "dm" and is_instance_valid(dm_scroll):
        _set_dm_height(ch - _dm_rest() - 6.0)
    scroll.custom_minimum_size = Vector2(cw, ch)
    panel.custom_minimum_size = Vector2.ZERO
    panel.reset_size()
    panel.size = logical
    panel.scale = Vector2.ONE * s
    panel.position = ((vs - logical * s) / 2.0).round()
    chrome.position = panel.position
    chrome.scale = panel.scale
    chrome.size = logical
    _style_scrollbar()

## barra de rolagem fina dourada (funcional: arrastar, roda do mouse, clique no trilho)
func _style_scrollbar():
    var bar := scroll.get_v_scroll_bar()
    if bar.has_meta("fraiha"): return
    bar.set_meta("fraiha", true)
    var tr := StyleBoxFlat.new()
    tr.bg_color = Color(0.028, 0.047, 0.085, 0.85)
    tr.border_color = Color(0.72, 0.56, 0.24, 0.8)
    tr.set_border_width_all(1)
    tr.set_corner_radius_all(4)
    tr.content_margin_left = 5; tr.content_margin_right = 5
    var gr := StyleBoxFlat.new()
    gr.bg_color = Color("d9b05a")
    gr.border_color = Color("6e4f1c")
    gr.set_border_width_all(1)
    gr.set_corner_radius_all(4)
    var gh: StyleBoxFlat = gr.duplicate()
    gh.bg_color = Color("f3d27e")
    bar.add_theme_stylebox_override("scroll", tr)
    bar.add_theme_stylebox_override("scroll_focus", tr)
    bar.add_theme_stylebox_override("grabber", gr)
    bar.add_theme_stylebox_override("grabber_highlight", gh)
    bar.add_theme_stylebox_override("grabber_pressed", gh)

func _layout_toast():
    if not toast.visible: return
    var mobile = Mobile.active(get_viewport())
    var area = Mobile.safe_rect(get_viewport()) if mobile else get_viewport().get_visible_rect()
    var s = 1.0 if mobile else 1.4
    toast.scale = Vector2.ONE * s
    toast_label.add_theme_font_size_override("font_size", 15)
    var w = minf(460.0, (area.size.x - 24.0) / s)
    toast_label.custom_minimum_size.x = w - 24.0
    toast_label.size.x = w - 24.0
    toast.custom_minimum_size = Vector2.ZERO
    toast.size = Vector2(w, toast_label.get_combined_minimum_size().y + 20.0)
    toast.reset_size()
    toast.size.x = w
    toast.position = Vector2(area.position.x + (area.size.x - w * s) / 2.0, area.position.y + 12.0)
    _layout_req_card()

# ---------- Mensagens privadas (DM) ----------
## Conversa a dois: "minha" = não enviada pelo amigo (não depende do id local da sessão).
func _is_mine(m: Dictionary, peer_id: String) -> bool:
    return String(m.get("sender_id", "")) != peer_id

func open_dm(uid: String, peer: Dictionary = {}, back_to := "list"):
    dm_id = uid
    dm_peer = _peer(uid, peer)
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
    _frame(_avatar(head, dm_peer, 44), dm_peer)
    _seal(head, dm_peer, 30)
    var col = VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(col)
    var nick = _label(col, String(dm_peer.get("nickname", "")), 19, Color("f4edda"))
    nick.name = "DmPeer"
    var dm_pres = _label(col, _dm_presence_text(), 13, DIM_TEXT)
    dm_pres.name = "DmPresence"
    var dm_rep = _button(head, "DENUNCIAR", func():
        confirm = {"action": "report_dm", "user_id": dm_id, "title": "DENUNCIAR CONVERSA?", "text": "A equipe FRAIHA vai receber as últimas mensagens que %s te enviou para análise. Ele não fica sabendo quem denunciou." % String(dm_peer.get("nickname", "o jogador")), "return": "dm"}
        _show("confirm"), false, true)
    dm_rep.name = "DmReport"
    dm_scroll = ScrollContainer.new()
    preload("res://ui_v022/touch_scroll.gd").attach(dm_scroll)
    dm_scroll.name = "DmScroll"
    dm_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    dm_scroll.custom_minimum_size.y = 240
    var bg = StyleBoxFlat.new()
    bg.bg_color = Color(0.043, 0.057, 0.085, 0.75)
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
    preload("res://ui_v022/web_text_field.gd").attach(dm_input, true)   # R90 · barra de envio acima do teclado
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
    st.bg_color = Color("3a4762") if mine else Color("252c3a")
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
var invite_return := "profile"   # R51 · de onde o convite saiu (lista de amigos ou perfil)
func open_invite(uid: String, peer: Dictionary):
    invite_peer = _peer(uid, peer)
    invite_sending = false
    invite_return = "list" if screen == "list" else "profile"
    _show("invite_pick")

func send_invite(mode: String, game := "chess", table := "bots"):
    if invite_sending: return
    invite_sending = true
    _show("invite_friends" if picker_game in ["marcha", "xeque"] and screen != "invite_pick" else "invite_pick")
    var msg := {"type": "invite_send", "user_id": String(invite_peer.get("user_id", "")), "mode": mode}
    if game != "chess":
        msg["game"] = game     # R35: MARCHA REAL / XEQUE (mesa online com bots)
        msg["table"] = table   # R144 · "bots" (vocês + bots) ou "online" (vocês juntos na fila online)
    if not _send(msg):
        invite_sending = false
        _show("invite_friends" if picker_game in ["marcha", "xeque"] else "invite_pick")
        notice_text("Sem conexão. Tente de novo em instantes.")

func _on_invite(msg: Dictionary):
    if screen != "invite_pick" and screen != "invite_friends": return
    invite_sending = false
    if String(msg.get("type", "")) == "invite_sent":
        if not picker_game.is_empty():
            # convite feito de dentro do modo: fecha a lista; o cartão do convite mostra a espera
            close()
            return
        # O cartão do convite (com CANCELAR e contagem) aparece no topo; volta para onde estava (lista ou perfil).
        _show(invite_return)
        notice_text("Convite enviado para %s." % String(invite_peer.get("nickname", "")), Color("9fe0a8"))
    else:
        _show(screen if screen == "invite_friends" else "invite_pick")
        notice_text(String(msg.get("message", "Não foi possível convidar.")))

func _build_invite_pick():
    var head = HBoxContainer.new()
    head.add_theme_constant_override("separation", 10)
    box.add_child(head)
    _frame(_avatar(head, invite_peer, 44), invite_peer)
    _seal(head, invite_peer, 30)
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
    # R35 · modos de cartas: vocês dois + 2 bots no servidor (não gasta a partida grátis do dia)
    if picker_game == "chess":
        if invite_sending: _label(box, "Enviando convite…", 14, GOLD, true)
        return
    _label(box, "Ou um modo de cartas:", 15, GOLD)
    var grid2 = GridContainer.new()
    grid2.columns = 1 if _narrow() else 2
    grid2.add_theme_constant_override("h_separation", 8)
    grid2.add_theme_constant_override("v_separation", 8)
    box.add_child(grid2)
    for item in [["marcha", "bots", "MARCHA REAL · dupla contra 2 bots"], ["marcha", "online", "MARCHA REAL · dupla ONLINE"], ["xeque", "bots", "XEQUE · vocês + 2 bots"], ["xeque", "online", "XEQUE · ONLINE juntos"]]:
        var game: String = item[0]
        var table: String = item[1]
        var gb = _button(grid2, item[2], func(): send_invite(game, game, table), true)
        gb.name = "Invite_" + game + ("_online" if table == "online" else "")
        gb.custom_minimum_size.y = 54
        gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        gb.disabled = invite_sending
    if invite_sending: _label(box, "Enviando convite…", 14, GOLD, true)

# R144 · convite de MARCHA REAL / XEQUE: vocês + bots, ou vocês juntos na fila online
func _build_invite_table():
    _label(box, "CONVIDAR " + String(invite_peer.get("nickname", "")), 20, Color("f4edda"), true)
    _label(box, String(GAME_NAMES.get(picker_game, "")), 15, GOLD, true)
    _label(box, "Como vocês querem jogar?", 15, DIM_TEXT, true)
    var duo := picker_game == "marcha"
    for item in [["bots", "VOCÊS + BOTS", "Começa assim que o convite for aceito" if not duo else "Vocês em dupla contra 2 bots"],
            ["online", "JOGAR ONLINE JUNTOS", "Vocês entram juntos na fila" + (" como dupla" if duo else "") + " e a mesa completa com outras pessoas"]]:
        var table: String = item[0]
        var b = _button(box, String(item[1]), func(): send_invite(picker_game, picker_game, table), table == "online")
        b.name = "InviteTable_" + table
        b.custom_minimum_size.y = 58
        b.disabled = invite_sending
        _label(box, String(item[2]), 13, DIM_TEXT, true)
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


# ---------- R35.1 · CONVIDAR AMIGO de dentro de cada modo (JOGAR ONLINE, MARCHA REAL, XEQUE) ----------
const GAME_NAMES := {"chess": "JOGAR ONLINE · xadrez casual", "marcha": "MARCHA REAL", "xeque": "XEQUE"}   # R144 · com bots ou online: escolhido depois
func open_invite_picker(game: String):
    picker_game = game
    invite_sending = false
    notice_text("")
    _show("invite_friends")
    _request_list()

func _build_invite_friends():
    _label(box, "CONVIDAR AMIGO", 20, Color("f4edda"), true)
    _label(box, String(GAME_NAMES.get(picker_game, "")), 15, GOLD, true)
    _label(box, "Toque em CONVIDAR ao lado de um amigo online. O convite vale 60 s.", 13, DIM_TEXT, true)
    if not account.has_profile():
        _label(box, "Entre na sua conta para convidar amigos.", 15, ERROR, true)
        return
    if not has_list:
        _label(box, "Carregando amigos…", 15, GOLD, true)
        return
    var friends: Array = data["friends"]
    if friends.is_empty():
        _label(box, "Você ainda não tem amigos. Abra AMIGOS na tela inicial e busque pelo nickname.", 14, DIM_TEXT, true)
        return
    var order := {"online": 0, "in_match": 1, "offline": 2}
    var list := friends.duplicate()
    list.sort_custom(func(a, b): return int(order.get(String(a.get("presence", "offline")), 2)) < int(order.get(String(b.get("presence", "offline")), 2)))
    for f in list:
        var fid := String(f.get("user_id", ""))
        var pres := String(f.get("presence", "offline"))
        var finfo: Dictionary = f
        var label: String = {"online": "Online", "in_match": "Em partida", "offline": "Offline"}.get(pres, "Offline")
        var col: Color = PRESENCE.get(pres, PRESENCE["offline"])[1]
        var acts := []
        if pres == "online" and not invite_sending: acts = [["CONVIDAR", func(): _picker_invite(fid, finfo), true]]
        var row = _row(f, label, col, acts)
        row.name = "PickFriend_" + String(f.get("nickname", ""))
    if invite_sending: _label(box, "Enviando convite…", 14, GOLD, true)

func _picker_invite(uid: String, peer: Dictionary):
    if picker_game == "chess":
        open_invite(uid, peer)        # escolher o ritmo (3/5/10/20 min)
        return
    invite_peer = _peer(uid, peer)
    invite_return = "invite_friends"
    _show("invite_table")   # R144 · com bots ou online?
