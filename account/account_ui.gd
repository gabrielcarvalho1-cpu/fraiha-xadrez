extends CanvasLayer
## Telas de conta (entrar, criar conta, Google, recuperar senha, nickname).
## Apenas coleta dados e chama AccountService; não guarda senha.
signal closed
signal ready_for_ranked
const Mobile = preload("res://ui_v022/mobile_layout.gd")
const GOLD = Color("f4ce7f")
const Art = preload("res://account/login_art.gd")
const Widgets = preload("res://account/login_widgets.gd")
const WebTextField = preload("res://ui_v022/web_text_field.gd")
var frame: Control
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
    # Moldura medieval desenhada atrás do conteúdo (painel, brasão, cavalos, estandartes).
    frame = preload("res://account/login_frame.gd").new()
    frame.name = "LoginFrame"
    add_child(frame)
    panel = PanelContainer.new()
    panel.name = "AccountPanel"
    var style = StyleBoxEmpty.new()
    style.content_margin_left = 46
    style.content_margin_right = 46
    style.content_margin_top = 70
    style.content_margin_bottom = 28
    panel.add_theme_stylebox_override("panel", style)
    add_child(panel)
    scroll = ScrollContainer.new()
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    panel.add_child(scroll)
    box = VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 14)
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
    dim.show(); panel.show(); frame.show()
    _layout()

func hide_ui():
    dim.hide(); panel.hide(); frame.hide()

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
    if panel.visible:
        _layout()
        if is_instance_valid(status_label):
            for c in status_label.get_children(): if c is Control: c.queue_redraw()

func _layout():
    var mobile = Mobile.active(get_viewport())
    var area = Mobile.safe_rect(get_viewport()) if mobile else get_viewport().get_visible_rect()
    dim.position = Vector2.ZERO
    dim.size = get_viewport().get_visible_rect().size
    frame.compact = mobile
    var style: StyleBoxEmpty = panel.get_theme_stylebox("panel")
    style.content_margin_left = 30 if mobile else 50
    style.content_margin_right = style.content_margin_left
    style.content_margin_top = 58 if mobile else 74
    style.content_margin_bottom = 22 if mobile else 30
    # Espaço para os cavalos e o brasão que saem por cima da moldura.
    var above = 70.0 if mobile else 100.0
    var width = minf(440.0, area.size.x - 36.0) if mobile else 600.0
    box.custom_minimum_size.x = width - style.content_margin_left * 2.0
    var wanted = box.get_combined_minimum_size().y + style.content_margin_top + style.content_margin_bottom
    # Desktop usa coordenadas 1920x1080: amplia até caber (cavalos incluídos).
    var ui_scale = 1.0 if mobile else clampf((area.size.y - 40.0) / (wanted + above), 0.7, 1.25)
    panel.scale = Vector2.ONE * ui_scale
    var height = minf(wanted, (area.size.y - (above + 12.0) * ui_scale) / ui_scale)
    # Se vai rolar, deixa espaço para a barra de rolagem não cobrir os campos.
    if wanted > height + 1.0: box.custom_minimum_size.x = width - style.content_margin_left * 2.0 - 14.0
    scroll.custom_minimum_size = Vector2(box.custom_minimum_size.x, height - style.content_margin_top - style.content_margin_bottom)
    panel.custom_minimum_size = Vector2.ZERO
    panel.reset_size()
    panel.size = Vector2(width, height)
    var free_y = area.size.y - panel.size.y * ui_scale
    panel.position = Vector2(area.position.x + (area.size.x - panel.size.x * ui_scale) / 2.0, area.position.y + maxf(above * ui_scale, free_y / 2.0 + above * ui_scale * 0.35))
    frame.position = panel.position
    frame.size = panel.size
    frame.scale = panel.scale

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
    var holder = Widgets.Field.new()
    holder.name = "Field_" + key
    holder.custom_minimum_size.y = 58
    holder.setup("lock" if secret else ("mail" if key == "email" else "person_add"), secret)
    var e: LineEdit = holder.line
    e.placeholder_text = placeholder
    if key == "email": e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
    if secret: e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
    box.add_child(holder)
    # Web no celular: campo HTML real por cima para o teclado virtual abrir.
    WebTextField.attach(e)
    fields[key] = e
    return e

