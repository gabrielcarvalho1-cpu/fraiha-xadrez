extends CanvasLayer
## Telas de conta (entrar, criar conta, Google, recuperar senha, nickname).
## Apenas coleta dados e chama AccountService; não guarda senha.
## Visual: a arte de referência aprovada (account/art/login_art.png — moldura, cavalos, brasão,
## estandartes, campos, botões e links) é a própria tela de ENTRAR; os controles interativos
## ficam exatamente sobre os elementos pintados. As outras páginas usam a mesma moldura sem o
## interior (login_art_blank.png) com os componentes recortados da arte (login_skin.gd).
signal closed
signal ready_for_ranked
const Mobile = preload("res://ui_v022/mobile_layout.gd")
const GOLD = Color("f4ce7f")
const Art = preload("res://account/login_art.gd")
const LoginSkin = preload("res://account/login_skin.gd")
const WebTextField = preload("res://ui_v022/web_text_field.gd")
const ART_FULL := preload("res://account/art/login_art.png")
const ART_BLANK := preload("res://account/art/login_art_blank.png")
const REF := Vector2(1122, 1402)            # tamanho da arte de referência
const INNER := Rect2(196, 430, 738, 825)    # interior útil (abaixo da faixa do título)
const TITLE_BAND := Rect2(222, 300, 678, 90)
const BODY_W := 1002.0                       # largura do corpo do painel na arte
# Posições dos elementos já pintados na arte de ENTRAR (coords da referência)
const SLOT_EMAIL := Rect2(196, 445, 738, 120)
const SLOT_PASSWORD := Rect2(196, 560, 738, 120)
const SLOT_ENTER := Rect2(196, 688, 738, 150)
const SLOT_GOOGLE := Rect2(196, 846, 738, 104)
const SLOT_LINKS := [Rect2(290, 993, 550, 72), Rect2(290, 1065, 550, 72), Rect2(290, 1138, 550, 72)]
const SLOT_STATUS := Rect2(230, 1212, 662, 40)

var account
var dim: ColorRect
var scroll: ScrollContainer
var panel: Control            # escala = k; filhos em coordenadas da referência
var art: TextureRect
var box: VBoxContainer        # páginas secundárias (também guarda labels para testes)
var title_label: Label
var status_label: Label
var page := ""
var message := ""
var return_to_ranked := false
var fields := {}
var k := 1.0
var frame                      # compat: antes era a moldura desenhada; hoje aponta para `art`

func setup(service):
    account = service
    layer = 60
    dim = ColorRect.new()
    dim.name = "AccountDim"
    dim.color = Color(0.02, 0.04, 0.03, 0.78)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    scroll = ScrollContainer.new()
    scroll.name = "AccountScroll"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    add_child(scroll)
    var holder := Control.new()      # ocupa o tamanho da arte escalada para o scroll medir
    holder.name = "AccountHolder"
    holder.mouse_filter = Control.MOUSE_FILTER_PASS
    scroll.add_child(holder)
    panel = Control.new()
    panel.name = "AccountPanel"
    panel.size = REF
    panel.mouse_filter = Control.MOUSE_FILTER_PASS
    holder.add_child(panel)
    art = TextureRect.new()
    art.name = "LoginArt"
    art.texture = ART_FULL
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_SCALE
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    art.size = REF
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(art)
    frame = art
    title_label = Label.new()
    title_label.name = "Title"
    title_label.position = TITLE_BAND.position
    title_label.size = TITLE_BAND.size
    title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title_label.add_theme_font_override("font", Art.FONT_BOLD)
    title_label.add_theme_font_size_override("font_size", 62)
    title_label.add_theme_color_override("font_color", Color("f3d58c"))
    title_label.add_theme_color_override("font_outline_color", Color("3a2408"))
    title_label.add_theme_constant_override("outline_size", 8)
    title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
    title_label.add_theme_constant_override("shadow_offset_y", 4)
    title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(title_label)
    box = VBoxContainer.new()
    box.name = "AccountBox"
    box.position = INNER.position + Vector2(0, 16)
    box.size = Vector2(INNER.size.x, INNER.size.y - 16)
    box.add_theme_constant_override("separation", 18)
    panel.add_child(box)
    status_label = _make_status()
    panel.add_child(status_label)
    account.changed.connect(_on_account_changed)
    account.notice.connect(_on_notice)
    account.recovery_started.connect(func(): open("new_password"))
    get_viewport().size_changed.connect(_layout)
    hide_ui()

func is_open() -> bool:
    return dim.visible

func open(target := "", info := "", for_ranked := false):
    return_to_ranked = for_ranked
    message = info
    if target.is_empty(): target = _natural_page()
    _show(target)
    dim.show(); scroll.show()
    _layout()

func hide_ui():
    dim.hide(); scroll.hide()

func close():
    hide_ui()
    closed.emit()

