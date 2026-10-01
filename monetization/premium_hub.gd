extends CanvasLayer
## FRAIHA PREMIUM — sobreposição aberta a partir de CONFIGURAÇÕES.
## Navegação: Produto (Fundador/Club) → Hub Premium → Configurações.
## MONETIZAÇÃO V1: tudo é SIMULAÇÃO (PAYMENT_MODE = "mock"); nenhum pagamento é processado.
signal closed

const Art := preload("res://monetization/premium_art.gd")
const Catalog := preload("res://monetization/monetization_catalog.gd")
const StateScript := preload("res://monetization/monetization_state.gd")
const Gateway := preload("res://monetization/payment_gateway.gd")
const FounderUI := preload("res://monetization/founder_ui.gd")
const ClubUI := preload("res://monetization/club_ui.gd")
const PaymentUI := preload("res://monetization/payment_mock_ui.gd")
const Mobile := preload("res://ui_v022/mobile_layout.gd")

var state
var gateway
var page := "hub"
var root: Control
var backdrop: Control
var sparkles: Control
var header: HBoxContainer
var back_button: Button
var crumbs: HBoxContainer
var banner: Control
var scroll: ScrollContainer
var column: VBoxContainer
var modal_layer: Control
var modal: Control = null
var view := Vector2(1920, 1080)
var narrow := false      # celular retrato / telas estreitas: 1 coluna
var compact := false     # pouca altura (celular paisagem)
var k := 1.0             # escala de fonte

func _init(monetization_state = null):
    layer = 60
    name = "PremiumHub"
    state = monetization_state if monetization_state != null else StateScript.new()
    gateway = Gateway.new(state)

func _ready():
    _build()
    get_viewport().size_changed.connect(_relayout)
    visible = false

# ---------------------------------------------------------------- navegação
func open(page_id := "hub"):
    visible = true
    root.visible = true
    show_page(page_id)

func close():
    close_modal()
    visible = false
    root.visible = false
    closed.emit()

func is_open() -> bool:
    return visible

func back():
    if modal != null:
        close_modal()
    elif page != "hub":
        show_page("hub")
    else:
        close()

func show_page(id: String):
    close_modal()
    page = id
    _rebuild()
    scroll.scroll_vertical = 0

func _input(event):
    if not visible: return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        back()
        get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- estrutura
func _build():
    root = Control.new()
    root.name = "PremiumRoot"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    backdrop = Control.new()
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    backdrop.draw.connect(_draw_backdrop)
    root.add_child(backdrop)
    sparkles = Art.Sparkles.new(40)
    root.add_child(sparkles)
    var outer := VBoxContainer.new()
    outer.name = "PremiumOuter"
    outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    outer.add_theme_constant_override("separation", 8)
    root.add_child(outer)
    header = HBoxContainer.new()
    header.name = "PremiumHeader"
    header.add_theme_constant_override("separation", 14)
    outer.add_child(header)
    back_button = Art.Cta.new("VOLTAR", "dark", 54, 18)
    back_button.name = "PremiumBack"
    back_button.icon_kind = ""
    back_button.pressed.connect(back)
    header.add_child(back_button)
    crumbs = HBoxContainer.new()
    crumbs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    crumbs.alignment = BoxContainer.ALIGNMENT_BEGIN
    crumbs.add_theme_constant_override("separation", 8)
    header.add_child(crumbs)
    var test_stamp := Art.Stamp.new("MODO TESTE", "test", 15)
    test_stamp.name = "HeaderTestStamp"
    header.add_child(test_stamp)
    banner = _test_banner()
    outer.add_child(banner)
    scroll = ScrollContainer.new()
    scroll.name = "PremiumScroll"
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    outer.add_child(scroll)
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    var center := CenterContainer.new()
    center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    center.use_top_left = false
    scroll.add_child(center)
    column = VBoxContainer.new()
    column.name = "PremiumColumn"
    column.add_theme_constant_override("separation", 22)
    center.add_child(column)
    modal_layer = Control.new()
    modal_layer.name = "PremiumModals"
    modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(modal_layer)
    _relayout()

