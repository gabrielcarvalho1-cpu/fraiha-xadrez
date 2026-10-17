extends CanvasLayer
## R144 · MARCHA REAL / XEQUE: escolha CONTRA BOTS ou JOGAR ONLINE, e a tela de BUSCA da fila online.
## Por cima da tela do modo (layer 70). Quem decide a mesa é o servidor (online_v021/modes/party_queue.js):
## 4 pessoas → começa na hora; 2–3 → depois de ~20 s com bots nos lugares vazios; sozinho → continua
## esperando, e depois de 30 s aparece JOGAR CONTRA BOTS. A mesa chega por party_start (stage.gd).
const FONT_TITLE := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_BODY := preload("res://ui_kit/fonts/Alegreya-Bold.woff")
const FONT_TEXT := preload("res://ui_kit/fonts/Alegreya-Medium.woff")
const GOLD := Color("f5cf6a")
const CREAM := Color("f4ead2")
const DIM := Color("c9bfa6")
const ICON_BOTS := "res://profile/avatars/ferro_reward.png"
const ICON_ONLINE := "res://ui_v022/assets/online_tab_icon_casual.png"
const ALONE_HINT_S := 30
## cores de cada modo: [fundo do painel, borda/detalhe]
const THEME := {"xeque": [Color("2a0b12"), Color("8e1c2c")], "marcha": [Color("0d241b"), Color("1f5a3e")]}
const NAMES := {"xeque": "XEQUE", "marcha": "MARCHA REAL"}

signal bots_chosen(game: String)

var stage
var account
var game := ""
var screen := ""            # "" | choose | search
var group := 1
var waiting := 0
var since_ms := 0
var dim: ColorRect
var panel: PanelContainer
var body: VBoxContainer
var time_label: Label
var count_label: Label
var alone_box: VBoxContainer
var error_label: Label

func setup(p_stage):
    stage = p_stage
    account = stage.get("account")
    layer = 70
    name = "PartyOnlineUI"
    visible = false
    dim = ColorRect.new()
    dim.color = Color(0.02, 0.02, 0.04, 0.72)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    panel = PanelContainer.new()
    panel.name = "PartyOnlinePanel"
    add_child(panel)
    body = VBoxContainer.new()
    body.add_theme_constant_override("separation", 14)
    panel.add_child(body)
    if account != null and account.has_signal("server_message"): account.server_message.connect(on_message)
    get_viewport().size_changed.connect(_layout)

func is_open() -> bool:
    return visible

# ---------------------------------------------------------------- telas
func open_choice(p_game: String):
    game = p_game
    _build("choose")

func open_search(p_game: String, p_group := 1, p_waiting := 0):
    game = p_game
    group = maxi(1, p_group)
    waiting = maxi(p_waiting, group)
    since_ms = Time.get_ticks_msec()
    _build("search")

func close():
    visible = false
    screen = ""

func _build(which: String):
    screen = which
    for c in body.get_children():
        body.remove_child(c)
        c.queue_free()
    var th: Array = THEME.get(game, THEME["xeque"])
    var st := StyleBoxFlat.new()
    st.bg_color = Color(th[0], 0.97)
    st.border_color = GOLD
    st.set_border_width_all(3)
    st.set_corner_radius_all(10)
    st.shadow_color = Color(0, 0, 0, 0.6)
    st.shadow_size = 18
    for side in ["left", "right"]: st.set("content_margin_" + side, 26)
    for side in ["top", "bottom"]: st.set("content_margin_" + side, 22)
    panel.add_theme_stylebox_override("panel", st)
    var s := _s()
    panel.custom_minimum_size = Vector2(_panel_w(), 0)   # largura antes do conteúdo: o texto quebra na largura certa
    panel.size = panel.custom_minimum_size
    _label(NAMES.get(game, ""), 18, GOLD, FONT_TITLE)
    if which == "choose":
        _label("COMO VOCÊ QUER JOGAR?", 30, CREAM, FONT_TITLE)
        var row := BoxContainer.new()
        row.vertical = _narrow()
        row.add_theme_constant_override("separation", int(14 * s))
        body.add_child(row)
        var bots := _option(row, ICON_BOTS, "CONTRA BOTS", "Comece agora contra o computador", true)
        bots.name = "PartyChoiceBots"
        bots.pressed.connect(_choose_bots)
        var onl := _option(row, ICON_ONLINE, "JOGAR ONLINE", "Fila com outras pessoas" if game == "xeque" else "Fila com outras pessoas · duplas", false)
        onl.name = "PartyChoiceOnline"
        onl.pressed.connect(_choose_online)
        error_label = _label("", 16, Color("ff9d86"), FONT_BODY)
        error_label.visible = false
        var back := _button("VOLTAR", false)
        back.name = "PartyChoiceBack"
        back.pressed.connect(close)
    else:
        _label("PROCURANDO JOGADORES", 30, CREAM, FONT_TITLE)
        _label("Você e seu amigo estão na fila" if group >= 2 else "A mesa tem 4 lugares: os vazios viram bots se demorar", 17, DIM, FONT_TEXT)
        time_label = _label("0:00", 46, GOLD, FONT_TITLE)
        time_label.name = "PartySearchTime"
        count_label = _label("", 18, CREAM, FONT_BODY)
        count_label.name = "PartySearchCount"
        alone_box = VBoxContainer.new()
        alone_box.add_theme_constant_override("separation", 10)
        body.add_child(alone_box)
        var hint := Label.new()
        hint.text = "Ninguém mais na fila agora. Continue esperando ou jogue contra bots."
        _style_label(hint, 16, DIM, FONT_TEXT)
        alone_box.add_child(hint)
        var b := _button("JOGAR CONTRA BOTS", true)
        b.name = "PartySearchBots"
        body.remove_child(b)
        alone_box.add_child(b)
        b.pressed.connect(_alone_bots)
        alone_box.visible = false
        error_label = _label("", 16, Color("ff9d86"), FONT_BODY)
        error_label.visible = false
        var c := _button("CANCELAR BUSCA", false)
        c.name = "PartySearchCancel"
        c.pressed.connect(_cancel_search)
        _tick()
    visible = true
    _layout()
    call_deferred("_layout")

