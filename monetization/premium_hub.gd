extends CanvasLayer
## FRAIHA PREMIUM — sobreposição aberta a partir de CONFIGURAÇÕES.
## Navegação: Produto (Fundador/Club) → Hub Premium → Configurações.
## R39: build publicada = pagamento REAL (Mercado Pago, PIX + cartão, pelo servidor); editor/testes = simulação.
signal closed

const Art := preload("res://monetization/premium_art.gd")
const Catalog := preload("res://monetization/monetization_catalog.gd")
const StateScript := preload("res://monetization/monetization_state.gd")
const Gateway := preload("res://monetization/payment_gateway.gd")
const FounderUI := preload("res://monetization/founder_ui.gd")
const ClubUI := preload("res://monetization/club_ui.gd")
const PaymentUI := preload("res://monetization/payment_mock_ui.gd")
const PaymentRealUI := preload("res://monetization/payment_real_ui.gd")
const PersonalizeUI := preload("res://monetization/personalize_ui.gd")
const MyClubUI := preload("res://monetization/my_club_ui.gd")
const PurchasesUI := preload("res://monetization/purchases_ui.gd")
const PreviewBoard := preload("res://monetization/preview_board.gd")
const FoundersHallUI := preload("res://monetization/founders_hall_ui.gd")
const Mobile := preload("res://ui_v022/mobile_layout.gd")
const Showcase := preload("res://monetization/showcase.gd")

var state
var gateway
var page := "hub"
var entry_page := "hub"   # página por onde o jogador entrou (VOLTAR nela fecha, se veio do Perfil/Club)
var url_opener: Callable   # testes: substitui OS.shell_open
var last_opened_url := ""
var main_hub = null       # ui_v022/main_hub.gd (direitos reais, identidade, histórico do Club)
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
var purchases: Array = []     # R107 · MINHAS COMPRAS (payment_history)
var purchases_loaded := false
var founders: Array = []      # R109 · SALÃO DOS FUNDADORES (payment_founders)
var founders_loaded := false
var offer := {}          # R39 · resposta do servidor (payment_offer): vagas de Fundador, provedor pronto
var _offer_bound = null

func _init(monetization_state = null):
    layer = 60
    preload("res://ui_v022/esc_stack.gd").register(self)   # R129 · ESC em tudo (fecha só a janela de cima)
    name = "PremiumHub"
    state = monetization_state if monetization_state != null else StateScript.new()
    gateway = Gateway.new(state)

func _ready():
    _build()
    get_viewport().size_changed.connect(_relayout)
    visible = false

# ---------------------------------------------------------------- navegação
func open(page_id := "hub"):
    entry_page = page_id
    visible = true
    root.visible = true
    _request_offer()
    show_page(page_id)

## R39 · pagamento real: o servidor diz se o Mercado Pago está ligado e quantas vagas de Fundador restam.
func _account():
    return main_hub.account if main_hub != null else null

func _request_offer():
    var acc = _account()
    if acc == null: return
    if _offer_bound != acc and acc.has_signal("server_message"):
        acc.server_message.connect(_on_server)
        _offer_bound = acc
        # direitos mudaram (pagamento confirmado, vencimento, outra aba): a página atrás do modal acompanha
        if main_hub.entitlements != null: main_hub.entitlements.changed.connect(func(): if visible: _rebuild())
    if Catalog.is_mock(): return   # R109 · no modo de simulação só escuta (compras / Salão), sem pedir oferta
    if acc.has_method("has_profile") and acc.has_profile(): acc.send_server({"type": "payment_offer"})

func _on_server(msg: Dictionary):
    if String(msg.get("type", "")) == "payment_founders":   # R109
        founders = msg.get("founders", []) if msg.get("founders") is Array else []
        founders_loaded = true
        if visible and modal == null and page == "salao": _rebuild()
        return
    if String(msg.get("type", "")) == "payment_history":   # R107
        purchases = msg.get("items", []) if msg.get("items") is Array else []
        purchases_loaded = true
        if visible and modal == null and page == "purchases": _rebuild()
        return
    if String(msg.get("type", "")) != "payment_offer": return
    offer = msg
    if visible and modal == null and page in ["hub", "founder", "club"]: _rebuild()