func _test_banner() -> Control:
    var f := Art.Frame.new("test", 10)
    f.name = "TestBanner"
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 12)
    f.add_child(row)
    row.add_child(Art.Glyph.new("lock", 22, Color("f2a070")))
    var l := Art.label(row, "SIMULAÇÃO DE DESENVOLVIMENTO  ·  preços de teste R$ 0,00  ·  nenhum pagamento é processado e nenhum dado financeiro é pedido", 15, Color("ffe2c8"))
    l.name = "TestBannerText"
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    return f

func _relayout():
    if root == null: return
    view = root.get_viewport_rect().size
    var mobile := Mobile.active(root.get_viewport())
    narrow = view.x < 760.0
    compact = view.y < 520.0
    k = 1.0 if view.x >= 1100.0 else (0.84 if view.x >= 760.0 else 0.74)
    if compact and not narrow: k = minf(k, 0.64)
    Art.stamp_cap = (view.x - 150.0) if narrow else 0.0
    var gutter := 16.0 if mobile or narrow else 40.0
    var outer: Control = root.get_node("PremiumOuter")
    outer.offset_left = gutter
    outer.offset_right = -gutter
    outer.offset_top = 10.0 if compact else (14.0 if narrow else 22.0)
    outer.offset_bottom = -8.0
    var col_w := minf(view.x - gutter * 2.0 - 18.0, 1240.0)
    column.custom_minimum_size.x = col_w
    back_button.custom_minimum_size = Vector2(150 if narrow else (210 if compact else 260), 42 if compact else (52 if narrow else 58))
    back_button.font_size = 16 if narrow or compact else 19
    var stamp: Control = header.get_node("HeaderTestStamp")
    stamp.font_size = 12 if narrow or compact else 15
    stamp._measure()
    var bl: Label = banner.find_child("TestBannerText", true, false)
    bl.add_theme_font_size_override("font_size", 12 if narrow or compact else 15)
    bl.text = "SIMULAÇÃO · R$ 0,00 de teste · nenhum pagamento é processado" if narrow or compact else "SIMULAÇÃO DE DESENVOLVIMENTO  ·  preços de teste R$ 0,00  ·  nenhum pagamento é processado e nenhum dado financeiro é pedido"
    if visible: _rebuild()
    backdrop.queue_redraw()

func _draw_backdrop():
    var s := backdrop.size
    backdrop.draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.04, 0.025, 1.0))
    # Vinheta + luz dourada no alto (salão do reino).
    for i in 10:
        var a := 0.035 * (1.0 - i / 10.0)
        backdrop.draw_circle(Vector2(s.x * 0.5, -s.y * 0.15), s.x * (0.25 + i * 0.07), Color(1.0, 0.78, 0.35, a))
    var stripe := Color(0.79, 0.6, 0.27, 0.10)
    backdrop.draw_line(Vector2(0, 2), Vector2(s.x, 2), Color(0.79, 0.6, 0.27, 0.5), 2.0)
    backdrop.draw_line(Vector2(0, s.y - 2), Vector2(s.x, s.y - 2), Color(0.79, 0.6, 0.27, 0.5), 2.0)
    var step := 64.0
    var x := -s.y
    while x < s.x:
        backdrop.draw_line(Vector2(x, s.y), Vector2(x + s.y, 0), stripe * Color(1, 1, 1, 0.25), 1.0)
        x += step

