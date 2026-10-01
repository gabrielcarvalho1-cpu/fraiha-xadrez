extends CenterContainer
## Pagamento SIMULADO (Monetização V1): escolha PIX/Cartão → tela do método → confirmação.
## Não gera QR Code nem PIX Copia e Cola reais; não pede nem coleta dado de cartão/CPF.
## A área do PIX já tem o lugar do QR, do Copia e Cola e do status para a V2.
const Art := preload("res://monetization/premium_art.gd")
const Catalog := preload("res://monetization/monetization_catalog.gd")

var hub
var product_id := ""
var step := "choose"
var panel: Control

func setup(owner_hub, product: String):
    hub = owner_hub
    product_id = product
    name = "PaymentMock"
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _show("choose")

func _club() -> bool:
    return product_id.begins_with("club")

func _show(id: String):
    step = id
    if panel != null:
        remove_child(panel)
        panel.queue_free()
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    var w := minf(hub.view.x - 24.0, 860.0)
    scroll.custom_minimum_size = Vector2(w, minf(hub.view.y - 24.0, 400.0))
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    add_child(scroll)
    panel = scroll
    var f := Art.Frame.new("club" if _club() else "founder", int(24 * hub.k))
    f.name = "PaymentPanel"
    f.custom_minimum_size.x = w - 14.0
    scroll.add_child(f)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", int(14 * hub.k))
    f.add_child(v)
    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation", 10)
    v.add_child(head)
    head.add_child(Art.Stamp.new("MODO TESTE", "test", 13))
    var pname := Art.label(head, String(Catalog.product(product_id).get("name", "")), hub.fs(16), Art.MUTED, Art.FONT_SEMI)
    pname.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    match id:
        "pix": _pix(v)
        "card": _card(v)
        _: _choose(v)
    _fit_height.call_deferred(scroll, f)

## Altura do painel = conteúdo (centralizado), limitada à tela (rola se faltar espaço).
func _fit_height(scroll: ScrollContainer, f: Control):
    if not is_instance_valid(scroll): return
    scroll.custom_minimum_size.y = minf(f.get_combined_minimum_size().y + 4.0, hub.view.y - 24.0)

func _price_text() -> String:
    return Catalog.charge_price(product_id) + (" / MÊS" if _club() else "") + " · MODO TESTE"

# ------------------------------------------------------------ 1. escolha
func _choose(v: VBoxContainer):
    Art.label(v, "ESCOLHA A FORMA DE PAGAMENTO", hub.fs(30), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    Art.label(v, "Simulação: nenhum pagamento será processado.", hub.fs(17), Color("f2a070"), null, HORIZONTAL_ALIGNMENT_CENTER)
    for m in Catalog.enabled_methods():
        if m == "pix": v.add_child(_pix_option())
        elif m == "card": v.add_child(_card_option())
    var cancel := Art.Cta.new("CANCELAR", "dark", 54, 18)
    cancel.name = "PaymentCancel"
    cancel.pressed.connect(hub.close_modal)
    v.add_child(cancel)

func _pix_option() -> Control:
    var f := Art.Frame.new("reward", int(20 * hub.k))
    f.name = "OptionPix"
    f.glow = true
    var row: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    f.add_child(row)
    var g := Art.Glyph.new("pix", 78 * maxf(hub.k, 0.8), Color("7fe0c8"), true)
    g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    row.add_child(g)
    var col := VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.add_theme_constant_override("separation", 6)
    row.add_child(col)
    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 10)
    col.add_child(top)
    var t := Art.label(top, "PIX", hub.fs(34), Art.GOLD, Art.FONT_BOLD)
    t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    t.autowrap_mode = TextServer.AUTOWRAP_OFF
    var rec := Art.Stamp.new("RECOMENDADO", "new", 14)
    rec.name = "PixRecommended"
    top.add_child(rec)
    Art.label(col, _price_text(), hub.fs(19), Color("fff1c0"), Art.FONT_SEMI)
    Art.label(col, "Rápido  ·  Simples  ·  Confirmação imediata (futuramente)", hub.fs(16), Art.MUTED)
    var b := Art.Cta.new("PAGAR COM PIX", "gold", 62 * maxf(hub.k, 0.85), 21)
    b.name = "ChoosePix"
    b.icon_kind = "pix"
    b.shimmer = true
    b.pressed.connect(func(): _show("pix"))
    col.add_child(b)
    return f

