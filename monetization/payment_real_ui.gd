extends CenterContainer
## R39 · PAGAMENTO REAL (Mercado Pago): escolha PIX/Cartão → cobrança criada pelo SERVIDOR →
##   PIX: QR Code + Copia e Cola + "abrir no Mercado Pago"; Cartão: abre o checkout do Mercado Pago.
## R40 · Cartão DENTRO DO JOGO (Web): formulário seguro do Mercado Pago por cima do jogo (card_form_web.gd);
##   o servidor cria o pagamento com o token. Sem Public Key / fora da Web / formulário falhou → página do MP.
##   Enquanto espera: "aguardando pagamento" (consulta o servidor a cada poucos segundos e no botão JÁ PAGUEI).
##   Confirmado (webhook → servidor → acct_state) → tela de boas-vindas com as vantagens liberadas.
## O jogo NUNCA confirma pagamento sozinho e nunca vê dado de cartão nem chave do provedor.
const Art := preload("res://monetization/premium_art.gd")
const Catalog := preload("res://monetization/monetization_catalog.gd")
const CardForm := preload("res://monetization/card_form_web.gd")
const POLL_SECONDS := 5.0

var hub
var product_id := ""
var step := "choose"         # choose | creating | pix | card | done | error | expired
var method := ""
var charge := {}
var error_text := ""
var error_code := ""
var panel: Control
var poll: Timer
var countdown: Label
var status_label: Label
var copied_label: Label
var url_opener: Callable     # testes: substitui a abertura de link
var clipboard_writer: Callable
var card_form_factory: Callable   # testes: formulário de cartão falso (fora do navegador)
var card_form: Node
var card_form_failed := false
var card_note: Label

func setup(owner_hub, product: String):
    hub = owner_hub
    product_id = product
    name = "PaymentReal"
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    poll = Timer.new()
    poll.wait_time = POLL_SECONDS
    poll.timeout.connect(_poll)
    add_child(poll)
    var acc = _account()
    if acc != null and acc.has_signal("server_message"): acc.server_message.connect(_on_server)
    _show("choose")

func _exit_tree():
    if card_form != null: card_form.close()
    var acc = _account()
    if acc != null and acc.has_signal("server_message") and acc.server_message.is_connected(_on_server): acc.server_message.disconnect(_on_server)

func _account():
    return hub.main_hub.account if hub != null and hub.main_hub != null else null

func _club() -> bool:
    return product_id.begins_with("club")

func _price_text() -> String:
    return Catalog.planned_price(product_id) + (" · 30 DIAS DE CLUB" if _club() else " · PAGAMENTO ÚNICO")

# ------------------------------------------------------------ estrutura
func _show(id: String):
    step = id
    if panel != null:
        remove_child(panel)
        panel.queue_free()
    countdown = null
    status_label = null
    copied_label = null
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
    head.add_child(Art.Stamp.new("PAGAMENTO SEGURO · MERCADO PAGO", "ok", 13))
    var pname := Art.label(head, String(Catalog.product(product_id).get("name", "")), hub.fs(16), Art.MUTED, Art.FONT_SEMI)
    pname.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    match id:
        "creating": _creating(v)
        "pix": _pix(v)
        "card": _card(v)
        "error": _error(v)
        "expired": _expired(v)
        _: _choose(v)
    _fit_height.call_deferred(scroll, f)

func _fit_height(scroll: ScrollContainer, f: Control):
    if not is_instance_valid(scroll): return
    scroll.custom_minimum_size.y = minf(f.get_combined_minimum_size().y + 4.0, hub.view.y - 24.0)