func _set_crumbs():
    for c in crumbs.get_children():
        crumbs.remove_child(c)
        c.queue_free()
    var parts := ["CONFIGURAÇÕES", "FRAIHA PREMIUM"]
    if page == "founder": parts.append("PACOTE FUNDADOR")
    elif page == "club": parts.append("CLUB FRAIHA")
    if narrow: parts = [{"hub": "PREMIUM", "founder": "FUNDADOR", "club": "CLUB"}.get(page, "PREMIUM")]
    for i in parts.size():
        if i > 0: crumbs.add_child(Art.Glyph.new("star", 12, Color(0.79, 0.6, 0.27, 0.8)))
        var last := i == parts.size() - 1
        var l := Art.label(crumbs, parts[i], fs(20 if last else 15), Art.GOLD if last else Art.MUTED, Art.FONT_BOLD if last else Art.FONT_SEMI)
        l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
        l.autowrap_mode = TextServer.AUTOWRAP_OFF
        l.clip_text = narrow
        if narrow: l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    back_button.text = "VOLTAR" if narrow else ("CONFIGURAÇÕES" if page == "hub" else "FRAIHA PREMIUM")
    back_button.icon_kind = ""
    back_button.queue_redraw()

func _rebuild():
    if column == null: return
    _set_crumbs()
    for c in column.get_children():
        column.remove_child(c)
        c.queue_free()
    match page:
        "founder": FounderUI.build(self, column)
        "club": ClubUI.build(self, column)
        _: _build_hub(column)
    if Catalog.dev_tools_enabled(): _dev_tools(column)
    var tail := Control.new()
    tail.custom_minimum_size.y = 40 if narrow else 24
    column.add_child(tail)

# ---------------------------------------------------------------- hub
func _build_hub(parent: VBoxContainer):
    var hero := VBoxContainer.new()
    hero.alignment = BoxContainer.ALIGNMENT_CENTER
    hero.add_theme_constant_override("separation", 6)
    parent.add_child(hero)
    var crown_row := HBoxContainer.new()
    crown_row.alignment = BoxContainer.ALIGNMENT_CENTER
    crown_row.add_theme_constant_override("separation", 18)
    hero.add_child(crown_row)
    crown_row.add_child(Art.Glyph.new("shield", 46 * k, Art.GOLD_MID))
    crown_row.add_child(Art.Glyph.new("crown", 74 * k, Art.GOLD, true))
    crown_row.add_child(Art.Glyph.new("shield", 46 * k, Art.GOLD_MID))
    var t := Art.label(hero, "FRAIHA PREMIUM", fs(58), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    t.add_theme_constant_override("outline_size", 8)
    t.add_theme_color_override("font_outline_color", Color(0.16, 0.08, 0.0, 0.95))
    Art.label(hero, "Apoie o reino, vista sua identidade e evolua o seu jogo.", fs(22), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
    hero.add_child(fair_play_note())
    var cards: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    cards.add_theme_constant_override("separation", 22 if not narrow else 18)
    parent.add_child(cards)
    cards.add_child(_hub_card_founder())
    cards.add_child(_hub_card_club())

func _hub_card_founder() -> Control:
    var f := Art.Frame.new("founder", int(26 * k))
    f.name = "HubFounderCard"
    f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    f.glow = true
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", int(10 * k))
    f.add_child(v)
    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 14)
    v.add_child(top)
    top.add_child(Art.Glyph.new("crown", 64 * k, Art.GOLD, true))
    var tv := VBoxContainer.new()
    tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(tv)
    tv.add_child(Art.Stamp.new("EDIÇÃO DE LANÇAMENTO", "new", int(13 * maxf(k, 0.9))))
    Art.label(tv, "PACOTE FUNDADOR FRAIHA", fs(32), Art.GOLD, Art.FONT_BOLD)
    if state.founder_view():
        v.add_child(status_badge("FUNDADOR DO REINO · ATIVO (TESTE)"))
    v.add_child(price_block("founder", false))
    Art.label(v, "Faça parte de quem ajudou a construir o reino desde o início.", fs(20), Art.CREAM)
    var chips := HFlowContainer.new()
    chips.add_theme_constant_override("h_separation", 8)
    chips.add_theme_constant_override("v_separation", 6)
    v.add_child(chips)
    chips.add_child(Art.Stamp.new("PAGAMENTO ÚNICO", "info", 13))
    chips.add_child(Art.Stamp.new("EDIÇÃO LIMITADA · %d" % Catalog.FOUNDER_LIMIT, "info", 13))
    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    v.add_child(spacer)
    var cta := Art.Cta.new("CONHECER PACOTE FUNDADOR", "gold", 66 * maxf(k, 0.85), int(22 * maxf(k, 0.85)))
    cta.name = "OpenFounder"
    cta.shimmer = true
    cta.pressed.connect(func(): show_page("founder"))
    v.add_child(cta)
    return f

func _hub_card_club() -> Control:
    var f := Art.Frame.new("club", int(26 * k))
    f.name = "HubClubCard"
    f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", int(10 * k))
    f.add_child(v)
    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 14)
    v.add_child(top)
    top.add_child(Art.Glyph.new("book", 64 * k, Art.GOLD, true))
    var tv := VBoxContainer.new()
    tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(tv)
    tv.add_child(Art.Stamp.new("ASSINATURA MENSAL", "info", int(13 * maxf(k, 0.9))))
    Art.label(tv, "CLUB FRAIHA", fs(32), Art.GOLD, Art.FONT_BOLD)
    Art.label(v, "JOGUE.  ENTENDA.  EVOLUA.", fs(22), Color("bfe8a8"), Art.FONT_BOLD)
    if state.club_subscription_view():
        v.add_child(status_badge("CLUB FRAIHA ATIVO (TESTE)"))
    elif state.founder_trial_view():
        v.add_child(status_badge("%d DIAS DE CLUB · BENEFÍCIO FUNDADOR · SIMULAÇÃO" % Catalog.FOUNDER_CLUB_DAYS))
    v.add_child(price_block("club_monthly", true))
    Art.label(v, "Transforme suas partidas em aprendizado: análise, treino dos seus erros e evolução acompanhada.", fs(20), Art.CREAM)
    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    v.add_child(spacer)
    var cta := Art.Cta.new("CONHECER CLUB FRAIHA", "green", 66 * maxf(k, 0.85), int(22 * maxf(k, 0.85)))
    cta.name = "OpenClub"
    cta.pressed.connect(func(): show_page("club"))
    v.add_child(cta)
    return f

