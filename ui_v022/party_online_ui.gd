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
const THEME := {"xeque": [Color("2a0b12"), Color("8e1c2c")], "marcha": [Color("2a0b12"), Color("8e1c2c")]}
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
    var s := _s()
    # R177f · moldura ornamentada desenhada (degradê vinho, filete dourado duplo, cantos com joia, brasão no topo)
    var st := StyleBoxEmpty.new()
    for side in ["left", "right"]: st.set("content_margin_" + side, 40 * s)
    st.content_margin_top = 44 * s
    st.content_margin_bottom = 34 * s
    panel.add_theme_stylebox_override("panel", st)
    if not panel.draw.is_connected(_draw_panel): panel.draw.connect(_draw_panel)
    panel.custom_minimum_size = Vector2(_panel_w(), 0)   # largura antes do conteúdo: o texto quebra na largura certa
    panel.size = panel.custom_minimum_size
    _label(NAMES.get(game, ""), 20, GOLD, FONT_TITLE)
    if which == "choose":
        _label("COMO VOCÊ QUER JOGAR?", 32, CREAM, FONT_TITLE)
        _divider()
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
    b.custom_minimum_size = Vector2(0, (150.0 if not _narrow() else 120.0) * s)
    for st in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
    b.set_meta("icon_path", icon_path)
    b.set_meta("primary", primary)
    b.draw.connect(func(): _draw_card(b))
    b.mouse_entered.connect(b.queue_redraw)
    b.mouse_exited.connect(b.queue_redraw)
    b.button_down.connect(b.queue_redraw)
    b.button_up.connect(b.queue_redraw)
    parent.add_child(b)
    var h := HBoxContainer.new()
    h.set_anchors_preset(Control.PRESET_FULL_RECT)
    h.offset_left = (26.0 + 92.0 + 16.0) * s   # espaço do medalhão (desenhado no _draw_card)
    h.offset_right = -16 * s
    h.mouse_filter = Control.MOUSE_FILTER_IGNORE
    b.add_child(h)
    var col := VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.alignment = BoxContainer.ALIGNMENT_CENTER
    col.add_theme_constant_override("separation", int(4 * s))
    col.mouse_filter = Control.MOUSE_FILTER_IGNORE
    h.add_child(col)
    var t := Label.new()
    t.text = title
    _style_label(t, 27, GOLD, FONT_TITLE, HORIZONTAL_ALIGNMENT_LEFT, false)
    t.add_theme_color_override("font_outline_color", Color(0.12, 0.03, 0.02, 0.95))
    t.add_theme_constant_override("outline_size", 5)
    col.add_child(t)
    var d := Label.new()
    d.text = sub
    _style_label(d, 17, CREAM, FONT_TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
    d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    col.add_child(d)
    return b

# ---------------------------------------------------------------- R177f · desenho ornamentado
const WINE_TOP := Color("4a0f1a")
const WINE_BOT := Color("1c050b")
const GOLD_D := Color("a8792a")
const GOLD_L := Color("ffe39a")

func _vgrad(ci: CanvasItem, r: Rect2, c0: Color, c1: Color):
    ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([c0, c0, c1, c1]))

func _diamond(ci: CanvasItem, c: Vector2, rr: float, edge: Color, fill: Color):
    ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -rr), c + Vector2(rr, 0), c + Vector2(0, rr), c + Vector2(-rr, 0)]), edge)
    var q := rr * 0.55
    ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -q), c + Vector2(q, 0), c + Vector2(0, q), c + Vector2(-q, 0)]), fill)
    ci.draw_circle(c + Vector2(-q * 0.25, -q * 0.3), q * 0.22, Color(1, 1, 1, 0.55))

## moldura: sombra, degradê, filete dourado grosso + fino por dentro, cantos com joia
func _ornate(ci: CanvasItem, r: Rect2, s: float, top: Color, bot: Color, gem: Color, glow := 0.0):
    for i in 6: ci.draw_rect(r.grow((3 + i * 3) * s), Color(0, 0, 0, 0.10 - i * 0.015), false, 3.0 * s)
    if glow > 0.0:
        for i in 5: ci.draw_rect(r.grow((2 + i * 3) * s), Color(1.0, 0.82, 0.4, glow * (0.22 - i * 0.04)), false, 3.0 * s)
    _vgrad(ci, r, top, bot)
    # vinheta: bordas por dentro mais escuras
    for i in 5:
        ci.draw_rect(r.grow(-(i * 4.0 + 2.0) * s), Color(0, 0, 0, 0.09 - i * 0.016), false, 4.0 * s)
    var bw := maxf(2.0, 3.0 * s)
    ci.draw_rect(r, GOLD_D, false, bw + 2.0 * s)
    ci.draw_rect(r, GOLD, false, bw)
    ci.draw_rect(r.grow(-1.0 * s), Color(GOLD_L, 0.6), false, maxf(1.0, s))
    var inner := r.grow(-8.0 * s)
    ci.draw_rect(inner, Color(GOLD, 0.55), false, maxf(1.0, 1.4 * s))
    var L := 22.0 * s
    for c in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
        var sx := 1.0 if c.x < r.get_center().x else -1.0
        var sy := 1.0 if c.y < r.get_center().y else -1.0
        ci.draw_line(c + Vector2(0, sy * 3 * s), c + Vector2(sx * L, sy * 3 * s), GOLD, 2.0 * s, true)
        ci.draw_line(c + Vector2(sx * 3 * s, 0), c + Vector2(sx * 3 * s, sy * L), GOLD, 2.0 * s, true)
    for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
        _diamond(ci, c, 9.0 * s, GOLD, gem)