func _button(text: String, action: Callable, primary := false) -> Button:
    var b = Widgets.OrnateButton.new()
    b.text = text
    b.label = text
    b.primary = primary
    var mobile = Mobile.active(get_viewport())
    b.font_size = (22 if mobile else 30) if primary else (15 if mobile else 19)
    b.custom_minimum_size.y = (58 if mobile else 72) if primary else (50 if mobile else 60)
    if "GOOGLE" in text: b.icon_kind = "google"
    b.pressed.connect(action)
    box.add_child(b)
    return b

const LINK_ICONS = {"Criar conta": "person_add", "Esqueci minha senha": "key", "Jogar como convidado": "persons"}

func _link(text: String, action: Callable) -> Button:
    var b = Widgets.Link.new()
    b.text = text
    b.icon_kind = LINK_ICONS.get(text, "")
    b.custom_minimum_size.y = 42
    b.add_theme_font_size_override("font_size", 16 if Mobile.active(get_viewport()) else 19)
    b.pressed.connect(action)
    # Links centralizados em coluna (largura do maior), como na referência.
    if links_box == null:
        var center = CenterContainer.new()
        box.add_child(center)
        links_box = VBoxContainer.new()
        links_box.add_theme_constant_override("separation", 2)
        center.add_child(links_box)
    links_box.add_child(b)
    return b

var links_box: VBoxContainer = null

func _divider():
    links_box = null
    var d = Control.new()
    d.custom_minimum_size.y = 18
    d.mouse_filter = Control.MOUSE_FILTER_IGNORE
    d.draw.connect(func(): Art.divider(d, Vector2(8, 9), Vector2(d.size.x - 8, 9)))
    box.add_child(d)
    return d

func _value(key: String) -> String:
    return fields[key].text if fields.has(key) else ""

func _show(target: String):
    page = target
    _clear()
    links_box = null
    var title = _label({"login":"ENTRAR NO FRAIHA", "signup":"CRIAR CONTA", "recover":"RECUPERAR SENHA",
        "new_password":"NOVA SENHA", "nickname":"ESCOLHA SEU NOME NO FRAIHA", "account":"SUA CONTA",
        "waiting":"CONECTANDO…", "unavailable":"CONTAS"}.get(target, "CONTA"), 22, GOLD)
    title.name = "Title"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_override("font", Art.FONT_BOLD)
    title.add_theme_font_size_override("font_size", 23 if Mobile.active(get_viewport()) else 40)
    title.add_theme_color_override("font_color", Color("f1d58a"))
    title.add_theme_color_override("font_outline_color", Color("2a1905"))
    title.add_theme_constant_override("outline_size", 6)
    title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
    title.add_theme_constant_override("shadow_offset_y", 3)
    _divider()
    if not message.is_empty(): _label(message, 16, Color("f0d9a0"))
    match target:
        "login":
            _input_field("email", "E-mail")
            _input_field("password", "Senha", true).text_submitted.connect(func(_t): account.sign_in(_value("email"), _value("password")))
            _button("ENTRAR", func(): account.sign_in(_value("email"), _value("password")), true)
            _button("CONTINUAR COM GOOGLE", func(): account.sign_in_google("ranked" if return_to_ranked else ""))
            _divider()
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
    if target == "login": _divider()
    status_label = _label("", 15, Color("a9ab9c"))
    status_label.name = "Status"
    status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    # Ícone de informação discreto antes da mensagem (só aparece quando há mensagem).
    var info_icon = Control.new()
    info_icon.custom_minimum_size = Vector2(22, 22)
    info_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    info_icon.draw.connect(func():
        if status_label.text.is_empty(): return
        var font := status_label.get_theme_font("font")
        var fs := status_label.get_theme_font_size("font_size")
        var tw := font.get_string_size(status_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
        var x := (status_label.size.x - minf(tw, status_label.size.x)) / 2.0 - 26.0
        Art.icon(info_icon, "info", Rect2(Vector2(x, 0), Vector2(20, 20)), Color("8d8f80")))
    status_label.add_child(info_icon)
    status_label.resized.connect(info_icon.queue_redraw)
    info_icon.position = Vector2(0, 1)
    message = ""
    if not fields.is_empty() and not Mobile.active(get_viewport()):
        fields.values()[0].grab_focus.call_deferred()
    _layout.call_deferred()