func _card_option() -> Control:
    var f := Art.Frame.new("dark", int(16 * hub.k))
    f.name = "OptionCard"
    var row: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    row.add_theme_constant_override("separation", 14)
    f.add_child(row)
    row.add_child(Art.Glyph.new("card", 48, Art.GOLD_MID, true))
    var col := VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(col)
    Art.label(col, "CARTÃO", hub.fs(24), Art.GOLD, Art.FONT_BOLD)
    Art.label(col, _price_text(), hub.fs(16), Art.CREAM)
    var b := Art.Cta.new("CARTÃO", "dark", 52, 18)
    b.name = "ChooseCard"
    b.custom_minimum_size.x = 0 if hub.narrow else 220
    b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    b.pressed.connect(func(): _show("card"))
    row.add_child(b)
    return f

# ------------------------------------------------------------ 2a. PIX (simulado)
func _pix(v: VBoxContainer):
    var top := HBoxContainer.new()
    top.alignment = BoxContainer.ALIGNMENT_CENTER
    top.add_theme_constant_override("separation", 12)
    v.add_child(top)
    top.add_child(Art.Glyph.new("pix", 46, Color("7fe0c8")))
    var t := Art.label(top, "PIX · MODO TESTE", hub.fs(30), Art.GOLD, Art.FONT_BOLD)
    t.name = "PixTitle"
    t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    t.autowrap_mode = TextServer.AUTOWRAP_OFF
    Art.label(v, _price_text(), hub.fs(20), Color("fff1c0"), Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
    var notice := Art.label(v, "Nenhum pagamento será realizado nesta simulação.", hub.fs(18), Color("f2a070"), null, HORIZONTAL_ALIGNMENT_CENTER)
    notice.name = "PixNotice"
    # Lugar reservado para a V2: QR Code, Copia e Cola e status.
    var area: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    area.add_theme_constant_override("separation", 18)
    v.add_child(area)
    var qr := QrPlaceholder.new()
    qr.name = "QrPlaceholder"
    qr.custom_minimum_size = Vector2(200, 200) * maxf(hub.k, 0.8)
    qr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    area.add_child(qr)
    var info := VBoxContainer.new()
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.add_theme_constant_override("separation", 8)
    area.add_child(info)
    Art.label(info, "PIX Copia e Cola", hub.fs(17), Art.GOLD, Art.FONT_SEMI)
    var code := Art.Frame.new("dark", 10)
    info.add_child(code)
    Art.label(code, "— disponível quando o pagamento real for ativado —", hub.fs(15), Color("8c8569"))
    Art.label(info, "Status", hub.fs(17), Art.GOLD, Art.FONT_SEMI)
    var status := HFlowContainer.new()
    status.add_theme_constant_override("h_separation", 8)
    info.add_child(status)
    status.add_child(Art.Stamp.new("AGUARDANDO PAGAMENTO", "soon", 12))
    status.add_child(Art.Stamp.new("PAGAMENTO CONFIRMADO", "soon", 12))
    Art.label(info, "(estados ilustrativos da versão real)", hub.fs(13), Color("8c8569"))
    var go := Art.Cta.new("SIMULAR ASSINATURA VIA PIX" if _club() else "SIMULAR PAGAMENTO PIX", "gold", 64 * maxf(hub.k, 0.85), 21)
    go.name = "SimulatePix"
    go.icon_kind = "pix"
    go.pressed.connect(func(): _confirm("pix"))
    v.add_child(go)
    _back_row(v)

# ------------------------------------------------------------ 2b. Cartão (simulado)
func _card(v: VBoxContainer):
    var top := HBoxContainer.new()
    top.alignment = BoxContainer.ALIGNMENT_CENTER
    top.add_theme_constant_override("separation", 12)
    v.add_child(top)
    top.add_child(Art.Glyph.new("card", 46, Art.GOLD_MID))
    var t := Art.label(top, "CARTÃO · MODO TESTE", hub.fs(30), Art.GOLD, Art.FONT_BOLD)
    t.name = "CardTitle"
    t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    t.autowrap_mode = TextServer.AUTOWRAP_OFF
    Art.label(v, _price_text(), hub.fs(20), Color("fff1c0"), Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
    var notice := Art.label(v, "Nenhum dado de cartão será solicitado nesta simulação.", hub.fs(18), Color("f2a070"), null, HORIZONTAL_ALIGNMENT_CENTER)
    notice.name = "CardNotice"
    var go := Art.Cta.new("SIMULAR ASSINATURA VIA CARTÃO" if _club() else "SIMULAR PAGAMENTO COM CARTÃO", "green" if _club() else "gold", 64 * maxf(hub.k, 0.85), 21)
    go.name = "SimulateCard"
    go.icon_kind = "card"
    go.pressed.connect(func(): _confirm("card"))
    v.add_child(go)
    _back_row(v)

func _back_row(v: VBoxContainer):
    var row: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    v.add_child(row)
    var back := Art.Cta.new("OUTRA FORMA DE PAGAMENTO", "dark", 52, 16)
    back.name = "PaymentBack"
    back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    back.pressed.connect(func(): _show("choose"))
    row.add_child(back)
    var cancel := Art.Cta.new("CANCELAR", "dark", 52, 16)
    cancel.name = "PaymentCancel"
    cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cancel.pressed.connect(hub.close_modal)
    row.add_child(cancel)

# ------------------------------------------------------------ 3. confirmação
func _confirm(method: String):
    var h = hub
    var pid := product_id
    if _club():
        h.open_confirm("SIMULAR ASSINATURA DO CLUB FRAIHA?", "Nenhuma cobrança será realizada.", "CANCELAR", "ATIVAR CLUB", func(): h.complete_mock(pid, method), "club")
    else:
        h.open_confirm("SIMULAR AQUISIÇÃO DO PACOTE FUNDADOR?", "Nenhum pagamento será realizado.\nEsta ação ativa apenas o estado de desenvolvimento.", "CANCELAR", "ATIVAR FUNDADOR", func(): h.complete_mock(pid, method))

## Moldura do futuro QR Code (sem gerar código algum).
class QrPlaceholder extends Control:
    func _draw():
        var r := Rect2(Vector2.ZERO, size)
        draw_rect(r, Color(0.02, 0.06, 0.04, 0.9))
        var gold := Color(0.79, 0.6, 0.27, 0.9)
        var x := 0.0
        while x < size.x:
            draw_line(Vector2(x, 0), Vector2(minf(x + 10, size.x), 0), gold, 2.0)
            draw_line(Vector2(x, size.y), Vector2(minf(x + 10, size.x), size.y), gold, 2.0)
            x += 18.0
        var y := 0.0
        while y < size.y:
            draw_line(Vector2(0, y), Vector2(0, minf(y + 10, size.y)), gold, 2.0)
            draw_line(Vector2(size.x, y), Vector2(size.x, minf(y + 10, size.y)), gold, 2.0)
            y += 18.0
        var f := get_theme_default_font()
        var lines := ["QR CODE PIX", "disponível no", "pagamento real"]
        var fs := int(maxf(12.0, size.x * 0.075))
        var yy := size.y / 2.0 - fs * 1.2
        for l in lines:
            var w := f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
            draw_string(f, Vector2((size.x - w) / 2.0, yy), l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("c9c2a8"))
            yy += fs * 1.4