## R109 · pede ao servidor a lista pública dos Fundadores.
func _request_founders():
    founders_loaded = false
    var acc = _account()
    if acc == null: return
    _request_offer()
    if acc.has_method("send_server") and not acc.send_server({"type": "payment_founders"}):
        founders_loaded = true

## R107 · pede ao servidor o histórico de compras da conta.
func _request_purchases():
    purchases_loaded = Catalog.is_mock()
    var acc = _account()
    if acc == null or not acc.has_method("has_profile") or not acc.has_profile(): return
    _request_offer()   # liga o _on_server (uma vez) e atualiza a oferta
    acc.send_server({"type": "payment_history"})

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
    elif page == entry_page and page in ["personalize", "myclub", "purchases"]:
        close()
    elif page != "hub":
        show_page("hub")
    else:
        close()

func show_page(id: String):
    close_modal()
    page = id
    if id == "purchases": _request_purchases()
    if id == "salao": _request_founders()
    _rebuild()
    scroll.scroll_vertical = 0

func esc_open() -> bool:
    return visible

func esc_close():
    back()

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
    var hs = root.find_child("HeaderTestStamp", true, false)
    if hs != null:   # R123 · celular: selo curto, sobra espaço para o título
        hs.text = "TESTE" if narrow else "MODO TESTE"
        hs.font_size = 12 if narrow else 15
        hs._measure()
        hs.queue_redraw()
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
    stamp.visible = Catalog.is_mock()
    banner.visible = Catalog.is_mock()
    stamp.font_size = 12 if narrow or compact else 15
    stamp._measure()
    var bl: Label = banner.find_child("TestBannerText", true, false)
    bl.add_theme_font_size_override("font_size", 12 if narrow or compact else 15)
    bl.text = "SIMULAÇÃO · R$ 0,00 de teste · nenhum pagamento é processado" if narrow or compact else "SIMULAÇÃO DE DESENVOLVIMENTO  ·  preços de teste R$ 0,00  ·  nenhum pagamento é processado e nenhum dado financeiro é pedido"
    if visible: _rebuild()
    backdrop.queue_redraw()

## R111 · fundo no estilo do jogo: o salão do produto (trono do Fundador / biblioteca do Club), escurecido,
## com vinheta e luz dourada — no lugar do verde chapado.
const BG_FOUNDER := preload("res://cosmetics/v031/fundador_arena.png")
const BG_CLUB := preload("res://cosmetics/v031/club_arena.png")
func _draw_backdrop():
    var s := backdrop.size
    backdrop.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.015, 0.01, 1.0))
    var tex: Texture2D = BG_CLUB if page in ["club", "myclub"] else BG_FOUNDER
    var ts := tex.get_size()
    var sc := maxf(s.x / ts.x, s.y / ts.y)
    var vis := s / sc
    backdrop.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, s), Rect2((ts - vis) * 0.5, vis), Color(0.42, 0.40, 0.38, 1.0))
    # escurece para o conteúdo ler bem e puxa a luz para o alto
    backdrop.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.012, 0.005, 0.55))
    for i in 12:
        var a := 0.05 * (1.0 - i / 12.0)
        backdrop.draw_rect(Rect2(0, 0, s.x * 0.06 * (12 - i) / 12.0, s.y), Color(0, 0, 0, a * 3.0))
        backdrop.draw_rect(Rect2(s.x - s.x * 0.06 * (12 - i) / 12.0, 0, s.x * 0.06 * (12 - i) / 12.0, s.y), Color(0, 0, 0, a * 3.0))
    for i in 10:
        backdrop.draw_circle(Vector2(s.x * 0.5, -s.y * 0.2), s.x * (0.22 + i * 0.06), Color(1.0, 0.78, 0.35, 0.025 * (1.0 - i / 10.0)))
    backdrop.draw_line(Vector2(0, 2), Vector2(s.x, 2), Color(0.85, 0.65, 0.25, 0.6), 2.0)
    backdrop.draw_line(Vector2(0, s.y - 2), Vector2(s.x, s.y - 2), Color(0.85, 0.65, 0.25, 0.6), 2.0)