func _natural_page() -> String:
    if not account.configured(): return "unavailable"
    if not account.signed_in(): return "login"
    if not account.server_ready: return "waiting"
    if account.needs_nickname: return "nickname"
    return "account"

func _on_account_changed():
    if not is_open(): return
    if account.has_profile() and return_to_ranked:
        return_to_ranked = false
        hide_ui()
        ready_for_ranked.emit()
        return
    if account.has_profile() and page in ["login", "signup", "nickname", "waiting"]:
        close()
        return
    var natural = _natural_page()
    if page in ["login", "signup", "nickname", "account", "waiting"] and natural != page:
        _show("waiting" if account.signed_in() and not account.server_ready else natural)
    elif page == "waiting" and account.server_ready:
        _show(natural)

func _on_notice(text: String, is_error: bool):
    if not is_open(): return
    status_label.text = text
    status_label.add_theme_color_override("font_color", Color("ff9d86") if is_error else Color("b9e3a6"))

func _process(_delta):
    if scroll.visible: _layout()

# ---------------------------------------------------------------- layout (escala única)
func _layout():
    var mobile = Mobile.active(get_viewport())
    var vr = get_viewport().get_visible_rect()
    var area = Mobile.safe_rect(get_viewport()) if mobile else vr
    dim.position = Vector2.ZERO
    dim.size = vr.size
    # A arte inteira (cavalos incluídos) cabe na altura; em telas baixas (celular deitado)
    # limita a redução e deixa rolar.
    # Largura útil = corpo do painel (x 60..1062 da arte); as bordas de floresta podem sair da tela.
    k = minf((area.size.y - 8.0) / REF.y, (area.size.x - 8.0) / BODY_W)
    var min_k := 0.5 if mobile else 0.42
    if k < min_k: k = minf(min_k, (area.size.x - 8.0) / BODY_W)
    panel.scale = Vector2.ONE * k
    var holder: Control = panel.get_parent()
    holder.custom_minimum_size = REF * k
    scroll.position = area.position
    scroll.size = area.size
    var free: Vector2 = area.size - REF * k
    panel.position = Vector2(free.x / 2.0, maxf(0.0, free.y / 2.0))
    holder.custom_minimum_size = Vector2(area.size.x, maxf(REF.y * k, area.size.y))

# ---------------------------------------------------------------- construção
func _clear():
    fields.clear()
    for child in box.get_children():
        box.remove_child(child)
        child.queue_free()
    for child in panel.get_children():
        if child.has_meta("slot"):
            panel.remove_child(child)
            child.queue_free()

func _make_status() -> Label:
    var l := Label.new()
    l.name = "Status"
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    l.add_theme_font_size_override("font_size", 22)
    l.add_theme_color_override("font_color", Color("c9c2a8"))
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
    l.add_theme_constant_override("shadow_offset_y", 2)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l

func _label(text: String, size := 16, color := Color("e8e0c8")) -> Label:
    var l = Label.new()
    l.text = text
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.add_theme_font_size_override("font_size", int(size * 1.6))
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
    l.add_theme_constant_override("shadow_offset_y", 2)
    box.add_child(l)
    return l

## Campo: `slot` = posição fixa sobre a arte de ENTRAR (baked); senão entra no box.
func _input_field(key: String, placeholder: String, secret := false, slot := Rect2()) -> LineEdit:
    var holder = LoginSkin.Field.new()
    holder.name = "Field_" + key
    holder.baked = slot.size.x > 0.0
    holder.setup("lock" if secret else ("mail" if key == "email" else "person_add"), secret)
    var e: LineEdit = holder.line
    e.placeholder_text = placeholder
    if key == "email": e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
    if secret: e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
    _place(holder, slot)
    WebTextField.attach(e)   # Web no celular: campo HTML real por cima para o teclado virtual abrir
    fields[key] = e
    return e

func _button(text: String, action: Callable, primary := false, slot := Rect2()) -> Button:
    var b = LoginSkin.SkinButton.new()
    b.text = text
    b.primary = primary
    b.baked = slot.size.x > 0.0
    b.font_size = 64 if primary else 40
    b.custom_minimum_size = Vector2(738, 150 if primary else 104)
    if "GOOGLE" in text: b.icon_kind = "google"
    b.pressed.connect(action)
    _place(b, slot)
    return b

const LINK_ICONS = {"Criar conta": "person", "Esqueci minha senha": "key", "Jogar como convidado": "persons"}

func _link(text: String, action: Callable, slot := Rect2()) -> Button:
    var b = LoginSkin.SkinLink.new()
    b.text = text
    b.icon_kind = LINK_ICONS.get(text, "")
    b.baked = slot.size.x > 0.0
    b.pressed.connect(action)
    if slot.size.x > 0.0: _place(b, slot)
    else:
        if links_box == null:
            var center = CenterContainer.new()
            box.add_child(center)
            links_box = VBoxContainer.new()
            links_box.add_theme_constant_override("separation", 0)
            center.add_child(links_box)
        links_box.add_child(b)
    return b