# ---------------------------------------------------------------- ferramentas DEV
func _dev_tools(parent: VBoxContainer):
    var f := Art.Frame.new("test", int(18 * k))
    f.name = "DevTools"
    parent.add_child(f)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 8)
    f.add_child(v)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    v.add_child(row)
    row.add_child(Art.Glyph.new("hammer", 26, Color("f2a070")))
    var title := Art.label(row, "FERRAMENTAS DE DESENVOLVIMENTO", fs(18), Color("ffd2b0"), Art.FONT_BOLD)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var names := {"nenhum": "nenhum ativo", "fundador": "só Fundador", "club": "só Club", "fundador+club": "Fundador + Club"}
    var st := Art.label(v, "Estado de teste: %s%s.  Só existe no modo de simulação e não aparece na versão comercial." % [names[state.summary()], (" · %d dias de Club (benefício Fundador)" % Catalog.FOUNDER_CLUB_DAYS) if state.founder_trial_view() else ""], fs(15), Color("f0d9c6"))
    st.name = "DevStateLabel"
    var b := Art.Cta.new("RESETAR MONETIZAÇÃO DE TESTE", "ember", 52, 17)
    b.name = "ResetMonetization"
    b.pressed.connect(func():
        open_confirm("RESETAR MONETIZAÇÃO DE TESTE?", "Limpa os estados simulados (Fundador, Club e os 30 dias de Club do Fundador).\nNão mexe em conta, PL, Ranked nem progressão.", "CANCELAR", "RESETAR", func():
            state.mock_reset()
            _rebuild()))
    v.add_child(b)