func _option(parent: Container, icon_path: String, title: String, sub: String, primary: bool) -> Button:
    var s := _s()
    var b := Button.new()
    b.focus_mode = Control.FOCUS_NONE
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    b.custom_minimum_size = Vector2(0, (150.0 if not _narrow() else 118.0) * s)
    var th: Array = THEME.get(game, THEME["xeque"])
    for pair in [["normal", 0.0], ["hover", 0.12], ["pressed", -0.1]]:
        var st := StyleBoxFlat.new()
        st.bg_color = Color(th[1]).lightened(maxf(0.0, pair[1])).darkened(maxf(0.0, -pair[1]))
        st.border_color = GOLD if primary else Color("d9b25c")
        st.set_border_width_all(3)
        st.set_corner_radius_all(8)
        b.add_theme_stylebox_override(pair[0], st)
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    parent.add_child(b)
    var h := HBoxContainer.new()
    h.set_anchors_preset(Control.PRESET_FULL_RECT)
    h.offset_left = 16 * s
    h.offset_right = -12 * s
    h.add_theme_constant_override("separation", int(14 * s))
    h.mouse_filter = Control.MOUSE_FILTER_IGNORE
    b.add_child(h)
    var ic := TextureRect.new()
    ic.texture = load(icon_path)
    ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    ic.custom_minimum_size = Vector2(76, 76) * s
    ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
    h.add_child(ic)
    var col := VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.alignment = BoxContainer.ALIGNMENT_CENTER
    col.mouse_filter = Control.MOUSE_FILTER_IGNORE
    h.add_child(col)
    var t := Label.new()
    t.text = title
    _style_label(t, 26, GOLD, FONT_TITLE, HORIZONTAL_ALIGNMENT_LEFT, false)
    col.add_child(t)
    var d := Label.new()
    d.text = sub
    _style_label(d, 17, CREAM, FONT_TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
    col.add_child(d)
    return b

func _button(text: String, primary: bool) -> Button:
    var s := _s()
    var b := Button.new()
    b.text = text
    b.focus_mode = Control.FOCUS_NONE
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    b.custom_minimum_size = Vector2(380 * s, 58 * s)
    b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    for pair in [["normal", 0.0], ["hover", 0.12], ["pressed", -0.1]]:
        var st := StyleBoxFlat.new()
        st.bg_color = (Color("c99a2e") if primary else Color("13254a")).lightened(maxf(0.0, pair[1])).darkened(maxf(0.0, -pair[1]))
        st.border_color = Color("f7dc8a") if primary else GOLD
        st.set_border_width_all(2)
        st.set_corner_radius_all(6)
        b.add_theme_stylebox_override(pair[0], st)
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    b.add_theme_font_override("font", FONT_TITLE)
    b.add_theme_font_size_override("font_size", int(22 * s))
    for k in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(k, Color("1b1205") if primary else GOLD)
    body.add_child(b)
    return b

func _label(text: String, px: int, col: Color, font: Font) -> Label:
    var l := Label.new()
    l.text = text
    _style_label(l, px, col, font)
    body.add_child(l)
    return l

func _style_label(l: Label, px: int, col: Color, font: Font, align := HORIZONTAL_ALIGNMENT_CENTER, wrap := true):
    l.horizontal_alignment = align
    if wrap:
        # quebra na largura do painel (sem largura definida o Godot mede o texto "em pé" e o painel cresce)
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        l.custom_minimum_size.x = maxf(10.0, _panel_w() - 60.0 * _s())
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    l.add_theme_font_override("font", font)
    l.add_theme_font_size_override("font_size", maxi(11, int(px * _s())))
    l.add_theme_color_override("font_color", col)
    l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
    l.add_theme_constant_override("outline_size", 3)

func _vp() -> Vector2:
    return get_viewport().get_visible_rect().size

func _narrow() -> bool:
    return _vp().x < 700.0

## escala do texto/controles: PC em 1080p = 1; celular estreito ~0,62
func _s() -> float:
    var v := _vp()
    return clampf(minf(v.x / 1100.0, v.y / 760.0), 0.55, 1.3)

func _panel_w() -> float:
    var v := _vp()
    return v.x - 32.0 if _narrow() else minf(v.x - 32.0, 900.0 * _s())

func _layout():
    if not visible: return
    var v := _vp()
    var w := _panel_w()
    panel.custom_minimum_size = Vector2(w, 0)
    panel.size = Vector2(w, 0)
    panel.reset_size()
    panel.size = Vector2(w, panel.get_combined_minimum_size().y)
    panel.position = ((v - panel.size) / 2.0).round()

# ---------------------------------------------------------------- ações
func _choose_bots():
    close()
    bots_chosen.emit(game)

func _choose_online():
    if account == null or not account.has_method("has_profile") or not account.has_profile():
        _err("Entre na sua conta para jogar online.")
        return
    if not account.send_server({"type": "party_queue", "game": game}):
        _err("Sem conexão com o servidor. Tente de novo em instantes.")
        return
    open_search(game, 1, 1)

func _err(text: String):
    if not is_instance_valid(error_label): return
    error_label.text = text
    error_label.visible = not text.is_empty()
    _layout()

func _cancel_search():
    if account != null: account.send_server({"type": "party_queue_cancel", "game": game})
    close()

func _alone_bots():
    if account != null: account.send_server({"type": "party_queue_cancel", "game": game})
    close()
    bots_chosen.emit(game)

var _last_h := -1.0
func _process(_d):
    if not visible: return
    if screen == "search": _tick()
    var h := panel.get_combined_minimum_size().y
    if not is_equal_approx(h, _last_h):
        _last_h = h
        _layout()

func _tick():
    var s := int((Time.get_ticks_msec() - since_ms) / 1000)
    var t := "%d:%02d" % [s / 60, s % 60]
    if is_instance_valid(time_label) and time_label.text != t: time_label.text = t
    var others := maxi(0, waiting - group)
    var c := ("%d pessoa%s na fila com você" % [others, "" if others == 1 else "s"]) if others > 0 else "Esperando outros jogadores…"
    if is_instance_valid(count_label) and count_label.text != c:
        count_label.text = c
        _layout()
    var alone := others == 0 and s >= ALONE_HINT_S
    if is_instance_valid(alone_box) and alone_box.visible != alone:
        alone_box.visible = alone
        _layout()

# ---------------------------------------------------------------- mensagens do servidor
func on_message(msg: Dictionary):
    var t := String(msg.get("type", ""))
    if not t.begins_with("party_"): return
    match t:
        "party_queued":
            var g := String(msg.get("game", ""))
            if screen != "search" or g != game: open_search(g, int(msg.get("group", 1)), int(msg.get("waiting", 1)))
            else: waiting = maxi(waiting, int(msg.get("waiting", waiting)))
        "party_queue_status":
            if String(msg.get("game", "")) != game: return
            var g2 := maxi(1, int(msg.get("group", group)))
            waiting = int(msg.get("waiting", waiting))
            if screen != "search": open_search(game, g2, waiting)
            elif g2 != group:
                group = g2
                _build("search")   # "Você e seu amigo estão na fila" (o tempo continua)
        "party_queue_error":
            if screen == "search": _build("choose")
            _err(String(msg.get("message", "Não foi possível entrar na fila.")))
        "party_queue_cancelled":
            if screen != "search": return
            if bool(msg.get("by_friend", false)) or msg.has("error"):
                _build("choose")
                _err(String(msg.get("error", "Seu amigo saiu da fila.")))
            else:
                close()
        "party_start":
            close()