func _set_crumbs():
    for c in crumbs.get_children():
        crumbs.remove_child(c)
        c.queue_free()
    var parts := ["FRAIHA PREMIUM"]
    if page == "founder": parts.append("PACOTE FUNDADOR")
    elif page == "club": parts.append("CLUB FRAIHA")
    elif page == "personalize": parts.append("PERSONALIZAÇÃO")
    elif page == "myclub": parts.append("MEU CLUB")
    elif page == "purchases": parts.append("MINHAS COMPRAS")
    elif page == "salao": parts.append("SALÃO DOS FUNDADORES")
    if narrow: parts = [{"hub": "PREMIUM", "founder": "FUNDADOR", "club": "CLUB", "personalize": "PERSONALIZAR", "myclub": "MEU CLUB", "purchases": "COMPRAS", "salao": "SALÃO"}.get(page, "PREMIUM")]
    for i in parts.size():
        if i > 0: crumbs.add_child(Art.Glyph.new("star", 12, Color(0.79, 0.6, 0.27, 0.8)))
        var last := i == parts.size() - 1
        var l := Art.label(crumbs, parts[i], fs((15 if narrow else 20) if last else 15), Art.GOLD if last else Art.MUTED, Art.FONT_BOLD if last else Art.FONT_SEMI)   # R123 · celular: título inteiro (era "PREMII")
        l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
        l.autowrap_mode = TextServer.AUTOWRAP_OFF
        l.clip_text = narrow
        if narrow: l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    back_button.text = "VOLTAR" if narrow or page == "hub" else "FRAIHA PREMIUM"
    back_button.icon_kind = ""
    back_button.queue_redraw()

func _rebuild():
    if column == null: return
    if backdrop != null: backdrop.queue_redraw()
    _set_crumbs()
    for c in column.get_children():
        column.remove_child(c)
        c.queue_free()
    match page:
        "founder": FounderUI.build(self, column)
        "club": ClubUI.build(self, column)
        "personalize": PersonalizeUI.build(self, column)
        "myclub": MyClubUI.build(self, column)
        "purchases": PurchasesUI.build(self, column)
        "salao": FoundersHallUI.build(self, column)
        _: _build_hub(column)
    if Catalog.dev_tools_enabled(): _dev_tools(column)
    var tail := Control.new()
    tail.custom_minimum_size.y = 40 if narrow else 24
    column.add_child(tail)

# ---------------------------------------------------------------- hub (R103 · vitrine)
func _build_hub(parent: VBoxContainer):
    parent.add_child(founder_showcase())
    parent.add_child(founder_plans())
    parent.add_child(club_showcase())
    parent.add_child(club_plans())
    parent.add_child(fair_play_note())
    # R31: atalhos para o que o jogador já tem
    var quick: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    quick.add_theme_constant_override("separation", 16)
    parent.add_child(quick)
    var pz := Art.Cta.new("PERSONALIZAÇÃO", "gold", 58 * maxf(k, 0.85), int(20 * maxf(k, 0.85)))
    pz.name = "OpenPersonalize"
    pz.icon_kind = "brush"
    pz.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pz.pressed.connect(func(): show_page("personalize"))
    quick.add_child(pz)
    var mc := Art.Cta.new("MEU CLUB · DESEMPENHO", "green", 58 * maxf(k, 0.85), int(20 * maxf(k, 0.85)))
    mc.name = "OpenMyClub"
    mc.icon_kind = "chart"
    mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mc.pressed.connect(func(): show_page("myclub"))
    quick.add_child(mc)
    var mp := Art.Cta.new("MINHAS COMPRAS", "dark", 58 * maxf(k, 0.85), int(20 * maxf(k, 0.85)))
    mp.name = "OpenPurchases"
    mp.icon_kind = "scroll"
    mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mp.pressed.connect(func(): show_page("purchases"))
    quick.add_child(mp)