# ---------------------------------------------------------------- blocos reutilizáveis
func fs(n: int) -> int:
    return maxi(12, int(round(n * k)))

func fair_play_note() -> Control:
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 8)
    row.add_child(Art.Glyph.new("shield", 22, Color("8fe08a")))
    var l := Art.label(row, "FRAIHA não é pay-to-win: nada aqui altera PL, matchmaking, tempo, regras ou resultado.", fs(16), Color("bfe8a8"))
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_SHRINK_CENTER
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    if not narrow: l.autowrap_mode = TextServer.AUTOWRAP_OFF
    return row

## Preço de teste em destaque + selo MODO TESTE + preço planejado.
func price_block(product_id: String, monthly: bool) -> Control:
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 2)
    var row := HFlowContainer.new()
    row.add_theme_constant_override("h_separation", 12)
    row.add_theme_constant_override("v_separation", 4)
    v.add_child(row)
    var price := Art.label(row, Catalog.charge_price(product_id) + (" / MÊS" if monthly else ""), fs(46), Color("fff1c0"), Art.FONT_BOLD)
    price.name = "TestPrice"
    price.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    price.autowrap_mode = TextServer.AUTOWRAP_OFF
    price.add_theme_constant_override("outline_size", 6)
    price.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.0, 0.9))
    row.add_child(Art.Stamp.new("MODO TESTE", "test", 14))
    var planned := "Preço planejado futuramente: %s%s" % [Catalog.planned_price(product_id), " / mês" if monthly else " · pagamento único"]
    var pl := Art.label(v, planned, fs(16), Art.MUTED)
    pl.name = "PlannedPrice"
    return v

func status_badge(text: String) -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.add_child(Art.Glyph.new("check", 26, Color("8fe08a"), false))
    var s := Art.Stamp.new(text, "ok", 14 if not narrow else 12)
    s.name = "StatusBadge"
    row.add_child(s)
    return row

## Seção com título dourado e divisória.
func section(parent: Node, title: String, icon_kind := "star", variant := "dark") -> VBoxContainer:
    var f := Art.Frame.new(variant, int(24 * k))
    f.name = "Section_" + title.validate_node_name().replace(" ", "_")
    parent.add_child(f)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", int(12 * k))
    f.add_child(v)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    v.add_child(row)
    var ink := Art.INK if variant == "parchment" else Art.GOLD
    row.add_child(Art.Glyph.new(icon_kind, 34 * maxf(k, 0.8), ink))
    var l := Art.label(row, title, fs(28), ink, Art.FONT_BOLD)
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return v

func columns_for(desktop: int) -> int:
    if narrow: return 1
    if view.x < 1100.0: return mini(2, desktop)
    return desktop

## Cartão de benefício: ícone, título, descrição e (opcional) selo de estado.
func benefit_card(parent: Node, icon_kind: String, title: String, desc: String, tag := "", tag_tone := "soon", variant := "dark") -> Control:
    var f := Art.Frame.new(variant, int(16 * k))
    f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    f.name = "Benefit_" + title.validate_node_name().replace(" ", "_")
    parent.add_child(f)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    f.add_child(row)
    var ink := Art.INK if variant == "parchment" else Art.GOLD
    var g := Art.Glyph.new(icon_kind, 50 * maxf(k, 0.8), ink, variant != "parchment")
    g.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    row.add_child(g)
    var v := VBoxContainer.new()
    v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    v.add_theme_constant_override("separation", 4)
    row.add_child(v)
    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation", 6)
    v.add_child(head)
    var chk := Art.Glyph.new("check", 18, Color("8fe08a") if variant != "parchment" else Color("2f6b2a"))
    chk.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    chk.custom_minimum_size.y = 24
    head.add_child(chk)
    var t := Art.label(head, title, fs(19), ink, Art.FONT_BOLD)
    t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    Art.label(v, desc, fs(16), Art.INK.lightened(0.15) if variant == "parchment" else Art.MUTED)
    if not tag.is_empty():
        var s := Art.Stamp.new(tag, tag_tone, 12)
        s.name = "Tag"
        v.add_child(s)
    return f