var links_box: VBoxContainer = null

func _divider():
    links_box = null
    var d = LoginSkin.Divider.new()
    d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    box.add_child(d)
    return d

func _place(c: Control, slot: Rect2):
    if slot.size.x > 0.0:
        c.set_meta("slot", true)
        c.position = slot.position
        c.size = slot.size
        panel.add_child(c)
    else:
        c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        box.add_child(c)

func _value(key: String) -> String:
    return fields[key].text if fields.has(key) else ""

func _show(target: String):
    page = target
    _clear()
    links_box = null
    var titles := {"login":"ENTRAR NO FRAIHA", "signup":"CRIAR CONTA", "recover":"RECUPERAR SENHA",
        "new_password":"NOVA SENHA", "nickname":"ESCOLHA SEU NOME", "account":"SUA CONTA",
        "waiting":"CONECTANDO…", "unavailable":"CONTAS"}
    var baked := target == "login"
    art.texture = ART_FULL if baked else ART_BLANK
    title_label.text = String(titles.get(target, "CONTA"))
    title_label.visible = not baked    # na arte de ENTRAR o título já está pintado
    box.visible = not baked
    status_label.text = ""
    status_label.position = SLOT_STATUS.position
    status_label.size = SLOT_STATUS.size
    if not message.is_empty() and not baked: _label(message, 16, Color("f0d9a0"))
    match target:
        "login":
            _input_field("email", "E-mail", false, SLOT_EMAIL)
            _input_field("password", "Senha", true, SLOT_PASSWORD).text_submitted.connect(func(_t): account.sign_in(_value("email"), _value("password")))
            _button("ENTRAR", func(): account.sign_in(_value("email"), _value("password")), true, SLOT_ENTER)
            _button("CONTINUAR COM GOOGLE", func(): account.sign_in_google("ranked" if return_to_ranked else ""), false, SLOT_GOOGLE)
            _link("Criar conta", func(): _show("signup"), SLOT_LINKS[0])
            _link("Esqueci minha senha", func(): _show("recover"), SLOT_LINKS[1])
            _link("Jogar como convidado", close, SLOT_LINKS[2])
            if not message.is_empty():
                status_label.text = message
                status_label.add_theme_color_override("font_color", Color("f0d9a0"))
        "signup":
            _input_field("nickname", "Nome de jogador (3 a 16)")
            _input_field("email", "E-mail")
            _input_field("password", "Senha (mín. 8 caracteres)", true)
            _button("CRIAR CONTA", func(): account.sign_up(_value("email"), _value("password"), _value("nickname")), true)
            _button("CONTINUAR COM GOOGLE", func(): account.sign_in_google("ranked" if return_to_ranked else ""))
            _divider()
            _link("Já tenho conta — Entrar", func(): _show("login"))
            _link("Jogar como convidado", close)
        "recover":
            _label("Enviaremos um link para criar uma nova senha.", 15)
            _input_field("email", "E-mail da conta")
            _button("ENVIAR LINK", func(): account.recover(_value("email")), true)
            _divider()
            _link("Voltar", func(): _show("login"))
        "new_password":
            _input_field("password", "Nova senha (mín. 8 caracteres)", true)
            _button("SALVAR NOVA SENHA", func(): account.update_password(_value("password")), true)
            _divider()
            _link("Fechar", close)
        "nickname":
            _label("É assim que os adversários verão você. Seu e-mail nunca é mostrado.", 15)
            _input_field("nickname", "Nome de jogador (3 a 16)").text_submitted.connect(func(t): account.create_profile(t))
            _button("CONFIRMAR NOME", func(): account.create_profile(_value("nickname")), true)
            _divider()
            _link("Sair da conta", account.sign_out)
        "account":
            _label("Jogador: " + account.nickname(), 18)
            _label(account.email, 14, Color("b8b19c"))
            if not account.persistent_backend:
                _label("Servidor em modo de teste: progresso Ranked NÃO é permanente.", 14, Color("ff9d86"))
            _button("CONTINUAR", close, true)
            _button("SAIR DA CONTA", account.sign_out)
        "waiting":
            _label("Conectando sua conta ao servidor FRAIHA…", 16)
            _divider()
            _link("Jogar como convidado", close)
        "unavailable":
            _label("As contas FRAIHA ainda não foram ativadas nesta versão. Você pode jogar Local, Bot e Online Casual como convidado.", 16)
            _button("JOGAR COMO CONVIDADO", close, true)
    if not baked:
        # status abaixo do conteúdo do box
        var spacer := Control.new()
        spacer.custom_minimum_size.y = 4
        box.add_child(spacer)
        status_label.position = Vector2(SLOT_STATUS.position.x, INNER.position.y + 16.0 + box.get_combined_minimum_size().y + 12.0)
    message = ""
    if not fields.is_empty() and not Mobile.active(get_viewport()):
        fields.values()[0].grab_focus.call_deferred()
    _layout.call_deferred()