func _showcase(kind: String) -> Control:
    var sc = Showcase.new(kind)
    sc.pieces_right = not narrow
    sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sc.custom_minimum_size.y = (580.0 if narrow else 380.0) * maxf(k, 0.8) if not compact else 260.0
    sc.overlay.add_theme_constant_override("separation", int(8 * k))
    return sc

## Título da vitrine numa linha só (encolhe no celular).
func _title_px(text: String) -> int:
    var w := column.custom_minimum_size.x * (0.9 if narrow else 0.5) - 12.0
    return Art.fit(Art.FONT_BOLD, text, fs(54), w, 22)

func _shadow(l: Label, size := 6):
    l.add_theme_constant_override("outline_size", size)
    l.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.02, 0.95))

## Vitrine do Fundador: salão do trono + peças douradas, prazo da oferta e título.
func founder_showcase() -> Control:
    var sc := _showcase("founder")
    sc.name = "FounderShowcase"
    var v: VBoxContainer = sc.overlay
    var chips := HFlowContainer.new()
    chips.add_theme_constant_override("h_separation", 8)
    chips.add_theme_constant_override("v_separation", 6)
    v.add_child(chips)
    chips.add_child(Art.Stamp.new("EDIÇÃO DE LANÇAMENTO", "new", int(14 * maxf(k, 0.9))))
    var limit := founder_deadline_text()
    if not limit.is_empty():
        var st := Art.Stamp.new(limit, "test" if not founder_open() else "info", int(14 * maxf(k, 0.9)))
        st.name = "FounderDeadline"
        chips.add_child(st)
    var t := Art.label(v, "PACOTE FUNDADOR", _title_px("PACOTE FUNDADOR"), Art.GOLD, Art.FONT_BOLD)
    _shadow(t, 9)
    var sub := Art.label(v, "Entre para a história do FRAIHA. Selo, título, tabuleiro e peças exclusivos, para sempre na sua conta.", fs(21), Art.CREAM)
    _shadow(sub, 5)
    if founder_owned():
        var n := founder_number()
        var who := ("FUNDADOR LENDÁRIO" if legend_owned() else "FUNDADOR DO REINO") + (" #%d" % n if n > 0 else "")
        v.add_child(status_badge(who + ("" if founder_real() else " (TESTE)")))
    var more := Art.Cta.new("VER TODOS OS BENEFÍCIOS", "dark", 50 * maxf(k, 0.85), int(17 * maxf(k, 0.85)))
    more.name = "OpenFounder"
    more.icon_kind = ""
    more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    more.custom_minimum_size.x = 300 * maxf(k, 0.8)
    more.pressed.connect(func(): show_page("founder"))
    var row := _with_try(more, "fundador")
    var hall := Art.Cta.new("SALÃO DOS FUNDADORES", "dark", 50 * maxf(k, 0.85), int(17 * maxf(k, 0.85)))
    hall.name = "OpenFoundersHall"
    hall.icon_kind = ""
    hall.custom_minimum_size.x = 280 * maxf(k, 0.8)
    hall.pressed.connect(func(): show_page("salao"))
    row.add_child(hall)
    v.add_child(row)
    return sc

func club_showcase() -> Control:
    var sc := _showcase("club")
    sc.name = "ClubShowcase"
    var v: VBoxContainer = sc.overlay
    var chips := HFlowContainer.new()
    chips.add_theme_constant_override("h_separation", 8)
    chips.add_theme_constant_override("v_separation", 6)
    v.add_child(chips)
    chips.add_child(Art.Stamp.new("SEM RENOVAÇÃO AUTOMÁTICA", "info", int(14 * maxf(k, 0.9))))
    var t := Art.label(v, "CLUB FRAIHA", _title_px("CLUB FRAIHA"), Art.GOLD, Art.FONT_BOLD)
    _shadow(t, 9)
    var tag := Art.label(v, "JOGUE.  ENTENDA.  EVOLUA.", fs(24), Art.acc_text(), Art.FONT_BOLD)
    _shadow(tag, 5)
    var sub := Art.label(v, "Análise ilimitada das suas partidas, treino dos seus erros e evolução acompanhada.", fs(20), Art.CREAM)
    _shadow(sub, 5)
    if club_real():
        var left: int = main_hub.entitlements.club_days_left() if main_hub != null else -1
        v.add_child(status_badge("CLUB ATIVO" + (" · FALTAM %d DIAS" % left if left > 1 else "")))
    elif state.club_subscription_view():
        v.add_child(status_badge("CLUB FRAIHA ATIVO (TESTE)"))
    var more := Art.Cta.new("VER TODOS OS BENEFÍCIOS", "dark", 50 * maxf(k, 0.85), int(17 * maxf(k, 0.85)))
    more.name = "OpenClub"
    more.icon_kind = ""
    more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    more.custom_minimum_size.x = 300 * maxf(k, 0.8)
    more.pressed.connect(func(): show_page("club"))
    v.add_child(_with_try(more, "club"))
    return sc

