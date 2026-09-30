extends CanvasLayer
## Telas de conta (entrar, criar conta, Google, recuperar senha, nickname).
## Apenas coleta dados e chama AccountService; não guarda senha.
signal closed
signal ready_for_ranked
const Mobile = preload("res://ui_v022/mobile_layout.gd")
const GOLD = Color("f4ce7f")
var account
var dim: ColorRect
var panel: PanelContainer
var scroll: ScrollContainer
var box: VBoxContainer
var status_label: Label
var page := ""
var message := ""
var return_to_ranked := false
var fields := {}

func setup(service):
    account = service
    layer = 60
    dim = ColorRect.new()
    dim.color = Color(0.02, 0.04, 0.03, 0.78)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    panel = PanelContainer.new()
    var style = StyleBoxFlat.new()
    style.bg_color = Color("#142217f7")
    style.border_color = Color("#b19758")
    style.set_border_width_all(2)
    style.set_corner_radius_all(8)
    for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 18)
    panel.add_theme_stylebox_override("panel", style)
    add_child(panel)
    scroll = ScrollContainer.new()
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    panel.add_child(scroll)
    box = VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 10)
    scroll.add_child(box)
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
    dim.show(); panel.show()
    _layout()

func hide_ui():
    dim.hide(); panel.hide()

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
    if panel.visible: _layout()

func _layout():
    var mobile = Mobile.active(get_viewport())
    var area = Mobile.safe_rect(get_viewport()) if mobile else get_viewport().get_visible_rect()
    dim.position = Vector2.ZERO
    dim.size = get_viewport().get_visible_rect().size
    # Desktop usa coordenadas 1920x1080; amplia o painel para manter a leitura confortável.
    var ui_scale = 1.0 if mobile else 1.45
    panel.scale = Vector2.ONE * ui_scale
    var width = minf(480.0, (area.size.x - 16.0) / ui_scale)
    box.custom_minimum_size.x = width - 40.0
    var wanted = box.get_combined_minimum_size().y + 40.0
    var height = minf(wanted, (area.size.y - 16.0) / ui_scale)
    scroll.custom_minimum_size = Vector2(width - 40.0, height - 40.0)
    panel.custom_minimum_size = Vector2.ZERO
    panel.reset_size()
    panel.size = Vector2(width, height)
    panel.position = area.position + (area.size - panel.size * ui_scale) / 2.0

func _clear():
    fields.clear()
    for child in box.get_children():
        box.remove_child(child)
        child.queue_free()

func _label(text: String, size := 16, color := Color("e8e0c8")) -> Label:
    var l = Label.new()
    l.text = text
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    box.add_child(l)
    return l

func _input_field(key: String, placeholder: String, secret := false) -> LineEdit:
    var e = LineEdit.new()
    e.placeholder_text = placeholder
    e.secret = secret
    e.custom_minimum_size.y = 46
    e.add_theme_font_size_override("font_size", 18)
    if key == "email": e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
    if secret: e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
    box.add_child(e)
    fields[key] = e
    return e

func _button(text: String, action: Callable, primary := false) -> Button:
    var b = Button.new()
    b.text = text
    b.custom_minimum_size.y = 48
    b.add_theme_font_size_override("font_size", 17)
    var style = StyleBoxFlat.new()
    style.bg_color = Color("2c4a2f") if primary else Color("14221d")
    style.border_color = GOLD if primary else Color("84754b")
    style.set_border_width_all(1)
    style.set_corner_radius_all(6)
    b.add_theme_stylebox_override("normal", style)
    var hover = style.duplicate()
    hover.bg_color = Color("36593a")
    for state in ["hover", "pressed", "focus"]: b.add_theme_stylebox_override(state, hover)
    b.add_theme_color_override("font_color", Color("f4edda"))
    b.pressed.connect(action)
    box.add_child(b)
    return b

func _link(text: String, action: Callable) -> Button:
    var b = Button.new()
    b.text = text
    b.flat = true
    b.custom_minimum_size.y = 40
    b.add_theme_font_size_override("font_size", 15)
    b.add_theme_color_override("font_color", GOLD)
    b.pressed.connect(action)
    box.add_child(b)
    return b

func _value(key: String) -> String:
    return fields[key].text if fields.has(key) else ""

func _show(target: String):
    page = target
    _clear()
    var title = _label({"login":"ENTRAR NO FRAIHA", "signup":"CRIAR CONTA", "recover":"RECUPERAR SENHA",
        "new_password":"NOVA SENHA", "nickname":"ESCOLHA SEU NOME NO FRAIHA", "account":"SUA CONTA",
        "waiting":"CONECTANDO…", "unavailable":"CONTAS"}.get(target, "CONTA"), 22, GOLD)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    if not message.is_empty(): _label(message, 16, Color("f0d9a0"))
    match target:
        "login":
            _input_field("email", "E-mail")
            _input_field("password", "Senha", true).text_submitted.connect(func(_t): account.sign_in(_value("email"), _value("password")))
            _button("ENTRAR", func(): account.sign_in(_value("email"), _value("password")), true)
            _button("CONTINUAR COM GOOGLE", func(): account.sign_in_google("ranked" if return_to_ranked else ""))
            _link("Criar conta", func(): _show("signup"))
            _link("Esqueci minha senha", func(): _show("recover"))
            _link("Jogar como convidado", close)
        "signup":
            _input_field("nickname", "Nome de jogador (3 a 16)")
            _input_field("email", "E-mail")
            _input_field("password", "Senha (mín. 8 caracteres)", true)
            _button("CRIAR CONTA", func(): account.sign_up(_value("email"), _value("password"), _value("nickname")), true)
            _button("CONTINUAR COM GOOGLE", func(): account.sign_in_google("ranked" if return_to_ranked else ""))
            _link("Já tenho conta — Entrar", func(): _show("login"))
            _link("Jogar como convidado", close)
        "recover":
            _label("Enviaremos um link para criar uma nova senha.", 15)
            _input_field("email", "E-mail da conta")
            _button("ENVIAR LINK", func(): account.recover(_value("email")), true)
            _link("Voltar", func(): _show("login"))
        "new_password":
            _input_field("password", "Nova senha (mín. 8 caracteres)", true)
            _button("SALVAR NOVA SENHA", func(): account.update_password(_value("password")), true)
            _link("Fechar", close)
        "nickname":
            _label("É assim que os adversários verão você. Seu e-mail nunca é mostrado.", 15)
            _input_field("nickname", "Nome de jogador (3 a 16)").text_submitted.connect(func(t): account.create_profile(t))
            _button("CONFIRMAR NOME", func(): account.create_profile(_value("nickname")), true)
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
            _link("Jogar como convidado", close)
        "unavailable":
            _label("As contas FRAIHA ainda não foram ativadas nesta versão. Você pode jogar Local, Bot e Online Casual como convidado.", 16)
            _button("JOGAR COMO CONVIDADO", close, true)
    status_label = _label("", 15)
    message = ""
    if not fields.is_empty() and not Mobile.active(get_viewport()):
        fields.values()[0].grab_focus.call_deferred()
    _layout.call_deferred()