func grid(parent: Node, cols: int) -> GridContainer:
    var g := GridContainer.new()
    g.columns = cols
    g.add_theme_constant_override("h_separation", int(16 * k))
    g.add_theme_constant_override("v_separation", int(14 * k))
    g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(g)
    return g

# ---------------------------------------------------------------- modais
func _modal_host() -> Control:
    close_modal()
    var dim := ColorRect.new()
    dim.name = "ModalDim"
    dim.color = Color(0, 0, 0, 0.72)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    modal_layer.add_child(dim)
    modal = dim
    return dim

func close_modal():
    if modal != null and is_instance_valid(modal):
        modal_layer.remove_child(modal)
        modal.queue_free()
    modal = null

## Fluxo de pagamento simulado (escolha → PIX/Cartão → confirmação).
func open_payment(product_id: String):
    var host := _modal_host()
    var ui := PaymentUI.new()
    host.add_child(ui)
    ui.setup(self, product_id)

## Modal simples de confirmação (2 botões) ou aviso (1 botão quando cancel_text vazio).
func open_confirm(title: String, body: String, cancel_text: String, ok_text: String, on_ok: Callable, tone := "test") -> Control:
    var host := _modal_host()
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    host.add_child(center)
    var f := Art.Frame.new("founder" if tone != "club" else "club", int(26 * k))
    f.name = "ConfirmModal"
    f.custom_minimum_size.x = minf(view.x - 32.0, 760.0)
    center.add_child(f)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 14)
    f.add_child(v)
    v.add_child(Art.Stamp.new("MODO TESTE", "test", 13))
    var tl := Art.label(v, title, fs(30), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    tl.name = "ConfirmTitle"
    var bl := Art.label(v, body, fs(19), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
    bl.name = "ConfirmBody"
    var row: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    row.add_theme_constant_override("separation", 14)
    v.add_child(row)
    if not cancel_text.is_empty():
        var c := Art.Cta.new(cancel_text, "dark", 58, 19)
        c.name = "ConfirmCancel"
        c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        c.pressed.connect(close_modal)
        row.add_child(c)
    var o := Art.Cta.new(ok_text, "gold" if tone != "club" else "green", 58, 19)
    o.name = "ConfirmOk"
    o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    o.pressed.connect(func():
        close_modal()
        if on_ok.is_valid(): on_ok.call())
    row.add_child(o)
    return f

## Pagamento simulado concluído: ativa o estado mock e celebra.
func complete_mock(product_id: String, method: String):
    var result: Dictionary = gateway.complete(product_id, method)
    close_modal()
    _rebuild()
    scroll.scroll_vertical = 0
    if result.get("ok", false): _celebrate()

func _celebrate():
    var burst := Art.Sparkles.new(90, Color("ffe08a"))
    burst.name = "Celebrate"
    root.add_child(burst)
    var tw := root.create_tween()
    tw.tween_interval(2.4)
    tw.tween_callback(func(): if is_instance_valid(burst): burst.queue_free())

## WhatsApp dos Fundadores: abre FOUNDER_WHATSAPP_URL; vazio → aviso (nunca inventa link).
func open_founder_group():
    var url := String(Catalog.FOUNDER_WHATSAPP_URL).strip_edges()
    if url.begins_with("https://"):
        OS.shell_open(url)
        return
    open_confirm("COMUNIDADE DOS FUNDADORES", "Grupo dos Fundadores ainda não configurado.\n\nSeu acesso já está garantido e o link será disponibilizado aqui.", "", "ENTENDI", Callable())