## R108 · linha com "VER TODOS OS BENEFÍCIOS" + "EXPERIMENTAR" (prévia do tabuleiro do universo).
func _with_try(more: Control, theme_id: String) -> Control:
    var row := HFlowContainer.new()
    row.add_theme_constant_override("h_separation", 10)
    row.add_theme_constant_override("v_separation", 8)
    row.add_child(more)
    var tr := Art.Cta.new("EXPERIMENTAR", "gold" if theme_id == "fundador" else "green", 50 * maxf(k, 0.85), int(17 * maxf(k, 0.85)))
    tr.name = "Try_" + theme_id
    tr.icon_kind = ""
    tr.custom_minimum_size.x = 220 * maxf(k, 0.8)
    tr.pressed.connect(func(): open_preview(theme_id))
    row.add_child(tr)
    return row

## R108 · prévia do universo: o tabuleiro com as peças do conjunto sobre a arena.
func open_preview(theme_id: String):
    var host := _modal_host()
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    host.add_child(center)
    var f := Art.Frame.new("founder" if theme_id == "fundador" else "club", int(18 * k))
    f.name = "PreviewModal"
    center.add_child(f)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    f.add_child(v)
    var title := "TABULEIRO E PEÇAS DO FUNDADOR" if theme_id == "fundador" else "TABULEIRO E PEÇAS DO CLUB"   # R139
    var tl := Art.label(v, title, fs(30), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    tl.name = "PreviewTitle"
    var w := minf(view.x - (70.0 if narrow else 60.0), 1000.0)
    var h := minf(view.y - (230.0 if not narrow else 260.0), w * (0.62 if not narrow else 1.05))
    # R139 · padrão único: o tabuleiro da Madeira com as cores exclusivas (no lugar do antigo universo)
    var board = preload("res://cosmetics/board_colors_preview.gd").new(theme_id, theme_id)
    board.name = "PreviewBoard"
    board.custom_minimum_size = Vector2(w, h)
    v.add_child(board)
    var d := Art.label(v, ("Tabuleiro e peças em dourado e ébano: são seus para sempre, junto com selo, título e moldura." if theme_id == "fundador" else "Tabuleiro e peças em esmeralda: liberados enquanto o Club estiver ativo."), fs(16), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
    d.custom_minimum_size.x = w
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 12)
    v.add_child(row)
    var close := Art.Cta.new("FECHAR", "dark", 52, 15 if narrow else 17)
    close.name = "PreviewClose"
    close.icon_kind = ""
    close.custom_minimum_size.x = 120 if narrow else 180
    close.pressed.connect(close_modal)
    row.add_child(close)
    var go := Art.Cta.new("QUERO ESTE", "gold" if theme_id == "fundador" else "green", 52, 15 if narrow else 17)
    go.name = "PreviewGo"
    go.icon_kind = ""
    go.custom_minimum_size.x = 150 if narrow else 200
    go.pressed.connect(func():
        close_modal()
        show_page("founder" if theme_id == "fundador" else "club"))
    row.add_child(go)

## Cartões dos dois pacotes de Fundador lado a lado (um embaixo do outro no celular).
func founder_plans() -> Control:
    var row: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    row.name = "FounderPlans"
    row.add_theme_constant_override("separation", 18)
    var closed := not founder_open()
    var owned := founder_owned()
    var legend := legend_owned()
    var c1 := ""
    if legend or owned: c1 = "VOCÊ JÁ É FUNDADOR"
    elif closed: c1 = "OFERTA ENCERRADA"
    else: c1 = "QUERO SER FUNDADOR"
    row.add_child(plan_card("founder", "founder", "FUNDADOR", "", [
        "Selo, título e moldura de Fundador",
        "5 avatares exclusivos de Fundador",
        "Tabuleiro e peças exclusivos do Fundador",
        "%d dias de Club FRAIHA inclusos" % Catalog.FOUNDER_CLUB_DAYS,
        "Grupo dos Fundadores no WhatsApp",
        "Seu número e nome no Salão dos Fundadores",
    ], c1, closed or owned, "gold"))
    var c2 := ""
    if legend: c2 = "VOCÊ JÁ É LENDÁRIO"
    elif closed: c2 = "OFERTA ENCERRADA"
    else: c2 = "QUERO SER LENDÁRIO"
    row.add_child(plan_card("founder_legend", "reward", "FUNDADOR LENDÁRIO", "MAIS COMPLETO", [
        "Tudo do Pacote Fundador",
        "1 ANO de Club FRAIHA incluso",
        "Título exclusivo \"Fundador Lendário\"",
        "Avatar \"Lenda Mística\", só do Lendário",
        "Apoio máximo ao FRAIHA no lançamento",
    ], c2, closed or legend, "gold"))
    return row

func club_plans() -> Control:
    var row: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
    row.name = "ClubPlans"
    row.add_theme_constant_override("separation", 18)
    var active := club_owned()
    row.add_child(plan_card("club_monthly", "club", "CLUB · 30 DIAS", "", [
        "Todos os recursos do Club por 30 dias",
        "Sem renovação automática",
        "Renovar soma +30 dias ao que resta",
    ], "RENOVAR · +30 DIAS" if active else "ATIVAR 30 DIAS", false, "green"))
    var pm := int(Catalog.product("club_monthly").get("pix_price_cents", 0)) * 12
    var py := int(Catalog.product("club_yearly").get("pix_price_cents", 0))
    var save := int(round(100.0 * (pm - py) / maxf(1.0, pm)))
    row.add_child(plan_card("club_yearly", "club", "CLUB · 1 ANO", "ECONOMIZE %d%%" % save, [
        "Todos os recursos do Club por 365 dias",
        "Sai por %s por mês no PIX" % Catalog.monthly_equiv("club_yearly"),
        "Sem renovação automática",
    ], "RENOVAR · +1 ANO" if active else "ATIVAR 1 ANO", false, "green"))
    return row

## Cartão de plano: selo opcional, nome, preço (PIX em destaque + cartão), lista e botão de compra.
func plan_card(product_id: String, variant: String, title: String, ribbon: String, lines: Array, cta_text: String, cta_off: bool, cta_tone: String) -> Control:
    var f := Art.Frame.new(variant, int(22 * k))
    f.name = "Plan_" + product_id
    f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    f.glow = not ribbon.is_empty()
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", int(8 * k))
    f.add_child(v)
    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation", 10)
    v.add_child(head)
    var tl := Art.label(head, title, fs(30), Art.GOLD, Art.FONT_BOLD)
    tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if not ribbon.is_empty():
        var rb := Art.Stamp.new(ribbon, "new", int(13 * maxf(k, 0.9)))
        rb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        head.add_child(rb)
    v.add_child(price_block(product_id, false))
    for line in lines:
        var r := HBoxContainer.new()
        r.add_theme_constant_override("separation", 8)
        v.add_child(r)
        var g := Art.Glyph.new("check", 22 * maxf(k, 0.85), Art.CHECK, false)
        g.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
        r.add_child(g)
        var l := Art.label(r, line, fs(18), Art.CREAM)
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    v.add_child(spacer)
    var cta := Art.Cta.new(cta_text, "dark" if cta_off else cta_tone, 64 * maxf(k, 0.85), int(21 * maxf(k, 0.85)))
    var names := {"founder": "BecomeFounder", "founder_legend": "BecomeLegend", "club_monthly": "SubscribeClub", "club_yearly": "SubscribeClubYearly"}
    cta.name = String(names.get(product_id, "Buy_" + product_id)) + ("Off" if cta_off else "")
    cta.icon_kind = ""
    cta.disabled = cta_off
    cta.shimmer = not cta_off and not ribbon.is_empty()
    if not cta_off: cta.pressed.connect(func(): open_payment(product_id))
    v.add_child(cta)
    return f

## Prazo da oferta de Fundador ("POR TEMPO LIMITADO · ATÉ 14/12").
func founder_deadline_text() -> String:
    if not founder_open(): return "OFERTA ENCERRADA"
    var d := Catalog.short_date(String(offer.get("founder_until", "") if offer.get("founder_until") != null else ""))
    return "POR TEMPO LIMITADO" + (" · ATÉ %s" % d if not d.is_empty() else "")

# ---------------------------------------------------------------- direitos (servidor OU simulação)
func founder_owned() -> bool:
    if main_hub != null: return main_hub.is_founder()
    return state.founder_view()

func club_owned() -> bool:
    if main_hub != null: return main_hub.club_active()
    return state.club_subscription_view() or state.founder_trial_view()

## R103 · a oferta de Fundador está aberta? (o servidor decide pelo prazo; sem resposta = aberta)
func founder_open() -> bool:
    if Catalog.is_mock(): return true
    return bool(offer.get("founder_open", true))

func founder_number() -> int:
    if main_hub != null and main_hub.entitlements != null:
        var n := int(main_hub.entitlements.real.get("founder_number", 0))
        if n > 0: return n
    return int(offer.get("founder_number", 0)) if offer.get("founder_number") != null else 0

func legend_owned() -> bool:
    if main_hub != null and main_hub.entitlements != null and String(main_hub.entitlements.real.get("founder_tier", "")) == "legend": return true
    return String(offer.get("founder_tier", "") if offer.get("founder_tier") != null else "") == "legend"

## Direito confirmado pelo SERVIDOR (não simulação).
func founder_real() -> bool:
    return main_hub != null and main_hub.entitlements != null and bool(main_hub.entitlements.real.is_founder)

func club_real() -> bool:
    return main_hub != null and main_hub.entitlements != null and bool(main_hub.entitlements.real.club_active)

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
    row.add_child(Art.Glyph.new("shield", 22, Art.CHECK))
    var l := Art.label(row, "FRAIHA não é pay-to-win: nada aqui altera PL, matchmaking, tempo, regras ou resultado.", fs(16), Art.acc_text())
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_SHRINK_CENTER
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    if not narrow: l.autowrap_mode = TextServer.AUTOWRAP_OFF
    return row

## R103 · Preço: PIX (com desconto) em destaque e o valor no cartão embaixo. No modo de teste: R$ 0,00 + selo.
func price_block(product_id: String, monthly: bool) -> Control:
    var v := VBoxContainer.new()
    v.name = "PriceBlock"
    v.add_theme_constant_override("separation", 0)
    var row := HFlowContainer.new()
    row.add_theme_constant_override("h_separation", 10)
    row.add_theme_constant_override("v_separation", 2)
    v.add_child(row)
    var days := Catalog.club_days(product_id)
    var price := Art.label(row, Catalog.charge_price(product_id) if Catalog.is_mock() else Catalog.pix_price(product_id), fs(46), Color("fff1c0"), Art.FONT_BOLD)
    price.name = "TestPrice"
    price.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    price.autowrap_mode = TextServer.AUTOWRAP_OFF
    price.add_theme_constant_override("outline_size", 6)
    price.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.0, 0.9))
    if Catalog.is_mock():
        row.add_child(Art.Stamp.new("MODO TESTE", "test", 14))
        var planned := "Preço comercial: %s no PIX · %s no cartão" % [Catalog.pix_price(product_id), Catalog.planned_price(product_id)]
        var pl := Art.label(v, planned, fs(16), Art.MUTED)
        pl.name = "PlannedPrice"
    else:
        var pix := Art.Stamp.new("NO PIX · %d%% OFF" % Catalog.PIX_DISCOUNT_PCT, "ok", int(13 * maxf(k, 0.9)))
        pix.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(pix)
        var when := "pagamento único" if Catalog.product(product_id).get("kind", "") == "one_time" else ("%d dias, sem renovação automática" % days if days < 365 else "1 ano, sem renovação automática")
        var how := Art.label(v, "ou %s no cartão · %s" % [Catalog.planned_price(product_id), when], fs(16), Art.MUTED)
        how.name = "PriceHow"
    return v