func _draw_panel():
    var s := _s()
    var r := Rect2(Vector2.ZERO, panel.size).grow(-6.0 * s)
    _ornate(panel, r, s, WINE_TOP, WINE_BOT, Color("c4161f"))
    # brasão no topo: losango grande com joia azul e filetes para os lados
    var c := Vector2(r.get_center().x, r.position.y)
    panel.draw_line(c + Vector2(-140 * s, 0), c + Vector2(-26 * s, 0), GOLD_L, 2.0 * s, true)
    panel.draw_line(c + Vector2(26 * s, 0), c + Vector2(140 * s, 0), GOLD_L, 2.0 * s, true)
    _diamond(panel, c, 20.0 * s, GOLD, Color("2a5fd6"))
    _diamond(panel, Vector2(r.get_center().x, r.end.y), 13.0 * s, GOLD, Color("c4161f"))

func _divider():
    var s := _s()
    var d := Control.new()
    d.custom_minimum_size = Vector2(0, 18 * s)
    d.mouse_filter = Control.MOUSE_FILTER_IGNORE
    d.draw.connect(func():
        var w := d.size.x
        var y := d.size.y / 2.0
        var cx := w / 2.0
        for side in [-1.0, 1.0]:
            var pts := PackedVector2Array([Vector2(cx + side * 16 * s, y), Vector2(cx + side * w * 0.32, y)])
            d.draw_polyline(pts, GOLD, 2.0 * s, true)
            _diamond(d, Vector2(cx + side * w * 0.32, y), 4.0 * s, GOLD, GOLD)
        _diamond(d, Vector2(cx, y), 8.0 * s, GOLD, Color("c4161f")))
    body.add_child(d)

## cartão de escolha: moldura do jogo + medalhão dourado com o ícone (foto do bot / pessoas desenhadas)
func _draw_card(b: Button):
    var s := _s()
    var hov := b.is_hovered() or b.button_pressed
    var down := b.is_pressed()
    var r := Rect2(Vector2.ZERO, b.size).grow(-4.0 * s)
    var top := Color("8e1c2c").lightened(0.10 if hov else 0.0)
    var bot := Color("3d0a14").lightened(0.06 if hov else 0.0)
    if down: top = top.darkened(0.15)
    _ornate(b, r, s, top, bot, Color("2a5fd6") if bool(b.get_meta("primary", false)) else Color("c4161f"), 1.0 if hov else 0.0)
    # medalhão
    var mr := minf(46.0 * s, r.size.y / 2.0 - 12.0 * s)
    var mc := Vector2(r.position.x + 22.0 * s + mr, r.get_center().y)
    for i in 4: b.draw_circle(mc, mr + (6 - i) * s, Color(0, 0, 0, 0.12))
    b.draw_circle(mc, mr + 3.0 * s, GOLD_D, true, -1.0, true)
    b.draw_circle(mc, mr + 1.0 * s, GOLD, true, -1.0, true)
    b.draw_circle(mc, mr - 3.0 * s, Color("120408"), true, -1.0, true)
    var path := String(b.get_meta("icon_path", ""))
    if path == ICON_BOTS:
        var tex: Texture2D = load(path)
        var px := Vector2(mr * 2.0 - 10.0 * s, mr * 2.0 - 10.0 * s)
        var t2: Texture2D = preload("res://ui_v022/crisp_tex.gd").at(tex, px)
        # recorte redondo: desenha a imagem num círculo (polígono com UV)
        var pts := PackedVector2Array()
        var uvs := PackedVector2Array()
        var rad := mr - 5.0 * s
        for i in 48:
            var a := TAU * i / 48.0
            var v := Vector2(cos(a), sin(a))
            pts.append(mc + v * rad)
            uvs.append(Vector2(0.5, 0.5) + v * 0.5)
        b.draw_colored_polygon(pts, Color.WHITE, uvs, t2)
    else:
        _people(b, mc, mr * 0.78, s)
    b.draw_arc(mc, mr - 3.0 * s, 0, TAU, 64, Color(GOLD_L, 0.7), maxf(1.0, 1.5 * s), true)

## três pessoas (vetor, bordas lisas) — antes era um ícone de 61 px ampliado e serrilhado
func _people(ci: CanvasItem, c: Vector2, r: float, s: float):
    var col := Color("f5cf6a")
    var shade := Color("b8872c")
    for spec in [[-0.62, 0.78, shade], [0.62, 0.78, shade], [0.0, 1.0, col]]:
        var ox: float = spec[0] * r
        var k: float = spec[1]
        var cc: Color = spec[2]
        var hc := c + Vector2(ox, -0.34 * r * k)
        ci.draw_circle(hc, 0.27 * r * k, cc, true, -1.0, true)
        var body_c := c + Vector2(ox, 0.42 * r * k)
        var w := 0.5 * r * k
        var pts := PackedVector2Array()
        for i in 25:
            var a := PI + PI * i / 24.0
            pts.append(body_c + Vector2(cos(a) * w, sin(a) * w * 0.95))
        pts.append(body_c + Vector2(w, 0.18 * r * k))
        pts.append(body_c + Vector2(-w, 0.18 * r * k))
        ci.draw_colored_polygon(pts, cc)
        pts.append(pts[0])
        ci.draw_polyline(pts, cc, 1.2, true)

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

## R145 · botão JOGAR ONLINE direto na tela do modo (sem a caixa de escolha). Devolve o erro ("" = entrou na fila).
func queue_online(p_game: String) -> String:
    game = p_game
    if account == null or not account.has_method("has_profile") or not account.has_profile(): return "Entre na sua conta para jogar online."
    if not account.send_server({"type": "party_queue", "game": game}): return "Sem conexão com o servidor. Tente de novo em instantes."
    open_search(game, 1, 1)
    return ""

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