# ------------------------------------------------------------ 1. escolha
func _choose(v: VBoxContainer):
    Art.label(v, "ESCOLHA A FORMA DE PAGAMENTO", hub.fs(30), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    Art.label(v, _price_text(), hub.fs(20), Color("fff1c0"), Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
    if _club():
        Art.label(v, "Sem renovação automática: quando os 30 dias acabarem, você renova se quiser.", hub.fs(16), Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
    v.add_child(_option("pix", "PIX", "Aprovação na hora · QR Code ou Copia e Cola", "PAGAR COM PIX", true))
    v.add_child(_option("card", "CARTÃO", ("Crédito aqui mesmo no jogo, no formulário seguro do Mercado Pago" if _inline_possible() else "Crédito ou débito na página segura do Mercado Pago"), "PAGAR COM CARTÃO", false))
    Art.label(v, "O FRAIHA nunca vê os dados do seu cartão. O recibo vai para o e-mail da sua conta.", hub.fs(14), Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
    var cancel := Art.Cta.new("CANCELAR", "dark", 54, 18)
    cancel.name = "PaymentCancel"
    cancel.pressed.connect(hub.close_modal)
    v.add_child(cancel)

func _option(m: String, title: String, desc: String, cta_text: String, main: bool) -> Control:
    var f := Art.Frame.new("reward" if main else "dark", int((20 if main else 16) * hub.k))
    f.name = "Option" + m.capitalize()
    f.glow = main
    var row: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    f.add_child(row)
    var g := Art.Glyph.new(m, (78 if main else 56) * maxf(hub.k, 0.8), Color("7fe0c8") if m == "pix" else Art.GOLD_MID, true)
    g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    row.add_child(g)
    var col := VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.add_theme_constant_override("separation", 6)
    row.add_child(col)
    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 10)
    col.add_child(top)
    var t := Art.label(top, title, hub.fs(32 if main else 26), Art.GOLD, Art.FONT_BOLD)
    t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    t.autowrap_mode = TextServer.AUTOWRAP_OFF
    if main: top.add_child(Art.Stamp.new("RECOMENDADO", "new", 14))
    Art.label(col, desc, hub.fs(16), Art.MUTED)
    var b := Art.Cta.new(cta_text, "gold" if main else ("green" if _club() else "dark"), (62 if main else 54) * maxf(hub.k, 0.85), 20 if main else 18)
    b.name = "Choose" + m.capitalize()
    b.icon_kind = m
    b.shimmer = main
    b.pressed.connect(func(): start(m))
    col.add_child(b)
    return f

## Pede a cobrança ao servidor (resposta assíncrona: payment_charge ou payment_error).
func start(m: String):
    method = m
    charge = {}
    var acc = _account()
    if acc == null or not acc.has_profile():
        error_code = "auth_required"
        error_text = "Entre na sua conta para comprar. Assim a vantagem fica salva na conta e vale em qualquer aparelho."
        _show("error")
        return
    if not acc.send_server({"type": "payment_create", "product_id": product_id, "method": m}):
        error_code = "offline"
        error_text = "Sem conexão com o servidor. Verifique a internet e tente de novo."
        _show("error")
        return
    _show("creating")

func _creating(v: VBoxContainer):
    Art.label(v, "PREPARANDO O PAGAMENTO…", hub.fs(28), Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    Art.label(v, ("Gerando o seu PIX no Mercado Pago." if method == "pix" else ("Preparando o formulário seguro do Mercado Pago." if _inline_possible() else "Abrindo o checkout seguro do Mercado Pago.")), hub.fs(18), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
    var spin := Spinner.new()
    spin.custom_minimum_size = Vector2(64, 64)
    spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    v.add_child(spin)

# ------------------------------------------------------------ 2a. PIX
func _pix(v: VBoxContainer):
    var top := HBoxContainer.new()
    top.alignment = BoxContainer.ALIGNMENT_CENTER
    top.add_theme_constant_override("separation", 12)
    v.add_child(top)
    top.add_child(Art.Glyph.new("pix", 46, Color("7fe0c8")))
    var t := Art.label(top, "PAGUE COM PIX", hub.fs(30), Art.GOLD, Art.FONT_BOLD)
    t.name = "PixTitle"
    t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    t.autowrap_mode = TextServer.AUTOWRAP_OFF
    Art.label(v, _price_text(), hub.fs(20), Color("fff1c0"), Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
    var area: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    area.add_theme_constant_override("separation", 18)
    v.add_child(area)
    var qr := TextureRect.new()
    qr.name = "PixQr"
    qr.custom_minimum_size = Vector2(230, 230) * maxf(hub.k, 0.8)
    qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    qr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    qr.texture = qr_texture(String(charge.get("qr_code_base64", "")))
    var qbox := PanelContainer.new()
    var qs := StyleBoxFlat.new()
    qs.bg_color = Color.WHITE
    qs.set_corner_radius_all(8)
    for side in ["left", "right", "top", "bottom"]: qs.set("content_margin_" + side, 10)
    qbox.add_theme_stylebox_override("panel", qs)
    qbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    qbox.add_child(qr)
    area.add_child(qbox)
    var info := VBoxContainer.new()
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.add_theme_constant_override("separation", 8)
    area.add_child(info)
    Art.label(info, "1. Abra o app do seu banco e escolha PIX.", hub.fs(17), Art.CREAM)
    Art.label(info, "2. Leia o QR Code ou use o PIX Copia e Cola:", hub.fs(17), Art.CREAM)
    var code := LineEdit.new()
    code.name = "PixCopyPaste"
    code.text = String(charge.get("copy_paste", ""))
    code.editable = false
    code.select_all_on_focus = true
    code.add_theme_font_size_override("font_size", hub.fs(14))
    info.add_child(code)
    var copy := Art.Cta.new("COPIAR CÓDIGO PIX", "gold", 54 * maxf(hub.k, 0.85), 19)
    copy.name = "PixCopy"
    copy.icon_kind = "pix"
    copy.shimmer = true
    copy.pressed.connect(copy_code)
    info.add_child(copy)
    copied_label = Art.label(info, "", hub.fs(15), Color("8fe08a"))
    copied_label.name = "PixCopied"
    if not String(charge.get("ticket_url", "")).is_empty():
        var open := Art.Cta.new("ABRIR NO MERCADO PAGO", "dark", 48, 16)
        open.name = "PixOpenTicket"
        open.pressed.connect(func(): _open_url(String(charge.ticket_url)))
        info.add_child(open)
    _waiting_block(v)

## Imagem PNG (base64) do QR Code gerado pelo Mercado Pago.
static func qr_texture(b64: String) -> Texture2D:
    if b64.is_empty(): return null
    var bytes := Marshalls.base64_to_raw(b64)
    var img := Image.new()
    if img.load_png_from_buffer(bytes) != OK: return null
    return ImageTexture.create_from_image(img)

func copy_code():
    var text := String(charge.get("copy_paste", ""))
    if text.is_empty(): return
    if clipboard_writer.is_valid(): clipboard_writer.call(text)
    elif OS.has_feature("web"):
        JavaScriptBridge.eval("navigator.clipboard && navigator.clipboard.writeText(%s)" % JSON.stringify(text))
    else: DisplayServer.clipboard_set(text)
    if copied_label != null: copied_label.text = "Código copiado! Cole no app do seu banco (PIX Copia e Cola)."

# ------------------------------------------------------------ 2b. Cartão
func _card(v: VBoxContainer):
    card_note = null
    var top := HBoxContainer.new()
    top.alignment = BoxContainer.ALIGNMENT_CENTER
    top.add_theme_constant_override("separation", 12)
    v.add_child(top)
    top.add_child(Art.Glyph.new("card", 46, Art.GOLD_MID))
    var t := Art.label(top, "PAGUE COM CARTÃO", hub.fs(30), Art.GOLD, Art.FONT_BOLD)
    t.name = "CardTitle"
    t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    t.autowrap_mode = TextServer.AUTOWRAP_OFF
    Art.label(v, _price_text(), hub.fs(20), Color("fff1c0"), Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
    if _inline_ready():
        Art.label(v, "Preencha os dados do cartão no formulário seguro do Mercado Pago, aqui mesmo no jogo. A vantagem é liberada assim que o pagamento for aprovado.", hub.fs(17), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
        var form := Art.Cta.new("PREENCHER DADOS DO CARTÃO", "green" if _club() else "gold", 64 * maxf(hub.k, 0.85), 21)
        form.name = "CardOpenForm"
        form.icon_kind = "card"
        form.shimmer = true
        form.pressed.connect(open_card_form)
        v.add_child(form)
        card_note = Art.label(v, "", hub.fs(16), Color("ffe6a0"), Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
        card_note.name = "CardFormNote"
        if not String(charge.get("checkout_url", "")).is_empty():
            var page := Art.Cta.new("PREFIRO PAGAR NA PÁGINA DO MERCADO PAGO", "dark", 46, 15)
            page.name = "CardOpenCheckout"
            page.pressed.connect(func(): _open_url(String(charge.get("checkout_url", ""))))
            v.add_child(page)
    else:
        var msg := "O pagamento acontece na página segura do Mercado Pago (nova aba). Depois de pagar, volte para o jogo: a vantagem é liberada sozinha."
        if card_form_failed: msg = "Não foi possível abrir o formulário do cartão aqui no jogo. " + msg
        Art.label(v, msg, hub.fs(17), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
        var go := Art.Cta.new("ABRIR PAGAMENTO COM CARTÃO", "green" if _club() else "gold", 64 * maxf(hub.k, 0.85), 21)
        go.name = "CardOpenCheckout"
        go.icon_kind = "card"
        go.shimmer = true
        go.pressed.connect(func(): _open_url(String(charge.get("checkout_url", ""))))
        v.add_child(go)
    _waiting_block(v)

# ------------------------------------------------------------ R40 · cartão dentro do jogo
func _inline_possible() -> bool:
    return CardForm.available() or card_form_factory.is_valid()

func _inline_ready() -> bool:
    return _inline_possible() and not card_form_failed and not String(charge.get("public_key", "")).is_empty()

func open_card_form():
    if not _inline_ready(): return
    if card_form == null:
        card_form = card_form_factory.call() if card_form_factory.is_valid() else CardForm.new()
        card_form.name = "CardForm"
        add_child(card_form)
        card_form.submitted.connect(_on_card_submitted)
        card_form.failed.connect(_on_card_failed)
        card_form.closed.connect(func(): _note("Formulário fechado. Toque em PREENCHER DADOS DO CARTÃO para continuar."))
    var acc = _account()
    _note("")
    CardForm.release_game_focus(get_viewport())
    card_form.open(String(charge.get("public_key", "")), int(charge.get("amount_cents", 0)), String(acc.email) if acc != null else "",
        String(Catalog.product(product_id).get("name", "FRAIHA")).to_upper(), _price_text())

func _note(text: String):
    if card_note != null and is_instance_valid(card_note): card_note.text = text

func _on_card_submitted(d: Dictionary):
    var acc = _account()
    var msg := {"type": "payment_card_pay", "charge_id": String(charge.get("id", ""))}
    for k in ["token", "payment_method_id", "issuer_id", "id_type", "id_number", "device_id"]: msg[k] = String(d.get(k, ""))
    if acc == null or not acc.send_server(msg):
        card_form.resolve_reject("Sem conexão com o servidor. Verifique a internet e tente de novo.")
        return
    _note("Processando o pagamento no Mercado Pago…")

func _on_card_failed(_reason: String):
    card_form_failed = true
    if step == "card": _show("card")

func _on_card_result(msg: Dictionary):
    if String(msg.get("charge_id", "")) != String(charge.get("id", "-")) or card_form == null: return
    var text := String(msg.get("message", ""))
    match String(msg.get("status", "")):
        "approved":
            card_form.resolve_ok()
            card_form.close()
            _paid()
        "pending":
            card_form.resolve_ok()
            card_form.close()
            _note(text)
            if status_label != null: status_label.text = "Pagamento em análise pelo Mercado Pago…"
        _:
            card_form.resolve_reject(text if not text.is_empty() else "O cartão foi recusado. Nada foi cobrado. Tente outro cartão ou pague com PIX.")
            _note(text)

func _waiting_block(v: VBoxContainer):
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 10)
    v.add_child(row)
    var spin := Spinner.new()
    spin.custom_minimum_size = Vector2(28, 28)
    row.add_child(spin)
    status_label = Art.label(row, "Aguardando a confirmação do pagamento…", hub.fs(18), Color("ffe6a0"), Art.FONT_SEMI)
    status_label.name = "PaymentWaiting"
    status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    status_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    countdown = Art.label(v, "", hub.fs(15), Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
    countdown.name = "PaymentCountdown"
    _tick_countdown()
    var btns: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    btns.add_theme_constant_override("separation", 12)
    v.add_child(btns)
    var paid := Art.Cta.new("JÁ PAGUEI", "green", 52, 17)
    paid.name = "PaymentCheck"
    paid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    paid.pressed.connect(func():
        if status_label != null: status_label.text = "Conferindo com o Mercado Pago…"
        _poll())
    btns.add_child(paid)
    var other := Art.Cta.new("OUTRA FORMA DE PAGAMENTO", "dark", 52, 16)
    other.name = "PaymentBack"
    other.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    other.pressed.connect(func():
        poll.stop()
        if card_form != null: card_form.close()
        _show("choose"))
    btns.add_child(other)
    var close := Art.Cta.new("FECHAR", "dark", 52, 16)
    close.name = "PaymentCancel"
    close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    close.pressed.connect(hub.close_modal)
    btns.add_child(close)
    Art.label(v, "Pode fechar esta janela: se o pagamento for aprovado depois, a vantagem aparece na sua conta do mesmo jeito.", hub.fs(14), Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)

func _process(_d):
    if step in ["pix", "card"] and countdown != null and Engine.get_process_frames() % 30 == 0: _tick_countdown()

func _tick_countdown():
    if countdown == null: return
    var exp := String(charge.get("expires_at", ""))
    if exp.is_empty() or method != "pix":
        countdown.text = ""
        return
    var left := int(Time.get_unix_time_from_datetime_string(exp.substr(0, 19)) - Time.get_unix_time_from_system())
    if left <= 0:
        countdown.text = "Este PIX expirou."
        return
    countdown.text = "O código vale por mais %d:%02d" % [left / 60, left % 60]

# ------------------------------------------------------------ erro / expirado
func _error(v: VBoxContainer):
    Art.label(v, "NÃO FOI POSSÍVEL CONTINUAR", hub.fs(28), Color("ffb08a"), Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    var l := Art.label(v, error_text, hub.fs(19), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
    l.name = "PaymentErrorText"
    var row: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    v.add_child(row)
    if error_code in ["server_error", "offline"]:
        var again := Art.Cta.new("TENTAR DE NOVO", "gold", 52, 17)
        again.name = "PaymentRetry"
        again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        again.pressed.connect(func(): start(method if not method.is_empty() else "pix"))
        row.add_child(again)
    var close := Art.Cta.new("FECHAR", "dark", 52, 17)
    close.name = "PaymentCancel"
    close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    close.pressed.connect(hub.close_modal)
    row.add_child(close)

func _expired(v: VBoxContainer):
    Art.label(v, "O PIX EXPIROU", hub.fs(28), Color("ffb08a"), Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    Art.label(v, "Nada foi cobrado. Gere um novo código para continuar.", hub.fs(19), Art.CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
    var again := Art.Cta.new("GERAR NOVO PIX", "gold", 56, 18)
    again.name = "PaymentRetry"
    again.pressed.connect(func(): start("pix"))
    v.add_child(again)
    var close := Art.Cta.new("FECHAR", "dark", 52, 17)
    close.name = "PaymentCancel"
    close.pressed.connect(hub.close_modal)
    v.add_child(close)

# ------------------------------------------------------------ servidor
func _poll():
    var acc = _account()
    var id := String(charge.get("id", ""))
    if acc != null and not id.is_empty(): acc.send_server({"type": "payment_status", "charge_id": id})

const ERRORS := {
    "auth_required": "Entre na sua conta para comprar. Assim a vantagem fica salva na conta e vale em qualquer aparelho.",
    "already_founder": "Você já é Fundador do Reino. Obrigado por apoiar o FRAIHA desde o começo!",
    "founder_sold_out": "As vagas do Pacote Fundador se esgotaram. Obrigado pelo interesse!",
    "provider_not_configured": "Os pagamentos ainda não foram ligados neste servidor. Tente novamente mais tarde.",
    "email_required": "Sua conta precisa de um e-mail para receber o recibo do pagamento.",
    "server_error": "O Mercado Pago não respondeu agora. Nada foi cobrado. Tente novamente em instantes.",
}

func _on_server(msg: Dictionary):
    if not is_inside_tree(): return
    match String(msg.get("type", "")):
        "payment_charge":
            if step != "creating": return
            charge = msg.get("charge", {}) if msg.get("charge") is Dictionary else {}
            if String(charge.get("product_id", product_id)) != product_id: return
            card_form_failed = false
            _show("pix" if String(charge.get("method", method)) == "pix" else "card")
            poll.start()
            if step == "card" and _inline_ready(): open_card_form.call_deferred()
        "payment_error":
            if step not in ["creating", "pix", "card"]: return
            poll.stop()
            error_code = String(msg.get("code", ""))
            error_text = String(ERRORS.get(error_code, String(msg.get("message", "Não foi possível iniciar o pagamento."))))
            _show("error")
        "payment_card_result":
            _on_card_result(msg)
        "payment_update":
            var c = msg.get("charge", {})
            if not (c is Dictionary) or String(c.get("id", "")) != String(charge.get("id", "-")): return
            match String(c.get("status", "")):
                "paid": _paid()
                "cancelled":
                    poll.stop()
                    _show("expired")
                _:
                    if status_label != null: status_label.text = "Aguardando a confirmação do pagamento…"

func _paid():
    if step == "done": return
    poll.stop()
    if card_form != null: card_form.close()
    step = "done"
    var h = hub
    var pid := product_id
    h.close_modal()
    h.payment_confirmed(pid)

func _open_url(url: String):
    if not url.begins_with("https://"): return
    if url_opener.is_valid(): url_opener.call(url)
    elif hub != null and hub.url_opener.is_valid(): hub.url_opener.call(url)
    else: OS.shell_open(url)

## Indicador de "carregando" (arco girando), sem depender de arte.
class Spinner extends Control:
    var t := 0.0
    func _process(d):
        t += d
        queue_redraw()
    func _draw():
        var c := size / 2.0
        var r := minf(size.x, size.y) / 2.0 - 3.0
        draw_arc(c, r, 0, TAU, 32, Color(0.79, 0.6, 0.27, 0.25), 4.0)
        draw_arc(c, r, t * 5.0, t * 5.0 + PI * 0.9, 24, Color("ffd76a"), 4.0)