func status_badge(text: String) -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.add_child(Art.Glyph.new("check", 26, Art.CHECK, false))
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
    var chk := Art.Glyph.new("check", 18, Art.CHECK if variant != "parchment" else Color("355087"))
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

## Pagamento: real (Mercado Pago pelo servidor) na build publicada; simulado no editor/testes.
func open_payment(product_id: String):
    var host := _modal_host()
    var ui = PaymentUI.new() if Catalog.is_mock() else PaymentRealUI.new()
    host.add_child(ui)
    ui.setup(self, product_id)

## R39 · pagamento confirmado pelo SERVIDOR (webhook → acct_state): festa + boas-vindas com o que foi liberado.
func payment_confirmed(product_id: String):
    _request_offer()
    purchases_loaded = false
    _rebuild()
    scroll.scroll_vertical = 0
    _celebrate()
    var founder := product_id in ["founder", "founder_legend"]
    var legend := product_id == "founder_legend"
    var num := founder_number()
    var title := ("BEM-VINDO, FUNDADOR LENDÁRIO!" if legend else "BEM-VINDO, FUNDADOR DO REINO!") if founder else "CLUB FRAIHA ATIVO!"
    var lines := []
    if founder:
        if num > 0: lines.append("Você é o Fundador #%d do FRAIHA" % num)
        lines += ["Selo e título \"%s\"" % ("Fundador Lendário" if legend else "Fundador do Reino"), "Avatares e moldura exclusivos de Fundador", "Tabuleiro e peças do Fundador",
            ("1 ano" if legend else "%d dias" % Catalog.FOUNDER_CLUB_DAYS) + " de Club FRAIHA inclusos", "Grupo dos Fundadores no WhatsApp"]
    else:
        lines = ["Análises ilimitadas", "MEU CLUB: estatísticas, treino dos seus erros e desafios", "Selo, avatares, moldura, tabuleiro e peças do Club"]
    var body := "Pagamento confirmado pelo Mercado Pago. Já está liberado na sua conta:\n\n• " + "\n• ".join(lines)
    if main_hub != null and main_hub.entitlements != null:
        var exp := String(main_hub.entitlements.club_expires_at())
        if not exp.is_empty(): body += "\n\nClub válido até %s/%s/%s." % [exp.substr(8, 2), exp.substr(5, 2), exp.substr(0, 4)]
    var f := open_confirm(title, body, "FECHAR", "PERSONALIZAR AGORA", func(): show_page("personalize"), "founder" if founder else "club")
    f.name = "WelcomeModal"

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
    if Catalog.is_mock(): v.add_child(Art.Stamp.new("MODO TESTE", "test", 13))
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

## WhatsApp dos Fundadores: o link vem do SERVIDOR só para Fundador de verdade; sem link → aviso.
func open_founder_group():
    var url := ""
    if main_hub != null and main_hub.entitlements != null: url = String(main_hub.entitlements.founder_group_url()).strip_edges()
    if url.begins_with("https://"):
        last_opened_url = url
        if url_opener.is_valid(): url_opener.call(url)
        else: OS.shell_open(url)
        return
    open_confirm("COMUNIDADE DOS FUNDADORES", "Grupo dos Fundadores ainda não configurado.\n\nSeu acesso já está garantido e o link será disponibilizado aqui.", "", "ENTENDI", Callable())
